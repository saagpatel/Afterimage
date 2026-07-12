#!/usr/bin/env python3
"""Ingest historical photos from Wikimedia Commons geosearch API.

Tiles city bounding boxes, queries the geosearch API for each tile,
filters for historical content, and writes a staging CSV.
"""

import asyncio
import csv
import logging
import math
import re
import sys
import tempfile
from pathlib import Path

import aiohttp
from tqdm import tqdm

from config import (
    CITIES,
    HISTORICAL_KEEP_CATEGORIES,
    HISTORICAL_REJECT_CATEGORIES,
    MAX_YEAR,
    MIN_YEAR,
    STAGING_COLUMNS,
    STAGING_DIR,
    WIKIMEDIA_API_URL,
    WIKIMEDIA_ATTRIBUTION,
    WIKIMEDIA_MAX_RETRIES,
    WIKIMEDIA_RATE_LIMIT_SEC,
    WIKIMEDIA_RESULTS_PER_TILE,
    WIKIMEDIA_SEARCH_RADIUS_M,
    WIKIMEDIA_TILE_SPACING_M,
    WIKIMEDIA_USER_AGENT,
)

logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s")
log = logging.getLogger(__name__)


def generate_tile_centers(lat_range: tuple, lon_range: tuple, spacing_m: float) -> list[tuple[float, float]]:
    """Generate a grid of tile centers covering the bounding box.

    spacing_m is the distance between tile centers in meters.
    Returns list of (lat, lon) tuples.
    """
    lat_min, lat_max = lat_range
    lon_min, lon_max = lon_range

    # Convert spacing from meters to degrees
    lat_step = spacing_m / 111_320  # 1° lat ≈ 111,320m
    mid_lat = (lat_min + lat_max) / 2
    lon_step = spacing_m / (111_320 * math.cos(math.radians(mid_lat)))

    centers = []
    lat = lat_min
    row = 0
    while lat <= lat_max:
        # Offset every other row by half spacing for hexagonal packing
        offset = lon_step / 2 if row % 2 else 0
        lon = lon_min + offset
        while lon <= lon_max:
            centers.append((round(lat, 6), round(lon, 6)))
            lon += lon_step
        lat += lat_step
        row += 1

    return centers


def parse_year_from_date_string(date_str: str) -> int | None:
    """Parse a year from Wikimedia's DateTimeOriginal field.

    Handles formats like:
    - "Taken on 18 November 2024, 19:34:52"
    - "1920-01-01"
    - "circa 1885"
    - "between 1900 and 1910"
    - "1935"
    """
    if not date_str:
        return None

    # Try 4-digit year patterns
    match = re.search(r"\b(1[0-9]{3}|20[0-2]\d)\b", date_str)
    if match:
        return int(match.group(1))
    return None


def is_historical(extmetadata: dict) -> tuple[bool, int | None]:
    """Determine if a Wikimedia file is a historical photo.

    Returns (is_historical, year).
    """
    # Extract date
    date_field = extmetadata.get("DateTimeOriginal", {}).get("value", "")
    year = parse_year_from_date_string(date_field)

    # Extract categories
    categories_str = extmetadata.get("Categories", {}).get("value", "").lower()
    categories = [c.strip() for c in categories_str.split("|")] if categories_str else []

    # Reject if modern indicators present
    for reject_kw in HISTORICAL_REJECT_CATEGORIES:
        if any(reject_kw in cat for cat in categories):
            if year and year < 1970:
                break  # Override reject if we have a confirmed old date
            return False, year

    # Accept if year < 1970
    if year is not None and year < 1970:
        return True, year

    # Accept if historical category keywords present
    for keep_kw in HISTORICAL_KEEP_CATEGORIES:
        if any(keep_kw in cat for cat in categories):
            return True, year

    # Check description for historical hints
    desc = extmetadata.get("ImageDescription", {}).get("value", "").lower()
    historical_desc_keywords = ["circa", "vintage", "historic", "archival", "19th century"]
    if any(kw in desc for kw in historical_desc_keywords):
        return True, year

    # No evidence of being historical
    return False, year


