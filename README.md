# Afterimage

[![Platform](https://img.shields.io/badge/platform-iOS%2017%2B-blue?logo=apple)](https://developer.apple.com/ios/)
[![Swift](https://img.shields.io/badge/swift-5.10-orange?logo=swift)](https://swift.org)
[![License](https://img.shields.io/badge/license-MIT-green)](LICENSE)
[![iPhone only](https://img.shields.io/badge/device-iPhone%20only-lightgrey?logo=apple)]()

Point your camera at a street corner and see what it looked like in 1920. Afterimage matches your photo to a geolocated historical photograph from the same location and reveals it beneath your shot using a draggable slider. All matching runs on-device against a bundled SQLite index — no backend, no accounts, no data leaves your phone.

## Features

- **Live camera matching** — take a photo, get a historical match in under 5 seconds
- **Camera roll matching** — select any photo with GPS EXIF metadata
- **Three comparison modes** — draggable slider overlay (hero), side-by-side, and animated crossfade
- **On-device matching pipeline** — four stages: spatial bounding-box query, heading filter (±45°), concurrent thumbnail fetch, and Vision feature-print re-ranking
- **Composite scoring** — 70% GPS/heading + 30% on-device Vision similarity; results labeled Strong Match, Good Match, or Nearby
- **Multi-match browsing** — up to 5 candidates in a horizontal thumbnail strip
- **Share sheet** — exports a 1200×800 composite JPEG of then-and-now
- **Covered cities** — NYC, SF, Chicago, DC, New Orleans, Boston (bundled SQLite index, ~80–200 MB)
- **Privacy-first** — no analytics, no tracking SDKs, no network calls beyond thumbnail fetch

## Tech Stack

| Layer | Technology |
|-------|-----------|
| Language | Swift 5.10, async/await throughout |
| UI | SwiftUI (iOS 17+), AVFoundation camera wrapper |
| Database | [GRDB.swift](https://github.com/groue/GRDB.swift) 7.x — typed Swift wrappers over bundled SQLite |
| Image loading | [Kingfisher](https://github.com/onevcat/Kingfisher) 8.x — async fetch + disk cache |
| ML similarity | Vision framework (`VNGenerateImageFeaturePrintRequest`) — on-device feature prints |
| Location | CoreLocation — `CLLocationManager` + `CLHeading` |
| Data pipeline | Python 3.12 + aiohttp (dev-time only, not shipped) |

## Prerequisites

- Xcode 16+ (project targets Xcode 26.3 / SDK)
- iOS 17.0 minimum deployment target
- A physical iPhone for camera and GPS features (Simulator cannot test end-to-end matching)
- Swift Package Manager resolves `GRDB.swift` and `Kingfisher` automatically on first build

## Getting Started

```bash
git clone https://github.com/saagpatel/Afterimage.git
cd Afterimage
open Afterimage.xcodeproj
```

Select your physical iPhone as the run destination, then build and run (`Cmd+R`). Camera and location permissions are requested lazily — only when you first tap the camera button or trigger a match.

To regenerate the bundled `photos.db` index (optional, dev-time only):

```bash
cd DataPipeline
pip install -r requirements.txt
python ingest_oldnyc.py
python ingest_wikimedia.py
python build_index.py
# Replace Afterimage/Resources/photos.db with the newly built file
```

## Project Structure

```
Afterimage/
├── Afterimage/
│   ├── App/                  # @main entry, AppState
│   ├── Features/
│   │   ├── Camera/           # AVFoundation preview + capture
│   │   ├── Matching/         # MatchingService, SpatialQuery, HeadingFilter, VisionRanker
│   │   ├── Comparison/       # SliderOverlayView, SideBySideView, FadeView
│   │   ├── Gallery/          # PHPickerViewController wrapper + map fallback
│   │   └── Share/            # Composite renderer + UIActivityViewController
│   ├── Data/
│   │   ├── Models/           # HistoricalPhoto, MatchCandidate types
│   │   ├── Database/         # DatabaseManager (read-only DatabasePool)
│   │   └── Cache/            # Kingfisher disk cache config
│   ├── Services/             # LocationService, ThumbnailFetcher
│   └── Resources/
│       └── photos.db         # Bundled SQLite index (do not compress)
├── DataPipeline/             # Python ingestion scripts — not in app target
│   ├── ingest_oldnyc.py
│   ├── ingest_wikimedia.py
│   ├── build_index.py
│   └── requirements.txt
└── AfterimageTests/          # XCTest unit tests (SpatialQuery, HeadingFilter, DatabaseManager)
```

## Screenshot

> _Screenshot placeholder — add a device frame showing the slider reveal._

## License

MIT — see [LICENSE](LICENSE).

Historical photographs are sourced from the [OldNYC / NYPL](https://www.oldnyc.org) dataset and [Wikimedia Commons](https://commons.wikimedia.org). Attribution and rights URIs are stored per-record in the bundled index and displayed in-app.
