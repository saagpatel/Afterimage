"""Shared configuration for the Afterimage data pipeline."""

from pathlib import Path

# Directories
PIPELINE_DIR = Path(__file__).parent
STAGING_DIR = PIPELINE_DIR / "staging"
OUTPUT_DIR = PIPELINE_DIR / "output"

# City bounding boxes: (lat_min, lat_max, lon_min, lon_max)
CITIES = {
    "nyc": {
        "lat_range": (40.47, 40.92),
        "lon_range": (-74.26, -73.70),
    },
    "sf": {
        "lat_range": (37.70, 37.84),
        "lon_range": (-122.53, -122.35),
    },
}

# Manhattan urban core for grid coverage audit
MANHATTAN_GRID = {
    "lat_range": (40.70, 40.82),
    "lon_range": (-74.02, -73.93),
}

# Grid cell size in degrees (~100m at NYC latitude)
GRID_CELL_LAT = 0.0009   # ~100m north-south
GRID_CELL_LON = 0.0012   # ~100m east-west at 40.7°N

# Staging CSV columns
STAGING_COLUMNS = [
    "id", "source", "title", "description", "date_text", "date_year",
    "lat", "lon", "heading", "heading_confidence",
    "thumbnail_url", "full_res_url", "attribution", "rights_uri",
]

# Date validation range
MIN_YEAR = 1800
MAX_YEAR = 1980

# OldNYC source
OLDNYC_JSON_URL = (
    "https://raw.githubusercontent.com/nypl-spacetime/oldnyc/master/nyc-records.json"
)
OLDNYC_THUMBNAIL_TEMPLATE = "https://images.nypl.org/index.php?id={photo_id}&t=r"
OLDNYC_FULLRES_TEMPLATE = "https://images.nypl.org/index.php?id={photo_id}&t=w"
OLDNYC_ATTRIBUTION = "New York Public Library"
OLDNYC_RIGHTS_URI = (
    "https://www.nypl.org/help/about-nypl/legal-notices/website-terms-and-conditions"
)

# Wikimedia Commons
WIKIMEDIA_API_URL = "https://commons.wikimedia.org/w/api.php"
WIKIMEDIA_TILE_SPACING_M = 700  # meters between tile centers
WIKIMEDIA_SEARCH_RADIUS_M = 500
WIKIMEDIA_RESULTS_PER_TILE = 50
WIKIMEDIA_RATE_LIMIT_SEC = 1.0
WIKIMEDIA_MAX_RETRIES = 3
WIKIMEDIA_ATTRIBUTION = "Wikimedia Commons"
WIKIMEDIA_USER_AGENT = "AfterimageBot/0.1 (historical photo index builder)"

# Historical photo filtering
HISTORICAL_KEEP_CATEGORIES = [
    "historic american buildings survey",
    "habs",
    "haer",
    "historical photographs",
    "in the 1800s", "in the 1810s", "in the 1820s", "in the 1830s",
    "in the 1840s", "in the 1850s", "in the 1860s", "in the 1870s",
    "in the 1880s", "in the 1890s", "in the 1900s", "in the 1910s",
    "in the 1920s", "in the 1930s", "in the 1940s", "in the 1950s",
    "in the 1960s",
]
HISTORICAL_REJECT_CATEGORIES = [
    "self-published work",
    "uploaded with mobile",
    "panoramio",
    "taken with",
]

# Compass directions for heading extraction
DIRECTION_MAP = {
    "north": 0, "n": 0,
    "northeast": 45, "ne": 45,
    "east": 90, "e": 90,
    "southeast": 135, "se": 135,
    "south": 180, "s": 180,
    "southwest": 225, "sw": 225,
    "west": 270, "w": 270,
    "northwest": 315, "nw": 315,
    "northward": 0, "southward": 180,
    "eastward": 90, "westward": 270,
}
