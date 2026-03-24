# Afterimage — Implementation Roadmap

## Architecture

### System Overview

```
[Dev-Time Data Pipeline — Python, NOT shipped in app]
LoC PPOC API ──────────────────────────────────────┐
Wikimedia Commons Geosearch API (namespace=6) ──────┤──► ingest_*.py scripts
NYPL Space/Time GeoJSON (static download) ──────────┘         │
                                                               ▼
                                                       build_index.py
                                                               │
                                                        photos.db (~80–200MB SQLite)
                                                               │
                                                    [Bundled in Xcode app bundle]

[On-Device Runtime]
CoreLocation ──► CLLocation (lat/lon, accuracy)
CoreMotion  ──► CLHeading (degrees, headingAccuracy)
                              │
                              ▼
                      MatchingService
                      ┌─────────────────────────────────────────┐
                      │ Stage 1: SpatialQuery                   │
                      │   GRDB bounding-box SELECT on photos.db │
                      │   Haversine exact filter ≤100m          │
                      │   → up to 20 candidates                 │
                      │                                         │
                      │ Stage 2: HeadingFilter                  │
                      │   Drop candidates where                 │
                      │   |heading - userHeading| > 45°         │
                      │   (skipped if headingAccuracy > 45°)    │
                      │                                         │
                      │ Stage 3: ThumbnailFetcher               │
                      │   URLSession async fetch (concurrent)   │
                      │   Kingfisher disk cache                 │
                      │                                         │
                      │ Stage 4: VisionRanker                   │
                      │   Grayscale preprocess both images      │
                      │   VNGenerateImageFeaturePrintRequest    │
                      │   computeDistance() → sort ascending    │
                      │   Composite score: 70% geo + 30% vision │
                      └─────────────────────────────────────────┘
                              │
                              ▼
                      [MatchCandidate array, sorted by compositeScore]
                              │
                              ▼
                      ComparisonView
                      ├── SliderOverlayView (hero — draggable reveal)
                      ├── SideBySideView
                      └── FadeView
                              │
                              ▼
                      ShareCompositor → UIActivityViewController
```

### File Structure

```
afterimage/
├── afterimage.xcodeproj
├── CLAUDE.md
├── IMPLEMENTATION-ROADMAP.md
├── afterimage/
│   ├── App/
│   │   ├── AfterimageApp.swift          # @main entry, WindowGroup setup
│   │   └── AppState.swift               # @StateObject: permission states, active match
│   ├── Features/
│   │   ├── Camera/
│   │   │   ├── CameraView.swift         # SwiftUI AVFoundation preview wrapper
│   │   │   ├── CameraViewModel.swift    # Photo capture, permission request logic
│   │   │   └── CameraCoordinator.swift  # AVCapturePhotoCaptureDelegate
│   │   ├── Matching/
│   │   │   ├── MatchingService.swift    # Orchestrates all 4 pipeline stages
│   │   │   ├── SpatialQuery.swift       # GRDB bounding-box + Haversine filter
│   │   │   ├── HeadingFilter.swift      # ±45° filter with accuracy fallback
│   │   │   └── VisionRanker.swift       # Grayscale preprocess + feature print + sort
│   │   ├── Comparison/
│   │   │   ├── ComparisonView.swift     # Mode switcher container
│   │   │   ├── SliderOverlayView.swift  # Hero: two image layers + draggable divider
│   │   │   ├── SideBySideView.swift     # Equal-width split
│   │   │   └── FadeView.swift           # Animated crossfade
│   │   ├── Gallery/
│   │   │   ├── GalleryPickerView.swift         # PHPickerViewController wrapper
│   │   │   └── GalleryMatchViewModel.swift      # EXIF GPS extraction + map fallback
│   │   └── Share/
│   │       ├── ShareCompositor.swift    # Renders 1200×800 composite JPEG
│   │       └── ShareSheetView.swift     # UIActivityViewController wrapper
│   ├── Data/
│   │   ├── Models/
│   │   │   └── HistoricalPhoto.swift    # GRDB Record + MatchCandidate types
│   │   ├── Database/
│   │   │   └── DatabaseManager.swift    # GRDB DatabasePool (read-only), bundled DB path
│   │   └── Cache/
│   │       └── ThumbnailCache.swift     # Kingfisher disk cache config
│   ├── Services/
│   │   ├── LocationService.swift        # CLLocationManager async wrapper
│   │   └── ThumbnailFetcher.swift       # URLSession concurrent fetch, cache check
│   └── Resources/
│       ├── photos.db                    # Bundled SQLite index (do not compress in Build Settings)
│       └── Assets.xcassets
├── DataPipeline/                        # NOT in app target — dev machine only
│   ├── ingest_loc.py                    # LoC PPOC API ingestion
│   ├── ingest_wikimedia.py              # Wikimedia Commons geosearch ingestion
│   ├── ingest_nypl.py                   # NYPL Space/Time GeoJSON ingestion
│   ├── build_index.py                   # Merge, deduplicate, output photos.db
│   └── requirements.txt                 # aiohttp, requests, Pillow, tqdm, geojson
└── AfterimageTests/
    ├── SpatialQueryTests.swift
    ├── HeadingFilterTests.swift
    └── VisionRankerTests.swift
```

