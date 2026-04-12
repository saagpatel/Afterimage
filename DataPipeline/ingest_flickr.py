#!/usr/bin/env python3
"""Ingest historical photos from Flickr Commons API.

Uses flickr.photos.search with is_commons=1 and geo bounding box params,
paginating per city until 2000 records or API exhausted. Writes staging CSV.

Requires FLICKR_API_KEY environment variable.
"""

import asyncio
import csv
import logging
import os
import re
import sys
from pathlib import Path

import aiohttp
from tqdm import tqdm

from config import (
    CITIES,
    DIRECTION_MAP,
    FLICKR_API_URL,
    FLICKR_ATTRIBUTION_PREFIX,
    FLICKR_LICENSE_MAP,
    FLICKR_MAX_PER_CITY,
    FLICKR_PER_PAGE,
    FLICKR_RATE_LIMIT_SEC,
    FLICKR_USER_AGENT,
    MAX_YEAR,
    MIN_YEAR,
    STAGING_COLUMNS,
    STAGING_DIR,
)

logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s")
log = logging.getLogger(__name__)

# Cities to ingest (NYC is covered by OldNYC; Flickr fills the other five)
TARGET_CITIES = ["sf", "chicago", "dc", "new_orleans", "boston"]


def _api_key() -> str:
    """Return FLICKR_API_KEY from environment, exit with error if missing."""
    key = os.environ.get("FLICKR_API_KEY", "").strip()
    if not key:
        log.error(
            "FLICKR_API_KEY environment variable is not set. "
            "Obtain a key at https://www.flickr.com/services/api/misc.api_keys.html"
        )
        sys.exit(1)
    return key


def _bbox(city_config: dict) -> str:
    """Return Flickr bbox string: lon_min,lat_min,lon_max,lat_max."""
    lat_min, lat_max = city_config["lat_range"]
    lon_min, lon_max = city_config["lon_range"]
    return f"{lon_min},{lat_min},{lon_max},{lat_max}"


def _extract_year(date_taken: str) -> int | None:
    """Parse a 4-digit year from a Flickr date_taken string (YYYY-MM-DD HH:MM:SS)."""
    if not date_taken:
        return None
    match = re.match(r"(\d{4})", date_taken.strip())
    if match:
        year = int(match.group(1))
        return year if MIN_YEAR <= year <= MAX_YEAR else None
    return None


def _extract_heading(text: str) -> tuple[int | None, str]:
    """Scan text tokens for directional words and return (heading_degrees, confidence).

    Confidence is "medium" when a directional word is found, "low" otherwise.
    Returns (None, "low") when no direction is detected.
    """
    if not text:
        return None, "low"
    tokens = re.findall(r"[a-z]+", text.lower())
    for token in tokens:
        if token in DIRECTION_MAP:
            return DIRECTION_MAP[token], "medium"
    return None, "low"


def _rights_uri(license_id: str) -> str:
    """Map a Flickr license ID to a rights URI."""
    return FLICKR_LICENSE_MAP.get(str(license_id), "")


def _extract_record(photo: dict, city_name: str) -> dict | None:
    """Build a staging row from a Flickr photo dict.

    Returns None if the photo lacks required fields or falls outside the date range.
    """
    photo_id = photo.get("id", "")
    if not photo_id:
        return None

    title = photo.get("title", "").strip()[:300]
    description = (
        photo.get("description", {}).get("_content", "")
        if isinstance(photo.get("description"), dict)
        else photo.get("description", "")
    ).strip()[:500]

    date_taken = photo.get("datetaken", "")
    year = _extract_year(date_taken)
    # Skip photos outside the historical window only when we have a date
    if year is not None and not (MIN_YEAR <= year <= MAX_YEAR):
        return None

    # Lat/lon — present when extras=geo is requested
    try:
        lat = float(photo.get("latitude", 0))
        lon = float(photo.get("longitude", 0))
    except (TypeError, ValueError):
        return None
    if lat == 0.0 and lon == 0.0:
        return None

    # Thumbnail: url_n (320px) preferred, url_m (240px) fallback
    thumbnail_url = photo.get("url_n") or photo.get("url_m", "")
    if not thumbnail_url:
        return None

    # Full-res: url_o (original) preferred, url_m fallback
    full_res_url = photo.get("url_o") or photo.get("url_m", "")

    # Heading from title then tags
    tags = photo.get("tags", "")
    heading, heading_confidence = _extract_heading(title + " " + tags)

    owner_name = photo.get("ownername", "").strip() or "Unknown"
    attribution = f"{FLICKR_ATTRIBUTION_PREFIX} / {owner_name}"

    license_id = str(photo.get("license", ""))
    rights = _rights_uri(license_id)

    return {
        "id": f"flickr:{photo_id}",
        "source": "flickr_commons",
        "title": title,
        "description": re.sub(r"<[^>]+>", "", description).strip()[:500],
        "date_text": date_taken[:100],
        "date_year": year if year is not None else "",
        "lat": lat,
        "lon": lon,
        "city": city_name,
        "heading": heading if heading is not None else "",
        "heading_confidence": heading_confidence,
        "thumbnail_url": thumbnail_url,
        "full_res_url": full_res_url,
        "attribution": attribution,
        "rights_uri": rights,
    }


