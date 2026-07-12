#!/usr/bin/env python3
"""Ingest historical photos from Wikimedia Commons via category membership.

Targets HABS/HAER collections plus historical photograph categories for
all non-NYC cities. Geocodes addresses from descriptions via Nominatim
when photos lack GPS coordinates.

No API key required — uses the public MediaWiki Action API.
"""

import asyncio
import csv
import logging
import re
import sys
import tempfile
from pathlib import Path

import aiohttp
from tqdm import tqdm

from config import (
    CITIES,
    MAX_YEAR,
    MIN_YEAR,
    STAGING_COLUMNS,
    STAGING_DIR,
    WIKIMEDIA_API_URL,
    WIKIMEDIA_ATTRIBUTION,
    WIKIMEDIA_RATE_LIMIT_SEC,
    WIKIMEDIA_USER_AGENT,
)

logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s")
log = logging.getLogger(__name__)

# Nominatim geocoding (free, 1 req/sec)
NOMINATIM_URL = "https://nominatim.openstreetmap.org/search"
NOMINATIM_USER_AGENT = "AfterimageBot/0.1 (historical photo geocoder)"

# Per-city category lists and geocoding context
CITY_CATEGORIES: dict[str, dict] = {
    "sf": {
        "categories": [
            "Category:Historic American Buildings Survey in San Francisco",
            "Category:Historic American Engineering Record in San Francisco",
            "Category:Historic American Buildings Survey in California",
            "Category:19th-century photographs of San Francisco",
            "Category:Early 20th-century photographs of San Francisco",
            "Category:Historical images of San Francisco",
        ],
        "geocode_suffix": ", San Francisco, CA",
        "geocode_bounds": (37.6, 37.9, -122.6, -122.3),
    },
    "chicago": {
        "categories": [
            "Category:Historic American Buildings Survey in Chicago",
            "Category:Historic American Buildings Survey in Illinois",
            "Category:Historic American Engineering Record in Illinois",
            "Category:19th-century photographs of Chicago",
            "Category:Early 20th-century photographs of Chicago",
            "Category:Historical images of Chicago",
            "Category:Old photographs of Chicago",
        ],
        "geocode_suffix": ", Chicago, IL",
        "geocode_bounds": (41.6, 42.1, -88.0, -87.4),
    },
    "dc": {
        "categories": [
            "Category:Historic American Buildings Survey in Washington, D.C.",
            "Category:Historic American Engineering Record in Washington, D.C.",
            "Category:19th-century photographs of Washington, D.C.",
            "Category:Early 20th-century photographs of Washington, D.C.",
            "Category:Historical images of Washington, D.C.",
            "Category:Old photographs of Washington, D.C.",
        ],
        "geocode_suffix": ", Washington, DC",
        "geocode_bounds": (38.7, 39.1, -77.2, -76.8),
    },
    "new_orleans": {
        "categories": [
            "Category:Historic American Buildings Survey in New Orleans",
            "Category:Historic American Buildings Survey in Louisiana",
            "Category:Historic American Engineering Record in Louisiana",
            "Category:19th-century photographs of New Orleans",
            "Category:Historical images of New Orleans",
            "Category:Old photographs of New Orleans",
        ],
        "geocode_suffix": ", New Orleans, LA",
        "geocode_bounds": (29.8, 30.1, -90.2, -89.9),
    },
    "boston": {
        "categories": [
            "Category:Historic American Buildings Survey in Boston",
            "Category:Historic American Buildings Survey in Massachusetts",
            "Category:Historic American Engineering Record in Massachusetts",
            "Category:19th-century photographs of Boston",
            "Category:Early 20th-century photographs of Boston",
            "Category:Historical images of Boston",
            "Category:Old photographs of Boston",
        ],
        "geocode_suffix": ", Boston, MA",
        "geocode_bounds": (42.2, 42.5, -71.2, -70.9),
    },
}


async def fetch_json(
    session: aiohttp.ClientSession,
    *,
    params: dict,
    context: str,
    max_attempts: int = 5,
) -> dict:
    """Fetch JSON with provider-friendly pacing and bounded retry/backoff."""
    for attempt in range(max_attempts):
        try:
            async with session.get(WIKIMEDIA_API_URL, params=params) as resp:
                if resp.status == 429:
                    retry_after = float(resp.headers.get("Retry-After", 2 ** attempt))
                    log.warning("Rate limited while fetching %s; retrying in %.1fs", context, retry_after)
                    await asyncio.sleep(retry_after)
                    continue
                resp.raise_for_status()
                return await resp.json()
        except (aiohttp.ClientError, asyncio.TimeoutError) as exc:
            if attempt == max_attempts - 1:
                raise RuntimeError(f"Wikimedia request failed for {context}") from exc
            delay = 2 ** attempt
            log.warning("Error fetching %s: %s; retrying in %ss", context, exc, delay)
            await asyncio.sleep(delay)
        finally:
            await asyncio.sleep(WIKIMEDIA_RATE_LIMIT_SEC)

    raise RuntimeError(f"Wikimedia remained rate limited for {context}")