### Data Model

```sql
-- Primary historical photo index table
CREATE TABLE historical_photos (
    id                  TEXT PRIMARY KEY,     -- "{source}:{source_id}" e.g. "oldnyc:730340f"
    source              TEXT NOT NULL,        -- "oldnyc" | "wikimedia" | "flickr_commons"
    title               TEXT NOT NULL,
    description         TEXT,
    date_text           TEXT,                 -- Human-readable: "circa 1920", "1887"
    date_year           INTEGER,              -- Parsed integer year for sorting; nullable
    lat                 REAL NOT NULL,
    lon                 REAL NOT NULL,
    heading             REAL,                 -- Camera heading in degrees [0–360]; nullable
    heading_confidence  TEXT NOT NULL DEFAULT 'low',  -- "high" | "medium" | "low"
    thumbnail_url       TEXT NOT NULL,        -- Direct URL to ~300px wide thumbnail
    full_res_url        TEXT,                 -- Full resolution URL; nullable
    attribution         TEXT NOT NULL,        -- "Library of Congress" / "Wikimedia Commons" / "NYPL"
    rights_uri          TEXT,                 -- Link to rights/license statement
    created_at          DATETIME DEFAULT CURRENT_TIMESTAMP
);

-- Spatial lookup — primary query path (bounding box)
CREATE INDEX idx_lat ON historical_photos(lat);
CREATE INDEX idx_lon ON historical_photos(lon);
CREATE INDEX idx_latlon ON historical_photos(lat, lon);

-- Heading filter (applied after spatial)
CREATE INDEX idx_heading ON historical_photos(heading);

-- Source breakdown (for debugging/stats)
CREATE INDEX idx_source ON historical_photos(source);
```

### Swift Type Definitions

```swift
// Data/Models/HistoricalPhoto.swift
import GRDB
import CoreLocation

enum PhotoSource: String, Codable, DatabaseValueConvertible {
    case oldnyc, wikimedia, flickrCommons
}

enum HeadingConfidence: String, Codable, DatabaseValueConvertible {
    case high, medium, low
}

struct HistoricalPhoto: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "historical_photos"

    let id: String
    let source: PhotoSource
    let title: String
    let description: String?
    let dateText: String?
    let dateYear: Int?
    let lat: Double
    let lon: Double
    let heading: Double?
    let headingConfidence: HeadingConfidence
    let thumbnailURL: URL
    let fullResURL: URL?
    let attribution: String
    let rightsURI: URL?

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: lat, longitude: lon)
    }
}

enum ConfidenceLabel: String {
    case strongMatch = "Strong Match"   // compositeScore < 0.25
    case goodMatch   = "Good Match"     // compositeScore 0.25–0.50
    case nearby      = "Nearby"         // compositeScore > 0.50
}

struct MatchCandidate: Identifiable {
    let id = UUID()
    let photo: HistoricalPhoto
    let distanceMeters: Double        // Raw Haversine result
    let headingDelta: Double?         // nil if photo.heading is nil or heading skipped
    var visionDistance: Float?        // nil until Vision pass completes; lower = more similar
    var compositeScore: Double        // 0.0 (perfect) to 1.0 (worst); 70% geo + 30% vision
    var confidenceLabel: ConfidenceLabel

    // Confidence thresholds
    static let strongThreshold: Double = 0.25
    static let goodThreshold: Double   = 0.50
}
```

