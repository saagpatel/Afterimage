#!/usr/bin/env python3
"""Audit coverage density of photos.db for Phase 0 verification."""

import logging
import sqlite3
import sys
from pathlib import Path

from config import CITIES, GRID_CELL_LAT, GRID_CELL_LON, MANHATTAN_GRID, OUTPUT_DIR

logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s")
log = logging.getLogger(__name__)


def audit(db_path: Path) -> bool:
    """Run all coverage audits. Returns True if all gates pass."""
    if not db_path.exists():
        log.error("Database not found: %s", db_path)
        return False

    conn = sqlite3.connect(str(db_path))
    all_pass = True

    # --- Overall stats ---
    total = conn.execute("SELECT COUNT(*) FROM historical_photos").fetchone()[0]
    log.info("=== Overall Stats ===")
    log.info("Total records: %d", total)

    source_counts = conn.execute(
        "SELECT source, COUNT(*) FROM historical_photos GROUP BY source ORDER BY COUNT(*) DESC"
    ).fetchall()
    for source, count in source_counts:
        log.info("  %s: %d (%.1f%%)", source, count, count / total * 100)

    if total < 3000:
        log.error("FAIL: Total records %d < 3,000 minimum", total)
        all_pass = False
    else:
        log.info("PASS: Total records >= 3,000")

    if len(source_counts) < 2:
        log.error("FAIL: Only %d source(s) — need >= 2", len(source_counts))
        all_pass = False
    else:
        log.info("PASS: %d sources present", len(source_counts))

    # --- Manhattan grid coverage ---
    log.info("\n=== Manhattan Grid Coverage ===")
    lat_min, lat_max = MANHATTAN_GRID["lat_range"]
    lon_min, lon_max = MANHATTAN_GRID["lon_range"]

    rows = conn.execute(
        "SELECT lat, lon FROM historical_photos WHERE lat BETWEEN ? AND ? AND lon BETWEEN ? AND ?",
        (lat_min, lat_max, lon_min, lon_max),
    ).fetchall()

    grid_cells: set[tuple[int, int]] = set()
    for lat, lon in rows:
        cell_lat = int((lat - lat_min) / GRID_CELL_LAT)
        cell_lon = int((lon - lon_min) / GRID_CELL_LON)
        grid_cells.add((cell_lat, cell_lon))

    total_cells = int((lat_max - lat_min) / GRID_CELL_LAT) * int((lon_max - lon_min) / GRID_CELL_LON)
    coverage = len(grid_cells) / total_cells * 100 if total_cells > 0 else 0

    log.info("Manhattan photos: %d", len(rows))
    log.info("Unique 100m grid cells covered: %d / %d", len(grid_cells), total_cells)
    log.info("Coverage: %.1f%%", coverage)

    if coverage < 25:
        log.error("FAIL: Manhattan coverage %.1f%% < 25%%", coverage)
        all_pass = False
    else:
        log.info("PASS: Manhattan coverage >= 25%%")

    # --- Spot queries ---
    log.info("\n=== Spot Queries ===")

    spots = {
        "Times Square (NYC)": {
            "lat_range": (40.75, 40.76),
            "lon_range": (-73.99, -73.97),
            "min_count": 20,
        },
        "SF Mission/Castro": {
            "lat_range": (37.77, 37.80),
            "lon_range": (-122.42, -122.39),
            "min_count": 10,
        },
    }

    for name, params in spots.items():
        count = conn.execute(
            "SELECT COUNT(*) FROM historical_photos WHERE lat BETWEEN ? AND ? AND lon BETWEEN ? AND ?",
            (params["lat_range"][0], params["lat_range"][1], params["lon_range"][0], params["lon_range"][1]),
        ).fetchone()[0]

        if count < params["min_count"]:
            log.error("FAIL: %s has %d records (need >= %d)", name, count, params["min_count"])
            all_pass = False
        else:
            log.info("PASS: %s has %d records (>= %d)", name, count, params["min_count"])

    # --- Date validation ---
    log.info("\n=== Date Validation ===")
    bad_dates = conn.execute(
        "SELECT COUNT(*) FROM historical_photos WHERE date_year IS NOT NULL AND (date_year < 1800 OR date_year > 1980)"
    ).fetchone()[0]

    if bad_dates > 0:
        log.error("FAIL: %d records with date_year outside 1800-1980", bad_dates)
        all_pass = False
    else:
        log.info("PASS: All date_year values within 1800-1980 range")

    # --- Heading stats ---
    log.info("\n=== Heading Stats ===")
    with_heading = conn.execute(
        "SELECT COUNT(*) FROM historical_photos WHERE heading IS NOT NULL"
    ).fetchone()[0]
    medium_plus = conn.execute(
        "SELECT COUNT(*) FROM historical_photos WHERE heading_confidence IN ('medium', 'high')"
    ).fetchone()[0]
    log.info("Records with heading: %d (%.1f%%)", with_heading, with_heading / total * 100 if total else 0)
    log.info("Records with medium+ confidence: %d (%.1f%%)", medium_plus, medium_plus / total * 100 if total else 0)

    # --- Per-city breakdown ---
    log.info("\n=== Per-City Breakdown ===")
    for city_name, city_config in CITIES.items():
        lat_min, lat_max = city_config["lat_range"]
        lon_min, lon_max = city_config["lon_range"]
        count = conn.execute(
            "SELECT COUNT(*) FROM historical_photos WHERE lat BETWEEN ? AND ? AND lon BETWEEN ? AND ?",
            (lat_min, lat_max, lon_min, lon_max),
        ).fetchone()[0]
        log.info("%s: %d records", city_name.upper(), count)

    conn.close()

    # --- Final verdict ---
    log.info("\n=== VERDICT ===")
    if all_pass:
        log.info("ALL GATES PASSED — Phase 0 go/no-go: GO")
    else:
        log.error("SOME GATES FAILED — Phase 0 go/no-go: NO-GO (see failures above)")

    return all_pass


if __name__ == "__main__":
    db_path = OUTPUT_DIR / "photos.db"
    if len(sys.argv) > 1:
        db_path = Path(sys.argv[1])

    passed = audit(db_path)
    sys.exit(0 if passed else 1)
