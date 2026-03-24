#!/usr/bin/env python3
"""Merge staging CSVs, deduplicate, and build the photos.db SQLite index."""

import csv
import logging
import math
import sqlite3
import sys
from pathlib import Path

from config import MAX_YEAR, MIN_YEAR, OUTPUT_DIR, STAGING_COLUMNS, STAGING_DIR

logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s")
log = logging.getLogger(__name__)

SCHEMA = """
CREATE TABLE IF NOT EXISTS historical_photos (
    id                  TEXT PRIMARY KEY,
    source              TEXT NOT NULL,
    title               TEXT NOT NULL,
    description         TEXT,
    date_text           TEXT,
    date_year           INTEGER,
    lat                 REAL NOT NULL,
    lon                 REAL NOT NULL,
    heading             REAL,
    heading_confidence  TEXT NOT NULL DEFAULT 'low',
    thumbnail_url       TEXT NOT NULL,
    full_res_url        TEXT,
    attribution         TEXT NOT NULL,
    rights_uri          TEXT,
    created_at          DATETIME DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_lat ON historical_photos(lat);
CREATE INDEX IF NOT EXISTS idx_lon ON historical_photos(lon);
CREATE INDEX IF NOT EXISTS idx_latlon ON historical_photos(lat, lon);
CREATE INDEX IF NOT EXISTS idx_heading ON historical_photos(heading);
CREATE INDEX IF NOT EXISTS idx_source ON historical_photos(source);
"""


def haversine_m(lat1: float, lon1: float, lat2: float, lon2: float) -> float:
    """Haversine distance in meters between two GPS coordinates."""
    R = 6_371_000  # Earth radius in meters
    phi1, phi2 = math.radians(lat1), math.radians(lat2)
    dphi = math.radians(lat2 - lat1)
    dlam = math.radians(lon2 - lon1)
    a = math.sin(dphi / 2) ** 2 + math.cos(phi1) * math.cos(phi2) * math.sin(dlam / 2) ** 2
    return 2 * R * math.atan2(math.sqrt(a), math.sqrt(1 - a))


def load_staging_csv(path: Path) -> list[dict]:
    """Load a staging CSV, validating required fields."""
    rows = []
    with open(path, encoding="utf-8") as f:
        reader = csv.DictReader(f)
        for i, row in enumerate(reader):
            # Validate required fields
            if not row.get("id") or not row.get("lat") or not row.get("lon"):
                continue
            try:
                row["lat"] = float(row["lat"])
                row["lon"] = float(row["lon"])
            except (ValueError, TypeError):
                continue

            # Parse optional numeric fields
            if row.get("heading") and row["heading"] != "":
                try:
                    row["heading"] = float(row["heading"])
                except (ValueError, TypeError):
                    row["heading"] = None
            else:
                row["heading"] = None

            if row.get("date_year") and row["date_year"] != "":
                try:
                    row["date_year"] = int(row["date_year"])
                    if not (MIN_YEAR <= row["date_year"] <= MAX_YEAR):
                        row["date_year"] = None
                except (ValueError, TypeError):
                    row["date_year"] = None
            else:
                row["date_year"] = None

            rows.append(row)

    log.info("Loaded %d rows from %s", len(rows), path.name)
    return rows


def confidence_rank(confidence: str) -> int:
    """Rank heading confidence for dedup comparison. Higher = better."""
    return {"high": 3, "medium": 2, "low": 1}.get(confidence, 0)


def completeness_score(row: dict) -> int:
    """Count non-empty fields for dedup tiebreaking."""
    score = 0
    for key in ["title", "description", "date_text", "date_year", "heading", "full_res_url", "rights_uri"]:
        val = row.get(key)
        if val is not None and val != "":
            score += 1
    return score