### API Contracts

**External data sources (used at build time by Python pipeline — NOT called from the app at runtime):**

| Source | Endpoint | Method | Auth | Rate Limit | Notes |
|--------|----------|--------|------|------------|-------|
| OldNYC (NYPL) | `https://raw.githubusercontent.com/nypl-spacetime/oldnyc/master/nyc-records.json` | GET | None | N/A — one-time 20MB download | ~43K records, ~25K with GPS. Fields: `extracted.latlon`, `title`, `date`, `folder`, `id` |
| Wikimedia Commons | Combined geosearch+imageinfo query to `https://commons.wikimedia.org/w/api.php` | GET | None | Polite: 1 req/sec | `generator=geosearch` + `prop=imageinfo`. Filter by DateTimeOriginal < 1970 + historical category keywords. Tile bounding boxes at 700m spacing. |

**Dropped sources (validated as non-viable March 2026):**
- ~~LoC PPOC API~~ — GPS coordinates are always empty strings in API results
- ~~NYPL Space/Time Directory~~ — archived October 2024, no downloadable GeoJSON

**Runtime thumbnail fetch (called from app):**

| Source | URL Pattern | Max Size |
|--------|-------------|----------|
| OldNYC (NYPL) | `https://images.nypl.org/index.php?id={photo_id}&t=r` | ~300px wide |
| Wikimedia | `thumburl` from imageinfo API (CDN-backed) | 300px wide |

### Dependencies

```bash
# Swift Package Manager — add via Xcode → File → Add Package Dependencies
# GRDB.swift (SQLite wrapper)
https://github.com/groue/GRDB.swift  →  from: "6.0.0"

# Kingfisher (async image loading + disk cache)
https://github.com/onevcat/Kingfisher  →  from: "7.0.0"

# Python data pipeline (run on dev machine — not in app target)
cd DataPipeline
pip install aiohttp requests Pillow tqdm geojson
```

**Xcode Build Settings (required):**
- `photos.db` target membership: app target only
- `photos.db` "Compress PNG Files": **No** (SQLite must not be compressed)
- Minimum Deployments: **iOS 17.0**
- Supported Destinations: **iPhone** only (remove iPad)
- Info.plist keys required:
  - `NSCameraUsageDescription`: "Afterimage uses your camera to take a photo and find a historical match for the same location."
  - `NSPhotoLibraryUsageDescription`: "Afterimage reads GPS data from your photos to find historical matches for where they were taken."
  - `NSLocationWhenInUseUsageDescription`: "Afterimage uses your location to search nearby historical photos."

---

## Scope Boundaries

**In scope (v1):**
- Live camera → match → slider flow
- Camera roll matching (photos with GPS EXIF, or user-pinned location fallback)
- 6 US cities in bundled index: NYC, SF, Chicago, DC, New Orleans, Boston
- 3 comparison modes: slider overlay (hero), side-by-side, fade
- Multi-match browsing (up to 5 results, horizontal scroll picker)
- Share sheet exporting 1200×800 composite image
- Confidence badge (Strong Match / Good Match / Nearby)
- No-match state with 500m fallback radius
- City coverage onboarding modal (first launch only)

**Out of scope (v1):**
- User accounts or sign-in
- User-submitted historical photos
- AR viewfinder overlay
- Timeline scrubbing (multiple decades at same location)
- International cities
- Backend or cloud sync
- Any analytics, tracking, or crash reporting SDKs

**Deferred to v2:**
- Visual alignment / homography transform for perspective-mismatched pairs
- Walking tour mode (curated location routes)
- AR real-time overlay mode
- International archive partnerships (Imperial War Museum UK, BnF France)
- User photo contributions with moderation

---

## Security & Credentials

