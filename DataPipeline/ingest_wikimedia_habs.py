#!/usr/bin/env python3
"""Ingest HABS/HAER historical photos from Wikimedia Commons categories.

Unlike the geosearch approach, this fetches photos by category membership
(which includes non-geotagged photos) and geocodes addresses from descriptions.
Primary target: San Francisco HABS collection.
"""

import asyncio
import csv
import logging
import re
import sys
from pathlib import Path

import aiohttp

from config import (
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

# HABS/HAER categories to search
HABS_CATEGORIES = [
    "Category:Historic American Buildings Survey in San Francisco",
    "Category:Historic American Engineering Record in San Francisco",
    "Category:Historic American Buildings Survey in California",
]

# Nominatim geocoding (free, 1 req/sec)
NOMINATIM_URL = "https://nominatim.openstreetmap.org/search"


def extract_address_from_description(description: str, title: str) -> str | None:
    """Extract a street address from HABS description or title text.

    HABS titles/descriptions typically contain patterns like:
    - "114 Montgomery Street, San Francisco"
    - "Wells Fargo Building, 420 Montgomery Street"
    - "Mission Dolores, 3321 16th Street, San Francisco"
    """
    # Strip HTML tags
    text = re.sub(r"<[^>]+>", " ", description + " " + title)

    # Pattern 1: Number + Street name + "Street/Avenue/etc." + optional city
    street_pattern = re.compile(
        r"(\d+[\-\d]*\s+(?:[NSEW]\.?\s+)?(?:\w+\s+){1,3}"
        r"(?:Street|St|Avenue|Ave|Boulevard|Blvd|Road|Rd|Drive|Dr|Way|Place|Pl|Lane|Ln|Court|Ct|Terrace|Highway|Hwy))"
        r"(?:\s*,?\s*(?:San\s+Francisco))?",
        re.IGNORECASE,
    )
    match = street_pattern.search(text)
    if match:
        addr = match.group(0).strip().rstrip(",")
        # Ensure San Francisco is appended for geocoding
        if "san francisco" not in addr.lower():
            addr += ", San Francisco, CA"
        return addr

    # Pattern 2: Named landmark with "San Francisco" context
    if "san francisco" in text.lower():
        # Try to find any street reference
        simple_pattern = re.compile(
            r"(\d+\s+\w+(?:\s+\w+)?\s+(?:Street|St|Ave|Blvd|Rd))",
            re.IGNORECASE,
        )
        match = simple_pattern.search(text)
        if match:
            return match.group(1) + ", San Francisco, CA"

    return None


async def geocode_address(
    session: aiohttp.ClientSession,
    address: str,
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
            async with session.get(NOMINATIM_URL, params=params) as resp:
                if resp.status != 200:
                    return None
                data = await resp.json()
        except (aiohttp.ClientError, asyncio.TimeoutError):
            return None
        finally:
            await asyncio.sleep(WIKIMEDIA_RATE_LIMIT_SEC)

    if not data:
        return None

    result = data[0]
    lat = float(result["lat"])
    lon = float(result["lon"])

    # Sanity check — should be in SF area
    if not (37.6 <= lat <= 37.9 and -122.6 <= lon <= -122.3):
        log.debug("Geocode result outside SF bounds: %s → (%.4f, %.4f)", address, lat, lon)
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

        async with session.get(WIKIMEDIA_API_URL, params=params) as resp:
            data = await resp.json()

        batch = data.get("query", {}).get("categorymembers", [])
        members.extend(batch)

        if "continue" in data:
            cmcontinue = data["continue"]["cmcontinue"]
            await asyncio.sleep(WIKIMEDIA_RATE_LIMIT_SEC)
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
    async with session.get(WIKIMEDIA_API_URL, params=params) as resp:
        data = await resp.json()
    await asyncio.sleep(WIKIMEDIA_RATE_LIMIT_SEC)

    return data.get("query", {}).get("pages", {})


async def ingest() -> Path:
    """Run the HABS category ingestion pipeline."""
    STAGING_DIR.mkdir(parents=True, exist_ok=True)
    output_path = STAGING_DIR / "staging_wikimedia_habs.csv"

    headers = {
        "User-Agent": WIKIMEDIA_USER_AGENT,
    }
    timeout = aiohttp.ClientTimeout(total=30)
    geocode_semaphore = asyncio.Semaphore(1)

    all_records: list[dict] = []
    seen_pageids: set[int] = set()

    async with aiohttp.ClientSession(headers=headers, timeout=timeout) as session:
        # Step 1: Collect all page IDs from HABS categories
        all_members = []
        for category in HABS_CATEGORIES:
            members = await fetch_category_members(session, category)
            log.info("%s: %d files", category, len(members))
            all_members.extend(members)

        # Deduplicate by pageid
        unique_pageids = []
        for m in all_members:
            pid = m["pageid"]
            if pid not in seen_pageids:
                seen_pageids.add(pid)
                unique_pageids.append(pid)

        log.info("Total unique files: %d", len(unique_pageids))

        # Step 2: Fetch metadata in batches of 50
        all_pages: dict = {}
        for i in range(0, len(unique_pageids), 50):
            batch = unique_pageids[i : i + 50]
            pages = await fetch_page_metadata(session, batch)
            all_pages.update(pages)
            log.info("Fetched metadata batch %d-%d", i, i + len(batch))

        # Step 3: Extract records, geocode if needed
        geocoded = 0
        already_geotagged = 0
        geocode_failed = 0

        for pid_str, page in all_pages.items():
            title = page.get("title", "")
            ii = page.get("imageinfo", [{}])
            if not ii:
                continue
            info = ii[0]
            ext = info.get("extmetadata", {})

            # Try GPS from metadata first
            lat = None
            lon = None
            gps_lat = ext.get("GPSLatitude", {}).get("value")
            gps_lon = ext.get("GPSLongitude", {}).get("value")
            if gps_lat and gps_lon:
                try:
                    lat = float(gps_lat)
                    lon = float(gps_lon)
                    already_geotagged += 1
                except (ValueError, TypeError):
                    pass

            # Also check coordinates property
            if lat is None and "coordinates" in page:
                coords = page["coordinates"]
                if coords:
                    lat = coords[0].get("lat")
                    lon = coords[0].get("lon")
                    if lat and lon:
                        already_geotagged += 1

            # Geocode from description/title if no GPS
            if lat is None:
                desc = ext.get("ImageDescription", {}).get("value", "")
                address = extract_address_from_description(desc, title)
                if address:
                    result = await geocode_address(session, address, geocode_semaphore)
                    if result:
                        lat, lon = result
                        geocoded += 1
                    else:
                        geocode_failed += 1
                else:
                    geocode_failed += 1

            if lat is None or lon is None:
                continue

            # Extract other fields
            desc_html = ext.get("ImageDescription", {}).get("value", "")
            description = re.sub(r"<[^>]+>", "", desc_html).strip()[:500]

            date_str = ext.get("DateTimeOriginal", {}).get("value", "")
            date_text = re.sub(r"<[^>]+>", "", date_str).strip()[:100]
            year_match = re.search(r"\b(1[0-9]{3})\b", date_text)
            date_year = int(year_match.group(1)) if year_match else None
            if date_year and not (MIN_YEAR <= date_year <= MAX_YEAR):
                date_year = None

            clean_title = title.removeprefix("File:").rsplit(".", 1)[0].replace("_", " ")[:300]
            rights_uri = ext.get("LicenseUrl", {}).get("value", "")
            thumbnail_url = info.get("thumburl", "")
            full_res_url = info.get("url", "")

            if not thumbnail_url:
                continue

            all_records.append({
                "id": f"wikimedia:{page.get('pageid', pid_str)}",
                "source": "wikimedia",
                "title": clean_title,
                "description": description,
                "date_text": date_text,
                "date_year": date_year if date_year else "",
                "lat": lat,
                "lon": lon,
                "city": "sf",
                "heading": "",
                "heading_confidence": "low",
                "thumbnail_url": thumbnail_url,
                "full_res_url": full_res_url,
                "attribution": WIKIMEDIA_ATTRIBUTION,
                "rights_uri": rights_uri,
            })

    log.info("Results: %d geolocated records", len(all_records))
    log.info("  Already geotagged: %d", already_geotagged)
    log.info("  Geocoded from address: %d", geocoded)
    log.info("  Failed to geocode: %d", geocode_failed)

    # Write CSV
    with open(output_path, "w", newline="", encoding="utf-8") as f:
        writer = csv.DictWriter(f, fieldnames=STAGING_COLUMNS)
        writer.writeheader()
        writer.writerows(all_records)

    log.info("Wrote %d rows → %s", len(all_records), output_path)
    return output_path


if __name__ == "__main__":
    output = asyncio.run(ingest())
    log.info("Done. Output: %s", output)