def extract_address_from_text(text: str) -> str | None:
    """Extract a street address from description or title text."""
    clean = re.sub(r"<[^>]+>", " ", text)

    # Pattern: Number + Street name + Street type
    street_pattern = re.compile(
        r"(\d+[\-\d]*\s+(?:[NSEW]\.?\s+)?(?:\w+\s+){1,3}"
        r"(?:Street|St|Avenue|Ave|Boulevard|Blvd|Road|Rd|Drive|Dr|Way|Place|Pl|Lane|Ln|Court|Ct|Terrace|Highway|Hwy))",
        re.IGNORECASE,
    )
    match = street_pattern.search(clean)
    if match:
        return match.group(0).strip().rstrip(",")

    return None


async def geocode_address(
    session: aiohttp.ClientSession,
    address: str,
    bounds: tuple[float, float, float, float],
    semaphore: asyncio.Semaphore,
) -> tuple[float, float] | None:
    """Geocode an address using Nominatim. Returns (lat, lon) or None."""
    params = {
        "q": address,
        "format": "json",
        "limit": 1,
        "countrycodes": "us",
    }
    async with semaphore:
        try:
            headers = {"User-Agent": NOMINATIM_USER_AGENT}
            async with session.get(NOMINATIM_URL, params=params, headers=headers) as resp:
                if resp.status != 200:
                    return None
                data = await resp.json()
        except (aiohttp.ClientError, asyncio.TimeoutError):
            return None
        finally:
            await asyncio.sleep(WIKIMEDIA_RATE_LIMIT_SEC)

    if not data:
        return None

    lat = float(data[0]["lat"])
    lon = float(data[0]["lon"])

    lat_min, lat_max, lon_min, lon_max = bounds
    if not (lat_min <= lat <= lat_max and lon_min <= lon <= lon_max):
        return None

    return lat, lon


async def fetch_category_members(
    session: aiohttp.ClientSession,
    category: str,
) -> list[dict]:
    """Fetch all file members of a Wikimedia Commons category."""
    members = []
    cmcontinue = None

    while True:
        params = {
            "action": "query",
            "list": "categorymembers",
            "cmtitle": category,
            "cmtype": "file",
            "cmlimit": "max",
            "format": "json",
        }
        if cmcontinue:
            params["cmcontinue"] = cmcontinue

        data = await fetch_json(session, params=params, context=category)

        batch = data.get("query", {}).get("categorymembers", [])
        members.extend(batch)

        if "continue" in data:
            cmcontinue = data["continue"]["cmcontinue"]
        else:
            break

    return members


async def fetch_page_metadata(
    session: aiohttp.ClientSession,
    pageids: list[int],
) -> dict:
    """Fetch imageinfo + extmetadata for a batch of page IDs (max 50)."""
    params = {
        "action": "query",
        "pageids": "|".join(str(p) for p in pageids[:50]),
        "prop": "imageinfo|coordinates",
        "iiprop": "url|extmetadata",
        "iiurlwidth": 300,
        "iiextmetadatafilter": "DateTimeOriginal|Categories|ImageDescription|License|LicenseUrl|GPSLatitude|GPSLongitude",
        "format": "json",
    }
    data = await fetch_json(
        session,
        params=params,
        context=f"metadata batch beginning {pageids[0] if pageids else 'empty'}",
    )

    return data.get("query", {}).get("pages", {})


def parse_year(text: str) -> int | None:
    """Extract a 4-digit historical year from text."""
    match = re.search(r"\b(1[0-9]{3})\b", text)
    if match:
        year = int(match.group(1))
        return year if MIN_YEAR <= year <= MAX_YEAR else None
    return None