- **No credentials in the app.** All data sources are public, unauthenticated APIs used at pipeline build time only.
- **`photos.db` is read-only.** Open via `DatabasePool` with `configuration.readonly = true`. Never write to it.
- **No user data leaves the device.** Photos, GPS coordinates, and camera heading are used only to query the local SQLite DB — never transmitted.
- **PHPickerViewController** (not `PHPhotoLibrary`): no full library permission required in iOS 14+. Scoped access only.
- **No keychain usage needed.** No secrets, tokens, or credentials at runtime.

---

## Phase 0: Data Pipeline + Index (Week 1)

**Objective:** Build and validate the bundled SQLite index for NYC and SF before writing any app code. This phase is a go/no-go gate — if coverage density is unacceptably low, pivot strategy here, not after 3 weeks of app development.

**Tasks:**

1. Create `DataPipeline/` directory structure and `requirements.txt`. Install deps.
   - **Acceptance:** `pip install -r requirements.txt` completes without errors.

2. Write `ingest_oldnyc.py` — download `nyc-records.json` (20MB, ~43K records) from OldNYC GitHub repo. Filter records with `extracted.latlon` present. Parse heading from direction words in titles (e.g., "- Northeast.", "looking west"). Validate date_year in 1800–1980 range (496 records have garbage 5-digit dates). Build thumbnail URLs via `images.nypl.org`. Write to `staging_oldnyc.csv`.
   - **Acceptance:** `staging_oldnyc.csv` contains ≥25,000 rows with non-null lat/lon. 20 random thumbnail URLs spot-checked return 200 + image/jpeg. ≥25% of records have extracted heading.

3. Write `ingest_wikimedia.py` — tile NYC and SF bounding boxes at 700m spacing. For each tile, call combined geosearch+imageinfo API query (one request per tile). Filter for historical content: DateTimeOriginal year < 1970, or HABS/HAER/historical category keywords. Reject modern indicators (Self-published, Panoramio, Uploaded with Mobile). Deduplicate by `pageid` across overlapping tiles. Rate limit: 1 req/sec. Run SF first for early density read.
   - **Acceptance:** `staging_wikimedia.csv` contains records for both NYC and SF. SF records ≥10 (if <200, log warning to trigger Flickr Commons contingency).

4. Write `build_index.py` — load all staging CSVs. Cross-source deduplication: for records within 10m (Haversine) AND same decade, keep the one with higher heading_confidence, then more complete metadata. Build `photos.db` with schema and indexes.
   - **Acceptance:** `python build_index.py` exits 0. `PRAGMA integrity_check` → `ok`. `SELECT source, COUNT(*) FROM historical_photos GROUP BY source` → ≥2 sources. Total records ≥3,000.

5. Write `audit_coverage.py` — compute Manhattan 100m grid cell coverage, run spot queries, validate date ranges, report per-city and per-source breakdowns.
   - **Acceptance:** Manhattan grid coverage ≥25%. Times Square spot query ≥20. SF Mission spot query ≥10.

6. (Contingency) Write `ingest_flickr.py` — only if Wikimedia SF yield <200. Use `flickr.photos.search` with `is_commons=1`, geo params, date filtering. Requires free API key.

**Verification checklist:**
- [ ] `python build_index.py` → exits 0, no unhandled exceptions
- [ ] `sqlite3 photos.db "PRAGMA integrity_check"` → `ok`
- [ ] `sqlite3 photos.db "SELECT COUNT(*) FROM historical_photos"` → ≥3,000
- [ ] `sqlite3 photos.db "SELECT source, COUNT(*) FROM historical_photos GROUP BY source"` → ≥2 sources
- [ ] 20 random thumbnail URLs manually verified: load + are visually historical
- [ ] NYC Times Square spot query → ≥20 results
- [ ] SF Mission spot query → ≥10 results
- [ ] Manhattan grid coverage ≥25%
- [ ] No records with date_year outside 1800–1980

**Risks:**
- SF coverage may be sparse (Wikimedia only source for SF). If <200 photos, trigger Flickr Commons contingency or drop SF from Phase 0 cities.
  - **Mitigation:** Run SF tiles first for early read. Implement `ingest_flickr.py` as backup.
  - **Fallback:** Ship NYC-only for Phase 0 validation; add SF in Phase 2 with expanded sources.

---

## Phase 1: Core App — Camera → Match → Slider (Weeks 2–4)

