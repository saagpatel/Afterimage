# Afterimage

[![Swift](https://img.shields.io/badge/Swift-f05138?style=flat-square&logo=swift)](#) [![License](https://img.shields.io/badge/license-MIT-blue?style=flat-square)](#)

> Point your camera at a street corner and see what it looked like in 1920.

Afterimage matches your photo to a geolocated historical photograph from the same location and reveals it beneath your shot using a draggable slider. All matching runs on-device against a bundled SQLite index — no backend, no accounts, no data leaves your phone.

## Features

- **Live camera matching** — take a photo and get a historical match in under 5 seconds
- **Four-stage pipeline** — spatial bounding-box query → heading filter (±45°) → thumbnail fetch → Vision feature-print re-ranking
- **Draggable slider** — reveals the historical image beneath the present-day photo
- **Composite scoring** — 70% GPS/heading + 30% Vision similarity; labeled Strong Match, Good Match, or Nearby
- **Camera roll matching** — any photo with GPS EXIF metadata works; manual location picker for GPS-less images
- **City browse mode** — explore historical photos for any of 6 covered US cities (NYC, SF, Chicago, DC, New Orleans, Boston) without taking a photo

## Quick Start

### Prerequisites
- Full Xcode 26.6 (what CI's unpinned `macos-latest` image provided as of 2026-10; 16.3 is the untested minimum that can resolve the locked GRDB 7.10 package), iOS 17.0+ deployment target
- Network access on first build: SwiftPM fetches GRDB and Kingfisher from GitHub
- Physical iPhone (camera and GPS required for end-to-end matching)

### Installation
```bash
git clone https://github.com/saagpatel/Afterimage.git
cd Afterimage
open Afterimage.xcodeproj
```

### Usage
Build and run on a physical iPhone. Tap the camera button, photograph a landmark, and the app returns its best historical match with the comparison controls.

## Verification

Run from the repository root with full Xcode 26.6 (what CI's unpinned
`macos-latest` image provided as of 2026-10) selected (`xcode-select -p`). `xcodeVersion: "26.3"` in `project.yml`
is only XcodeGen's project-format hint, not the toolchain requirement. The first
build resolves GRDB and Kingfisher through SwiftPM, which needs network access.
You also need an installed, available iPhone simulator runtime. Command Line Tools alone
cannot build or test this iOS target. The checked-in Xcode project is ready to
open; project generation is not required for these commands.

```bash
make build
make test
```

`make test` runs the full XCTest target, matching `.github/workflows/ci.yml`.
For one suite, run the same `xcodebuild test -scheme Afterimage -destination
"platform=iOS Simulator,id=<available-UUID>" CODE_SIGNING_ALLOWED=NO` command
with `-only-testing:AfterimageTests/HeadingFilterTests` appended. Use an actual
UUID from `xcrun simctl list devices available`; simulator names vary by Xcode.

The data-index safety tests use synthetic rows and a temporary SQLite file:

```bash
(cd DataPipeline && python3 -m unittest -v test_pipeline.py)
```

These safety tests require Python 3.10+ and only the standard library; the
collector dependencies in `DataPipeline/requirements.txt` are not needed.
Do not run collection/download/index-release scripts merely to verify a change.
No standalone Swift lint/format command is configured. For changed comparison
controls, matching states or exports, also exercise the affected flow in the
simulator with fixture data; real camera/GPS matching needs a physical iPhone
and is separate from simulator tests. A passing build is not device evidence.

## Tech Stack

| Layer | Technology |
|-------|------------|
| Language | Swift 5 language mode on a Swift 6.1+ toolchain, async/await |
| UI | SwiftUI (iOS 17+), AVFoundation camera wrapper |
| Database | GRDB.swift 7.x (typed SQLite wrappers) |
| Image loading | Kingfisher 8.x (async + disk cache) |
| ML similarity | Vision framework (VNGenerateImageFeaturePrintRequest) |
| Location | CoreLocation (CLLocationManager + CLHeading) |

## License

MIT