async def fetch_page(
    session: aiohttp.ClientSession,
    api_key: str,
    city_name: str,
    bbox: str,
    page: int,
    semaphore: asyncio.Semaphore,
) -> tuple[list[dict], int]:
    """Fetch one page of Flickr search results for a city bounding box.

    Returns (photos_list, total_pages).
    """
    params = {
        "method": "flickr.photos.search",
        "api_key": api_key,
        "is_commons": "1",
        "bbox": bbox,
        "min_taken_date": f"{MIN_YEAR}-01-01",
        "max_taken_date": f"{MAX_YEAR}-12-31",
        "extras": "geo,url_n,url_m,url_o,description,date_taken,owner_name,license,tags",
        "per_page": str(FLICKR_PER_PAGE),
        "page": str(page),
        "format": "json",
        "nojsoncallback": "1",
    }

    async with semaphore:
        try:
            async with session.get(FLICKR_API_URL, params=params) as resp:
                if resp.status == 429:
                    log.warning("%s p%d: rate limited (429), backing off 5s", city_name, page)
                    await asyncio.sleep(5.0)
                    return [], 0
                if resp.status != 200:
                    log.warning("%s p%d: HTTP %d", city_name, page, resp.status)
                    return [], 0
                data = await resp.json()
        except (aiohttp.ClientError, asyncio.TimeoutError) as exc:
            log.warning("%s p%d: request error: %s", city_name, page, exc)
            return [], 0
        finally:
            # Always honour the rate limit between requests
            await asyncio.sleep(FLICKR_RATE_LIMIT_SEC)

    if data.get("stat") != "ok":
        log.warning("%s p%d: API error: %s", city_name, page, data.get("message", "unknown"))
        return [], 0

    photos_block = data.get("photos", {})
    total_pages = int(photos_block.get("pages", 0))
    photos = photos_block.get("photo", [])
    return photos, total_pages


async def ingest_city(
    session: aiohttp.ClientSession,
    api_key: str,
    city_name: str,
    city_config: dict,
    seen_ids: set[str],
) -> list[dict]:
    """Paginate through Flickr search results for one city.

    Stops when FLICKR_MAX_PER_CITY unique records are collected or pages are exhausted.
    """
    bbox = _bbox(city_config)
    semaphore = asyncio.Semaphore(1)  # Sequential requests to respect 1 req/sec
    records: list[dict] = []
    page = 1
    total_pages: int | None = None

    pbar = tqdm(desc=f"{city_name.upper()} pages", unit="page")
    while True:
        photos, pages_returned = await fetch_page(
            session, api_key, city_name, bbox, page, semaphore
        )

        if total_pages is None:
            total_pages = pages_returned
            pbar.total = total_pages
            pbar.refresh()

        for photo in photos:
            photo_id = f"flickr:{photo.get('id', '')}"
            if photo_id in seen_ids:
                continue
            record = _extract_record(photo, city_name)
            if record:
                seen_ids.add(photo_id)
                records.append(record)

        pbar.update(1)
        pbar.set_postfix(collected=len(records))

        if len(records) >= FLICKR_MAX_PER_CITY:
            log.info("%s: reached cap of %d records", city_name.upper(), FLICKR_MAX_PER_CITY)
            break
        if page >= (total_pages or 1):
            break
        page += 1

    pbar.close()
    log.info("%s: %d records collected (cap=%d)", city_name.upper(), len(records), FLICKR_MAX_PER_CITY)
    return records


async def ingest() -> Path:
    """Run the Flickr Commons ingestion pipeline. Returns path to staging CSV."""
    api_key = _api_key()
    STAGING_DIR.mkdir(parents=True, exist_ok=True)
    output_path = STAGING_DIR / "staging_flickr.csv"

    seen_ids: set[str] = set()
    all_records: list[dict] = []
    city_counts: dict[str, int] = {}

    headers = {"User-Agent": FLICKR_USER_AGENT}
    timeout = aiohttp.ClientTimeout(total=30)

    async with aiohttp.ClientSession(headers=headers, timeout=timeout) as session:
        for city_name in TARGET_CITIES:
            city_config = CITIES[city_name]
            records = await ingest_city(session, api_key, city_name, city_config, seen_ids)
            all_records.extend(records)
            city_counts[city_name] = len(records)

    # Write CSV
    with open(output_path, "w", newline="", encoding="utf-8") as f:
        writer = csv.DictWriter(f, fieldnames=STAGING_COLUMNS)
        writer.writeheader()
        writer.writerows(all_records)

    log.info("Wrote %d total rows → %s", len(all_records), output_path)
    log.info("Per-city counts: %s", ", ".join(f"{c.upper()}={n}" for c, n in city_counts.items()))

    return output_path


if __name__ == "__main__":
    output = asyncio.run(ingest())
    log.info("Done. Output: %s", output)