**Objective:** Full end-to-end working flow on a physical device. Take photo → run matching pipeline → see slider. No gallery, no share, no polish.

**Tasks:**

1. Scaffold Xcode project — SwiftUI App template, iOS 17 minimum, iPhone only. Add GRDB.swift and Kingfisher via SPM. Add `photos.db` to app bundle (mark "Compress PNG Files" = No in Build Settings). Add required Info.plist permission strings.
   - **Acceptance:** App builds and runs on a physical iPhone 14+. In `DatabaseManager.swift`, `DatabasePool` opens `photos.db` from bundle. Console log confirms: `"DB opened: {N} historical photos loaded"`.

2. `LocationService.swift` — `@MainActor` class wrapping `CLLocationManager`. Expose `currentLocation: CLLocation` and `currentHeading: CLHeading` as `async` properties using `AsyncStream`. Handle `.notDetermined`, `.denied`, `.restricted` states.
   - **Acceptance:** Running on physical device outdoors, `locationService.currentLocation` returns a `CLLocation` with `horizontalAccuracy < 15`. `locationService.currentHeading` returns `CLHeading` with `headingAccuracy < 45°`. Both tested in live app (not simulator).

3. `CameraView.swift` + `CameraViewModel.swift` + `CameraCoordinator.swift` — full-screen `AVCaptureSession` preview in SwiftUI, capture button centered at bottom, returns `UIImage` on capture. Handle `.notDetermined`/`.denied` camera permission states with a "Grant Camera Access" fallback view.
   - **Acceptance:** App shows live camera preview. Tap capture button → `UIImage` returned to `CameraViewModel.capturedPhoto`. Preview thumbnail of captured image shown in top-right corner at 80×80pt.

4. `SpatialQuery.swift` — Haversine distance function in pure Swift. GRDB bounding box query: `SELECT * FROM historical_photos WHERE lat BETWEEN {minLat} AND {maxLat} AND lon BETWEEN {minLon} AND {maxLon}`. Apply exact Haversine filter (≤100m) to bounding-box results. Return up to 20 nearest candidates.
   - **Acceptance:** Unit test with seeded in-memory GRDB DB: 10 inserted rows at known distances. `SpatialQuery.candidates(near:radius:)` returns exactly the rows within 100m, sorted by distance ascending. Validate Haversine: Times Square (40.7580, -73.9855) to Empire State Building (40.7484, -73.9967) = 1,256m ± 5m.

5. `HeadingFilter.swift` — filter `[MatchCandidate]` by `|photo.heading - userHeading| ≤ 45°`. Handle 360°/0° wraparound. If `photo.heading == nil` OR `userHeading.headingAccuracy > 45°`: skip filter, pass all candidates through.
   - **Acceptance:** Unit tests: (a) photo heading 350°, user heading 10° → delta = 20° → PASS. (b) photo heading 180°, user heading 10° → delta = 170° → FAIL. (c) `headingAccuracy = 90°` → filter skipped, all candidates pass. 8 test cases total.

6. `ThumbnailFetcher.swift` — `async` function fetching all candidate thumbnails concurrently using `withThrowingTaskGroup`. Check Kingfisher cache first (`ImageCache.default`). On miss, fetch via `URLSession.shared.data(from:)`. Store in Kingfisher cache. Return `[String: UIImage]` keyed by `photo.id`.
   - **Acceptance:** Fetch 5 thumbnails concurrently on Wi-Fi → all 5 returned in <3 seconds. Fetch same 5 again → returns from cache in <100ms total (Kingfisher disk cache hit).

7. `VisionRanker.swift` — grayscale preprocess: apply `CIFilter(name: "CIColorControls")` with `inputSaturation = 0`. Run `VNGenerateImageFeaturePrintRequest` via `VNImageRequestHandler`. Call `computeDistance(_:to:)` for each candidate vs. user photo. Compute composite score: `0.7 * normalizedGeoScore + 0.3 * normalizedVisionScore` where each is normalized 0–1 within the candidate set. Sort ascending.
   - **Acceptance:** Benchmark on iPhone 14+: processing 20 candidates with 300px thumbnails completes in <2 seconds. Manual test: given a photo of a building and 5 candidates (2 same building type, 3 unrelated), the 2 matching candidates rank in positions 1 and 2 in ≥7 out of 10 test pairs.