def deduplicate_cross_source(rows: list[dict], distance_threshold_m: float = 10.0) -> list[dict]:
    """Remove cross-source duplicates within distance_threshold_m of each other in the same decade."""
    if len(rows) < 2:
        return rows

    # Sort by lat for spatial proximity scanning
    rows.sort(key=lambda r: r["lat"])

    removed_ids: set[str] = set()

    for i in range(len(rows)):
        if rows[i]["id"] in removed_ids:
            continue
        for j in range(i + 1, len(rows)):
            if rows[j]["id"] in removed_ids:
                continue
            # Quick lat check — if lat difference > ~0.0002 (~22m), skip
            if abs(rows[j]["lat"] - rows[i]["lat"]) > 0.0002:
                break

            # Same source = not a cross-source duplicate
            if rows[i]["source"] == rows[j]["source"]:
                continue

            # Check same decade
            year_i = rows[i].get("date_year")
            year_j = rows[j].get("date_year")
            if year_i and year_j:
                if abs(year_i - year_j) > 10:
                    continue

            dist = haversine_m(rows[i]["lat"], rows[i]["lon"], rows[j]["lat"], rows[j]["lon"])
            if dist <= distance_threshold_m:
                # Keep the one with higher heading confidence, then more complete metadata
                conf_i = confidence_rank(rows[i].get("heading_confidence", "low"))
                conf_j = confidence_rank(rows[j].get("heading_confidence", "low"))
                if conf_j > conf_i:
                    removed_ids.add(rows[i]["id"])
                elif conf_i > conf_j:
                    removed_ids.add(rows[j]["id"])
                elif completeness_score(rows[j]) > completeness_score(rows[i]):
                    removed_ids.add(rows[i]["id"])
                else:
                    removed_ids.add(rows[j]["id"])

    result = [r for r in rows if r["id"] not in removed_ids]
    log.info("Deduplication: %d → %d records (%d removed)", len(rows), len(result), len(removed_ids))
    return result


def build_db(rows: list[dict], db_path: Path) -> None:
    """Create photos.db from merged rows."""
    db_path.parent.mkdir(parents=True, exist_ok=True)
    if db_path.exists():
        db_path.unlink()

    conn = sqlite3.connect(str(db_path))
    conn.executescript(SCHEMA)

    insert_sql = """
    INSERT OR IGNORE INTO historical_photos
        (id, source, title, description, date_text, date_year,
         lat, lon, heading, heading_confidence,
         thumbnail_url, full_res_url, attribution, rights_uri)
    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    """

    batch = []
    for row in rows:
        batch.append((
            row["id"],
            row["source"],
            row.get("title", ""),
            row.get("description"),
            row.get("date_text"),
            row.get("date_year"),
            row["lat"],
            row["lon"],
            row.get("heading"),
            row.get("heading_confidence", "low"),
            row["thumbnail_url"],
            row.get("full_res_url"),
            row.get("attribution", ""),
            row.get("rights_uri"),
        ))

    conn.executemany(insert_sql, batch)
    conn.commit()

    # Verify
    cursor = conn.execute("PRAGMA integrity_check")
    integrity = cursor.fetchone()[0]
    if integrity != "ok":
        raise RuntimeError(f"SQLite integrity check failed: {integrity}")

    cursor = conn.execute("SELECT COUNT(*) FROM historical_photos")
    total = cursor.fetchone()[0]

    cursor = conn.execute("SELECT source, COUNT(*) FROM historical_photos GROUP BY source")
    source_counts = cursor.fetchall()

    conn.close()

    log.info("Database built: %s", db_path)
    log.info("Total records: %d", total)
    for source, count in source_counts:
        log.info("  %s: %d", source, count)
    log.info("Integrity check: %s", integrity)


def build() -> Path:
    """Run the build pipeline. Returns path to photos.db."""
    # Find all staging CSVs
    staging_files = sorted(STAGING_DIR.glob("staging_*.csv"))
    if not staging_files:
        log.error("No staging CSVs found in %s", STAGING_DIR)
        sys.exit(1)

    log.info("Found %d staging files: %s", len(staging_files), [f.name for f in staging_files])

    # Load all
    all_rows: list[dict] = []
    for path in staging_files:
        rows = load_staging_csv(path)
        all_rows.extend(rows)

    log.info("Total rows before dedup: %d", len(all_rows))

    # Deduplicate
    all_rows = deduplicate_cross_source(all_rows)

    # Build SQLite
    db_path = OUTPUT_DIR / "photos.db"
    build_db(all_rows, db_path)

    return db_path


if __name__ == "__main__":
    output = build()
    log.info("Done. Output: %s", output)