async def ingest_city(
    session: aiohttp.ClientSession,
    city_name: str,
    city_config: dict,
    global_seen: set[int],
    geocode_semaphore: asyncio.Semaphore,
) -> list[dict]:
    """Ingest all categories for a single city."""
    categories = city_config["categories"]
    geocode_suffix = city_config["geocode_suffix"]
    geocode_bounds = city_config["geocode_bounds"]

    # Step 1: Collect all page IDs from categories
    local_pageids: list[int] = []
    for category in categories:
        members = await fetch_category_members(session, category)
        new_count = 0
        for m in members:
            pid = m["pageid"]
            if pid not in global_seen:
                global_seen.add(pid)
                local_pageids.append(pid)
                new_count += 1
        log.info("  %s: %d files (%d new)", category, len(members), new_count)

    log.info("%s: %d unique files to process", city_name.upper(), len(local_pageids))

    # Step 2: Fetch metadata in batches of 50
    all_pages: dict = {}
    for i in range(0, len(local_pageids), 50):
        batch = local_pageids[i : i + 50]
        pages = await fetch_page_metadata(session, batch)
        all_pages.update(pages)

    # Step 3: Extract records
    records: list[dict] = []
    stats = {"geotagged": 0, "geocoded": 0, "failed_geo": 0, "no_thumb": 0}

    pbar = tqdm(all_pages.items(), desc=f"{city_name.upper()} records", unit="page")
    for pid_str, page in pbar:
        title = page.get("title", "")
        ii = page.get("imageinfo", [])
        if not ii:
            continue
        info = ii[0]
        ext = info.get("extmetadata", {})

        # Try GPS from metadata
        lat, lon = None, None
        gps_lat = ext.get("GPSLatitude", {}).get("value")
        gps_lon = ext.get("GPSLongitude", {}).get("value")
        if gps_lat and gps_lon:
            try:
                lat, lon = float(gps_lat), float(gps_lon)
                stats["geotagged"] += 1
            except (ValueError, TypeError):
                pass

        # Check coordinates property
        if lat is None and "coordinates" in page:
            coords = page["coordinates"]
            if coords:
                lat = coords[0].get("lat")
                lon = coords[0].get("lon")
                if lat is not None and lon is not None:
                    stats["geotagged"] += 1

        # Geocode from address if no GPS
        if lat is None:
            desc = ext.get("ImageDescription", {}).get("value", "")
            address = extract_address_from_text(desc + " " + title)
            if address:
                full_address = address + geocode_suffix
                result = await geocode_address(session, full_address, geocode_bounds, geocode_semaphore)
                if result:
                    lat, lon = result
                    stats["geocoded"] += 1
                else:
                    stats["failed_geo"] += 1
            else:
                stats["failed_geo"] += 1

        if lat is None or lon is None:
            continue

        # Verify within city bounds (wider check)
        lat_min, lat_max, lon_min, lon_max = geocode_bounds
        if not (lat_min <= lat <= lat_max and lon_min <= lon <= lon_max):
            continue

        # Extract fields
        desc_html = ext.get("ImageDescription", {}).get("value", "")
        description = re.sub(r"<[^>]+>", "", desc_html).strip()[:500]

        date_str = ext.get("DateTimeOriginal", {}).get("value", "")
        date_text = re.sub(r"<[^>]+>", "", date_str).strip()[:100]
        date_year = parse_year(date_text)

        clean_title = title.removeprefix("File:").rsplit(".", 1)[0].replace("_", " ")[:300]
        thumbnail_url = info.get("thumburl", "")
        full_res_url = info.get("url", "")
        rights_uri = ext.get("LicenseUrl", {}).get("value", "")

        if not thumbnail_url:
            stats["no_thumb"] += 1
            continue

        records.append({
            "id": f"wikimedia:{page.get('pageid', pid_str)}",
            "source": "wikimedia",
            "title": clean_title,
            "description": description,
            "date_text": date_text,
            "date_year": date_year if date_year else "",
            "lat": lat,
            "lon": lon,
            "city": city_name,
            "heading": "",
            "heading_confidence": "low",
            "thumbnail_url": thumbnail_url,
            "full_res_url": full_res_url,
            "attribution": WIKIMEDIA_ATTRIBUTION,
            "rights_uri": rights_uri,
        })
        pbar.set_postfix(found=len(records))

    pbar.close()
    log.info("%s: %d records (geotagged=%d, geocoded=%d, failed=%d, no_thumb=%d)",
             city_name.upper(), len(records), stats["geotagged"], stats["geocoded"],
             stats["failed_geo"], stats["no_thumb"])
    return records


async def ingest() -> Path:
    """Run the category-based ingestion pipeline for all non-NYC cities."""
    STAGING_DIR.mkdir(parents=True, exist_ok=True)
    output_path = STAGING_DIR / "staging_wikimedia_categories.csv"

    headers = {"User-Agent": WIKIMEDIA_USER_AGENT}
    timeout = aiohttp.ClientTimeout(total=30)
    geocode_semaphore = asyncio.Semaphore(1)

    global_seen: set[int] = set()
    all_records: list[dict] = []
    city_counts: dict[str, int] = {}

    async with aiohttp.ClientSession(headers=headers, timeout=timeout) as session:
        for city_name, city_config in CITY_CATEGORIES.items():
            log.info("=== %s ===", city_name.upper())
            records = await ingest_city(
                session, city_name, city_config, global_seen, geocode_semaphore
            )
            all_records.extend(records)
            city_counts[city_name] = len(records)

    if not all_records:
        raise RuntimeError("Wikimedia category ingestion produced no records; refusing to replace staging data")

    # Write atomically so an interrupted or failed provider run cannot replace a
    # previously usable staging file with an empty or partial result.
    with tempfile.NamedTemporaryFile(
        "w",
        newline="",
        encoding="utf-8",
        dir=STAGING_DIR,
        prefix="staging_wikimedia_categories.",
        suffix=".tmp",
        delete=False,
    ) as f:
        writer = csv.DictWriter(f, fieldnames=STAGING_COLUMNS)
        writer.writeheader()
        writer.writerows(all_records)
        temporary_path = Path(f.name)
    temporary_path.replace(output_path)

    log.info("=== SUMMARY ===")
    log.info("Total: %d records → %s", len(all_records), output_path)
    for city, count in city_counts.items():
        log.info("  %s: %d", city.upper(), count)

    return output_path


if __name__ == "__main__":
    output = asyncio.run(ingest())
    log.info("Done. Output: %s", output)