8. `MatchingService.swift` — orchestrates Stages 1–4. `func findMatches(for photo: UIImage, at location: CLLocation, heading: CLHeading?) async throws -> [MatchCandidate]`. On 0 results from 100m spatial query, automatically retry with 500m radius and set `confidenceLabel = .nearby` for all results.
   - **Acceptance:** End-to-end on physical device at a covered location (NYC or SF): result returned in <5 seconds. Console logs timing for each stage.

9. `SliderOverlayView.swift` — two `Image` layers in a `ZStack`. Bottom layer: historical photo (full frame). Top layer: user photo, clipped by `Rectangle().frame(width: dividerX)`. Draggable vertical divider bar (4pt wide, white, with left/right chevron at center). Divider initialized at 50% of frame width.
   - **Acceptance:** Drag gesture updates divider at 60fps — verify with Instruments → Core Animation, 0 dropped frames during sustained drag on iPhone 14. Works correctly at both extremes (0% and 100%). Both images letterboxed to 4:3 aspect ratio.

10. `ComparisonView.swift` — hosts `SliderOverlayView` as hero. Attribution string (`photo.attribution`) and `photo.dateText` displayed below image. "Back" button (top-left) returns to camera. `MatchingService` called when user photo is set; show `ProgressView` during matching.
    - **Acceptance:** Full flow on device: capture → 3–5s matching → slider appears with attribution text. "Back" returns to live camera.

**Verification checklist:**
- [ ] App builds with 0 warnings (treat warnings as errors in Build Settings for `afterimage` target)
- [ ] Full camera→match→slider flow runs on physical iPhone
- [ ] Slider drag: 0 dropped frames in Instruments Core Animation on iPhone 14
- [ ] Attribution text visible for every match result
- [ ] Matching completes in <5s on iPhone 12 (tested in Airplane Mode, thumbnails from Kingfisher cache)
- [ ] Camera permission requested only on first camera tap, not on launch
- [ ] Location permission requested only on first match attempt, not on launch
- [ ] All unit tests pass: `cmd+U` → 0 failures

**Risks:**
- Vision distances uniformly high for historical photos (all look dissimilar to modern photos regardless of content).
  - **Mitigation:** Run the Vision benchmark task from the plan before implementing full compositeScore — load 10 LoC thumbnails in a scratch playground, compute distances from a modern equivalent photo, check if any score < 0.5. If all > 0.7, change composite weighting to 90% geo / 10% vision.
  - **Fallback:** Remove Vision stage entirely for v1; return candidates sorted by GPS distance + heading delta only.

---

## Phase 2: Gallery Matching + Expanded Cities (Weeks 5–6)

**Objective:** Camera roll photos matchable. Index expanded to all 6 target cities.

**Tasks:**

1. `GalleryPickerView.swift` — `PHPickerViewController` wrapped in `UIViewControllerRepresentable`. On selection, extract `UIImage` + GPS coordinates from `PHAsset` via `PHAsset.location`. If `PHAsset.location` is nil, flag as `needsManualLocation = true`.
   - **Acceptance:** Select a photo taken with location services enabled → GPS coordinates extracted. Select a screenshot (no location) → `needsManualLocation = true` flag set. No `PHPhotoLibrary` full-access permission requested.

2. `GalleryMatchViewModel.swift` — handles `needsManualLocation` case by presenting a `MapKit` annotation picker (tap on map → sets coordinates; heading filter skipped for gallery photos with no EXIF orientation). Passes coordinates + image to `MatchingService`.
   - **Acceptance:** Gallery photo without GPS → `Map` view shown → tap a location pin → matching runs. `HeadingFilter` is skipped (`headingAccuracy = 999`). Result displayed in `ComparisonView`.