def extract_record(page: dict, geosearch_lat: float, geosearch_lon: float) -> dict | None:
    """Extract a staging record from a Wikimedia API page result.

    Returns None if the page should be filtered out.
    """
    pageid = page.get("pageid")
    title = page.get("title", "")
    imageinfo_list = page.get("imageinfo", [])

    if not imageinfo_list:
        return None

    info = imageinfo_list[0]
    extmetadata = info.get("extmetadata", {})

    historical, year = is_historical(extmetadata)
    if not historical:
        return None

    # Validate year range
    if year is not None and not (MIN_YEAR <= year <= MAX_YEAR):
        return None

    thumbnail_url = info.get("thumburl", "")
    full_res_url = info.get("url", "")
    if not thumbnail_url:
        return None

    # Extract description (strip HTML tags)
    desc_html = extmetadata.get("ImageDescription", {}).get("value", "")
    description = re.sub(r"<[^>]+>", "", desc_html).strip()[:500]

    # Extract license URL
    rights_uri = extmetadata.get("LicenseUrl", {}).get("value", "")

    # Clean title (remove "File:" prefix)
    clean_title = title.removeprefix("File:").rsplit(".", 1)[0].replace("_", " ")

    # Extract date text
    date_text = extmetadata.get("DateTimeOriginal", {}).get("value", "")
    # Clean up common Wikimedia date formats
    date_text = re.sub(r"<[^>]+>", "", date_text).strip()[:100]

    return {
        "id": f"wikimedia:{pageid}",
        "source": "wikimedia",
        "title": clean_title[:300],
        "description": description,
        "date_text": date_text,
        "date_year": year if year else "",
        "lat": geosearch_lat,
        "lon": geosearch_lon,
        "city": "",
        "heading": "",
        "heading_confidence": "low",
        "thumbnail_url": thumbnail_url,
        "full_res_url": full_res_url,
        "attribution": WIKIMEDIA_ATTRIBUTION,
        "rights_uri": rights_uri,
    }


async def fetch_tile(
    session: aiohttp.ClientSession,
    lat: float,
    lon: float,
    seen_pageids: set[int],
    semaphore: asyncio.Semaphore,
) -> list[dict]:
    """Fetch and filter results for a single tile center."""
    params = {
        "action": "query",
        "generator": "geosearch",
        "ggscoord": f"{lat}|{lon}",
        "ggsradius": WIKIMEDIA_SEARCH_RADIUS_M,
        "ggsnamespace": 6,
        "ggslimit": WIKIMEDIA_RESULTS_PER_TILE,
        "prop": "imageinfo",
        "iiprop": "url|extmetadata",
        "iiurlwidth": 300,
        "iiextmetadatafilter": "DateTimeOriginal|Categories|ImageDescription|License|LicenseShortName|LicenseUrl",
        "format": "json",
    }

    async with semaphore:
        for attempt in range(WIKIMEDIA_MAX_RETRIES):
            try:
                async with session.get(WIKIMEDIA_API_URL, params=params) as resp:
                    if resp.status == 429:
                        wait = float(
                            resp.headers.get(
                                "Retry-After",
                                (2 ** attempt) * WIKIMEDIA_RATE_LIMIT_SEC,
                            )
                        )
                        log.warning("Rate limited, waiting %.1fs", wait)
                        await asyncio.sleep(wait)
                        continue
                    if resp.status != 200:
                        raise RuntimeError(
                            f"Wikimedia returned HTTP {resp.status} for tile ({lat:.4f}, {lon:.4f})"
                        )
                    data = await resp.json()
            except (aiohttp.ClientError, asyncio.TimeoutError) as exc:
                log.warning("Request error for tile (%.4f, %.4f): %s", lat, lon, exc)
                if attempt < WIKIMEDIA_MAX_RETRIES - 1:
                    await asyncio.sleep((2 ** attempt) * WIKIMEDIA_RATE_LIMIT_SEC)
                    continue
                raise RuntimeError(
                    f"Wikimedia request failed for tile ({lat:.4f}, {lon:.4f})"
                ) from exc

            # Rate limit
            await asyncio.sleep(WIKIMEDIA_RATE_LIMIT_SEC)
            break
        else:
            raise RuntimeError(
                f"Wikimedia remained rate limited for tile ({lat:.4f}, {lon:.4f})"
            )

    pages = data.get("query", {}).get("pages", {})
    records = []

    for page_id_str, page in pages.items():
        pageid = page.get("pageid")
        if pageid is None or pageid in seen_pageids:
            continue
        seen_pageids.add(pageid)

        # Use coordinates from the page's geosearch data if available
        page_lat = page.get("coordinates", [{}])[0].get("lat", lat) if "coordinates" in page else lat
        page_lon = page.get("coordinates", [{}])[0].get("lon", lon) if "coordinates" in page else lon

        record = extract_record(page, page_lat, page_lon)
        if record:
            records.append(record)

    return records


