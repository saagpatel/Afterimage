#!/usr/bin/env python3
"""Ingest OldNYC dataset: download nyc-records.json, extract geolocated historical photos."""

import csv
import json
import logging
import random
import re
import sys
from pathlib import Path

import requests

from config import (
    DIRECTION_MAP,
    MAX_YEAR,
    MIN_YEAR,
    OLDNYC_ATTRIBUTION,
    OLDNYC_FULLRES_TEMPLATE,
    OLDNYC_JSON_URL,
    OLDNYC_RIGHTS_URI,
    OLDNYC_THUMBNAIL_TEMPLATE,
    STAGING_COLUMNS,
    STAGING_DIR,
)

logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s")
log = logging.getLogger(__name__)

# Direction extraction patterns
DIRECTION_PATTERN = re.compile(
    r"""
    (?:^|[\s\-–])                          # start of string or separator
    (?:looking\s+|view\s+(?:to\s+(?:the\s+)?)?|facing\s+)?  # optional prefix
    (north(?:east|west|ward)?|
     south(?:east|west|ward)?|
     east(?:ward)?|
     west(?:ward)?|
     [ns][ew]?|                             # abbreviations: N, NE, etc.
     [ew])                                  # E, W
    (?:[\s.,;)\-–]|$)                       # end separator
    """,
    re.IGNORECASE | re.VERBOSE,
)


def parse_heading(title: str) -> tuple[float | None, str]:
    """Extract compass heading from title text.

    Returns (heading_degrees, confidence) where confidence is
    "medium" if a direction was found, "low" otherwise.
    """
    match = DIRECTION_PATTERN.search(title)
    if not match:
        return None, "low"

    direction = match.group(1).lower().strip(".")
    heading = DIRECTION_MAP.get(direction)
    if heading is not None:
        return float(heading), "medium"
    return None, "low"


def parse_year(record: dict) -> int | None:
    """Extract a valid year from the record's date fields."""
    # Prefer extracted.date_range (more reliable)
    extracted = record.get("extracted", {})
    date_range = extracted.get("date_range")
    if date_range and len(date_range) >= 1:
        try:
            year = int(date_range[0][:4])
            if MIN_YEAR <= year <= MAX_YEAR:
                return year
        except (ValueError, TypeError):
            pass

    # Fallback to record.date
    date_text = record.get("date", "")
    if date_text:
        # Try to extract a 4-digit year
        year_match = re.search(r"\b(1[89]\d{2})\b", date_text)
        if year_match:
            year = int(year_match.group(1))
            if MIN_YEAR <= year <= MAX_YEAR:
                return year

    return None


def download_records(cache_path: Path) -> list[dict]:
    """Download nyc-records.json, caching locally."""
    if cache_path.exists():
        log.info("Using cached %s (%d bytes)", cache_path, cache_path.stat().st_size)
    else:
        log.info("Downloading %s ...", OLDNYC_JSON_URL)
        resp = requests.get(OLDNYC_JSON_URL, timeout=120)
        resp.raise_for_status()
        cache_path.parent.mkdir(parents=True, exist_ok=True)
        cache_path.write_bytes(resp.content)
        log.info("Downloaded %d bytes → %s", len(resp.content), cache_path)

    with open(cache_path, encoding="utf-8") as f:
        data = json.load(f)

    if not isinstance(data, list):
        raise ValueError(f"Expected JSON array, got {type(data).__name__}")
    return data


def spot_check_urls(rows: list[dict], sample_size: int = 20) -> None:
    """Verify a random sample of thumbnail URLs return 200 + image/jpeg."""
    sample = random.sample(rows, min(sample_size, len(rows)))
    ok = 0
    for row in sample:
        url = row["thumbnail_url"]
        try:
            resp = requests.head(url, timeout=10, allow_redirects=True)
            content_type = resp.headers.get("Content-Type", "")
            if resp.status_code == 200 and "image" in content_type:
                ok += 1
            else:
                log.warning("URL check failed: %s → %d %s", url, resp.status_code, content_type)
        except requests.RequestException as exc:
            log.warning("URL check error: %s → %s", url, exc)

    log.info("Spot check: %d/%d thumbnail URLs returned 200 + image/*", ok, len(sample))
    if ok < len(sample) * 0.8:
        log.warning("More than 20%% of spot-checked URLs failed — image server may be unreliable")


def ingest() -> Path:
    """Run the OldNYC ingestion pipeline. Returns path to staging CSV."""
    STAGING_DIR.mkdir(parents=True, exist_ok=True)
    cache_path = STAGING_DIR / "nyc-records.json"
    output_path = STAGING_DIR / "staging_oldnyc.csv"

    records = download_records(cache_path)
    log.info("Loaded %d total records", len(records))

    rows: list[dict] = []
    skipped_no_latlon = 0
    skipped_bad_date = 0

    for record in records:
        extracted = record.get("extracted", {})
        latlon = extracted.get("latlon")
        if not latlon or not isinstance(latlon, list) or len(latlon) < 2:
            skipped_no_latlon += 1
            continue

        lat, lon = latlon[0], latlon[1]
        if not (-90 <= lat <= 90 and -180 <= lon <= 180):
            skipped_no_latlon += 1
            continue

        date_year = parse_year(record)
        heading, heading_confidence = parse_heading(record.get("title", ""))
        photo_id = record.get("id", "")

        rows.append({
            "id": f"oldnyc:{photo_id}",
            "source": "oldnyc",
            "title": record.get("title", "").strip(),
            "description": record.get("folder", "").strip(),
            "date_text": record.get("date", "").strip(),
            "date_year": date_year if date_year else "",
            "lat": lat,
            "lon": lon,
            "heading": heading if heading is not None else "",
            "heading_confidence": heading_confidence,
            "thumbnail_url": OLDNYC_THUMBNAIL_TEMPLATE.format(photo_id=photo_id),
            "full_res_url": OLDNYC_FULLRES_TEMPLATE.format(photo_id=photo_id),
            "attribution": OLDNYC_ATTRIBUTION,
            "rights_uri": OLDNYC_RIGHTS_URI,
        })

    log.info("Kept %d records with valid lat/lon", len(rows))
    log.info("Skipped %d records without lat/lon", skipped_no_latlon)

    # Count heading extractions
    with_heading = sum(1 for r in rows if r["heading"] != "")
    log.info("Extracted heading from %d records (%.1f%%)", with_heading, with_heading / len(rows) * 100)

    # Count valid years
    with_year = sum(1 for r in rows if r["date_year"] != "")
    log.info("Valid date_year for %d records (%.1f%%)", with_year, with_year / len(rows) * 100)

    # Spot-check thumbnail URLs
    spot_check_urls(rows)

    # Write CSV
    with open(output_path, "w", newline="", encoding="utf-8") as f:
        writer = csv.DictWriter(f, fieldnames=STAGING_COLUMNS)
        writer.writeheader()
        writer.writerows(rows)

    log.info("Wrote %d rows → %s", len(rows), output_path)
    return output_path


if __name__ == "__main__":
    output = ingest()
    log.info("Done. Output: %s", output)