3. Run data pipeline for 4 additional cities: Chicago (41.78–42.02°N, 87.94–87.52°W), DC (38.79–38.99°N, 77.12–76.91°W), New Orleans (29.90–30.07°N, 90.16–89.99°W), Boston (42.30–42.40°N, 71.19–71.00°W). Regenerate `photos.db`. Replace bundled DB in Xcode project. Rebuild and push to TestFlight.
   - **Acceptance:** `photos.db` size ≤200MB. Each new city has ≥300 records. Coverage density spot-check: `SELECT COUNT(*) WHERE lat BETWEEN {city_bounds}` returns ≥300 for each city. TestFlight build installs and launches without crash.

4. No-match state — when 500m fallback also returns 0 results, show a dedicated "No historical photos found here" view. Display the nearest covered city name and distance from user's location (compute from city center coordinates hardcoded for 6 cities).
   - **Acceptance:** Simulated with mocked coords (e.g., rural Montana: 46.87°N, 113.99°W) → no-match state shown within 5s. Displays nearest city name. No blank screen. "Try a different location" button returns to camera.

**Verification checklist:**
- [ ] Gallery photo with GPS → match returned, no map picker shown
- [ ] Gallery photo without GPS → map picker shown → match returned after location pinned
- [ ] No-match state shown for rural coordinates (unit test: inject mocked location that returns 0 DB results)
- [ ] All 6 cities have ≥300 records in updated `photos.db`
- [ ] TestFlight build installs on iPhone, no crash on launch

---

## Phase 3: Confidence UI + Polish (Week 7)

**Objective:** Confidence badges, multi-match browsing, onboarding modal, haptics.

**Tasks:**

1. Confidence badge — overlay on `SliderOverlayView` (top-left corner). "Strong Match" = green badge, "Good Match" = amber badge, "Nearby" = gray badge. Text: SF Pro Rounded 12pt semibold.
   - **Acceptance:** All 3 badge states render. Text and background pass WCAG AA contrast (4.5:1) on both light and dark backgrounds. Verified with Accessibility Inspector in Xcode.

2. Multi-match browsing — when `MatchingService` returns ≥2 candidates, show a horizontal scroll picker below the slider (thumbnail strip, max 5 results). Selecting a thumbnail switches the historical image in the slider.
   - **Acceptance:** 3+ results available → thumbnail strip visible. Tap thumbnail → historical image updates in <300ms (Kingfisher cache hit). Active thumbnail has 2pt white border.

3. First-launch onboarding modal — appears once on first app launch (gated by `UserDefaults.standard.bool(forKey: "hasSeenOnboarding")`). Full-screen sheet with: title "Best in US Cities", 6 city labels positioned on a simple US outline map (`Image("us_outline")`), "Start Exploring" dismiss button.
   - **Acceptance:** Modal appears on first launch only. After dismiss, `UserDefaults` key set to `true`. Second launch → modal does not appear. Modal tested in Simulator (reset via Settings → General → Transfer or Reset iPhone → Reset → Reset Location & Privacy).

4. Haptic feedback — `UIImpactFeedbackGenerator(style: .light).impactOccurred()` on photo capture. `UIImpactFeedbackGenerator(style: .medium).impactOccurred()` when first match result appears.
   - **Acceptance:** Both haptics felt on physical device (not testable in Simulator). Verified manually.

**Verification checklist:**
- [ ] All 3 confidence badge colors visible and contrast-passing
- [ ] Multi-match thumbnail strip appears for results with ≥2 candidates
- [ ] Onboarding modal appears on first launch, not on second launch
- [ ] Haptics fire at capture and at first match result (physical device test)

---

## Phase 4: Share Sheet + App Store Submission (Week 8)

**Objective:** Shareable composite image. App Store ready.

**Tasks:**

1. `ShareCompositor.swift` — renders `UIImage` at 1200×800px using `UIGraphicsImageRenderer`. Layout: top half (600×800px) = user photo (aspect-fill cropped), white label overlay "2026" (SF Pro Display 28pt bold, bottom-right of top half). Bottom half (600×800px) = historical photo (aspect-fill cropped), white label overlay of `photo.dateText` (same style). Afterimage wordmark bottom-right of composite: "Afterimage" in SF Pro Display 14pt, white, 30% opacity. Attribution in 10pt below historical photo.
   - **Acceptance:** `ShareCompositor.render(userPhoto:historicalPhoto:candidate:)` returns valid `UIImage` in <1 second on iPhone 12. Output is 1200×800px confirmed via `image.size`. Save to Photos to verify layout visually.