async def ingest_city(
    session: aiohttp.ClientSession,
    city_name: str,
    city_config: dict,
    seen_pageids: set[int],
) -> list[dict]:
    """Ingest all tiles for a single city."""
    centers = generate_tile_centers(
        city_config["lat_range"],
        city_config["lon_range"],
        WIKIMEDIA_TILE_SPACING_M,
    )
    log.info("%s: %d tile centers generated", city_name.upper(), len(centers))

    # Process tiles sequentially (rate limit = 1 req/sec, semaphore enforces this)
    semaphore = asyncio.Semaphore(1)
    all_records: list[dict] = []
    total_pages_seen = 0

    pbar = tqdm(centers, desc=f"{city_name.upper()} tiles", unit="tile")
    for lat, lon in pbar:
        records = await fetch_tile(session, lat, lon, seen_pageids, semaphore)
        all_records.extend(records)
        pbar.set_postfix(historical=len(all_records))

    log.info("%s: %d historical photos found from %d tiles", city_name.upper(), len(all_records), len(centers))
    return all_records


async def ingest() -> Path:
    """Run the Wikimedia ingestion pipeline. Returns path to staging CSV."""
    STAGING_DIR.mkdir(parents=True, exist_ok=True)
    output_path = STAGING_DIR / "staging_wikimedia.csv"

    seen_pageids: set[int] = set()
    all_records: list[dict] = []

    headers = {"User-Agent": WIKIMEDIA_USER_AGENT}
    timeout = aiohttp.ClientTimeout(total=30)

    async with aiohttp.ClientSession(headers=headers, timeout=timeout) as session:
        # Run SF first for early density read (smaller, faster)
        for city_name in ["sf", "nyc", "chicago", "dc", "new_orleans", "boston"]:
            city_config = CITIES[city_name]
            records = await ingest_city(session, city_name, city_config, seen_pageids)
            all_records.extend(records)

            # Early warning for SF
            if city_name == "sf":
                sf_count = len(records)
                log.info("SF yield: %d historical photos", sf_count)
                if sf_count < 200:
                    log.warning(
                        "SF yield below 200 — consider Flickr Commons contingency (ingest_flickr.py)"
                    )

    if not all_records:
        raise RuntimeError("Wikimedia ingestion returned no historical records")

    # Replace staging data only after the full ingestion succeeds. A provider
    # failure must never erase the last known-good snapshot with partial data.
    with tempfile.NamedTemporaryFile(
        "w",
        newline="",
        encoding="utf-8",
        dir=output_path.parent,
        prefix=f".{output_path.name}.",
        delete=False,
    ) as temporary_file:
        writer = csv.DictWriter(temporary_file, fieldnames=STAGING_COLUMNS)
        writer.writeheader()
        writer.writerows(all_records)
        temporary_path = Path(temporary_file.name)
    temporary_path.replace(output_path)

    log.info("Wrote %d total rows → %s", len(all_records), output_path)

    # Per-city breakdown
    sf_records = [r for r in all_records if CITIES["sf"]["lat_range"][0] <= r["lat"] <= CITIES["sf"]["lat_range"][1]]
    nyc_records = [r for r in all_records if CITIES["nyc"]["lat_range"][0] <= r["lat"] <= CITIES["nyc"]["lat_range"][1]]
    log.info("Breakdown: NYC=%d, SF=%d", len(nyc_records), len(sf_records))

    return output_path


if __name__ == "__main__":
    output = asyncio.run(ingest())
    log.info("Done. Output: %s", output)