2. `ShareSheetView.swift` — `UIActivityViewController` wrapper. Present with: `[UIImage (composite), String]` where string = `"Then and now: \(photo.title) (\(photo.attribution)) — found with Afterimage"`. Share button added to `ComparisonView` toolbar (top-right).
   - **Acceptance:** Share sheet opens from `ComparisonView`. Composite image pre-populated. Text string pre-filled. Sharing to Photos, Messages, and Instagram verified manually.

3. App Store metadata and screenshots — generate 6 screenshots per device size (6.7" iPhone 15 Pro Max and 6.1" iPhone 15): camera view, mid-slide reveal at 50%, full historical reveal, confidence badge visible, multi-match strip visible, share composite. Use a high-contrast NYC or SF location.
   - **Acceptance:** 12 screenshots generated (6 per device size). All pass App Store Connect dimension requirements (1290×2796 for 6.7", 1179×2556 for 6.1"). Upload to App Store Connect without rejection.

4. App Store submission prep — Privacy Nutrition Label in App Store Connect: Data Not Collected. Age Rating: 4+. Categories: Travel (primary), Photo & Video (secondary). Review notes for App Store reviewer: "The app requires a physical device for camera and GPS. The historical photo database is bundled — no network required after install for matching. Test location: Times Square, NYC (40.7580°N, 73.9855°W), heading south."
   - **Acceptance:** App submitted to App Store Review. No binary rejection from automated checks.

**Verification checklist:**
- [ ] Composite renders at exactly 1200×800px
- [ ] Share sheet opens with pre-filled image and text from `ComparisonView`
- [ ] Sharing to Photos app saves composite correctly
- [ ] 12 screenshots generated at correct pixel dimensions
- [ ] App submitted to App Store Review without binary rejection

---

## Composite Score Implementation Reference

```swift
// In VisionRanker.swift — score normalization
func computeCompositeScores(candidates: [MatchCandidate]) -> [MatchCandidate] {
    guard !candidates.isEmpty else { return [] }

    // Normalize geo scores (distance in meters, max 100m)
    let maxGeo = candidates.compactMap { $0.distanceMeters }.max() ?? 100.0
    // Normalize vision scores (VNFeaturePrintObservation distance, iOS 17: range ~0–2)
    let maxVision = candidates.compactMap { $0.visionDistance }.map { Double($0) }.max() ?? 2.0

    return candidates.map { candidate in
        var c = candidate
        let geoScore = candidate.distanceMeters / maxGeo
        let visionScore = candidate.visionDistance.map { Double($0) / maxVision } ?? geoScore
        c.compositeScore = 0.7 * geoScore + 0.3 * visionScore
        c.confidenceLabel = {
            switch c.compositeScore {
            case ..<MatchCandidate.strongThreshold: return .strongMatch
            case ..<MatchCandidate.goodThreshold:  return .goodMatch
            default:                                return .nearby
            }
        }()
        return c
    }.sorted { $0.compositeScore < $1.compositeScore }
}
```

---

## Known Risks Summary

| Risk | Severity | Phase | Mitigation | Fallback |
|------|----------|-------|------------|----------|
| SF coverage sparse (Wikimedia-only source) | HIGH | 0 | Run SF tiles first; Flickr Commons contingency | Drop SF from Phase 0, ship NYC-only |
| Vision distances uniformly high for historical photos | HIGH | 1 | Benchmark in scratch playground before full implementation | Remove Vision, go 100% geo scoring |
| Coverage density below 25% in urban cores | HIGH | 0 | Audit before proceeding; adjust radius | Cannot ship v1 without passing density gate |
| NYPL image server down | MEDIUM | 0 | Server confirmed live March 2026; spot-check during ingestion | OldNYC `url` field → `digitalgallery.nypl.org` fallback |
| Magnetometer error in urban canyons | MEDIUM | 1 | ±45° filter; skip if headingAccuracy > 45° | Heading filter always skipped; GPS-only matching |
| `photos.db` exceeds 200MB bundle size | MEDIUM | 2 | Per-city SQLite files loaded on demand | Ship only 3 highest-density cities in v1 |
