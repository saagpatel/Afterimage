# Afterimage

[![Swift](https://img.shields.io/badge/Swift-f05138?style=flat-square&logo=swift)](#) [![License](https://img.shields.io/badge/license-MIT-blue?style=flat-square)](#)

> Photograph a place and compare it with historical images taken nearby.

Afterimage is an iPhone app that uses location, optional camera heading, and on-device Vision analysis to rank geolocated historical photographs. Matching and user-photo processing happen on device against a bundled SQLite index. Historical image files are not bundled: the app downloads thumbnails from their source archives, so comparison and city browsing require a network connection.

## Current capabilities

- Capture a photo or choose one from Photos.
- Use embedded photo location or select a location on a map.
- Search within 100 metres, with a 500-metre fallback, and optionally filter by heading.
- Rank up to five matches using geographic and Vision feature distances.
- Compare results with Slider, Side by Side, and Fade modes.
- Share a generated comparison image.
- Browse historical photographs for New York City, San Francisco, and Chicago.
- Handle unavailable permissions, sensors, camera configuration, and bundled data without hanging or crashing.

## Data and privacy

- Bundled index: 26,044 metadata records in a read-only 13 MB SQLite database.
- Current city counts: NYC 25,657; Chicago 245; San Francisco 142.
- Sources: OldNYC and Wikimedia Commons.
- No account, analytics SDK, advertising SDK, or Afterimage backend.
- User photos and precise location are processed locally and are not uploaded by the app.
- Historical-image requests go directly to archive hosts. Those hosts receive ordinary network metadata such as IP address and the requested image URL.

## Build and test

Prerequisites: Xcode 26.3+, XcodeGen 2.45+, and an iOS 17+ SDK.

```bash
git clone https://github.com/saagpatel/Afterimage.git
cd Afterimage
xcodegen generate

xcodebuild build \
  -project Afterimage.xcodeproj \
  -scheme Afterimage \
  -configuration Release \
  -destination 'generic/platform=iOS Simulator' \
  CODE_SIGNING_ALLOWED=NO
```

Run the full test suite against any installed iPhone simulator:

```bash
SIMULATOR_ID="$(xcrun simctl list devices available | awk -F '[()]' '/iPhone/ { print $2; exit }')"
xcodebuild test \
  -project Afterimage.xcodeproj \
  -scheme Afterimage \
  -destination "platform=iOS Simulator,id=${SIMULATOR_ID}" \
  CODE_SIGNING_ALLOWED=NO
```

Pipeline safety checks do not require downloading source data:

```bash
python3 -m unittest discover -s DataPipeline -p 'test_*.py' -v
python3 -m compileall -q DataPipeline
sqlite3 Afterimage/Resources/photos.db 'PRAGMA integrity_check;'
```

See [docs/RUNNABLE-PROOF.md](docs/RUNNABLE-PROOF.md) for simulator and physical-device proof boundaries.
See [PRIVACY.md](PRIVACY.md) for the repository-hosted privacy-policy draft.

## Release posture

The app is not yet represented as App Store ready. Open gates include:

- the repository-wide deep security scan;
- the existing Manhattan density audit (currently 24.0% against a 25% gate);
- physical-device camera, location, and heading validation;
- final privacy-policy/support URLs, screenshots, signing archive, and App Store Connect validation.

`APPSTORE-METADATA.md` is a draft grounded in the current binary. App Store Connect upload, legal acceptance, and submission remain operator actions.

## Stack

| Layer | Technology |
|---|---|
| Language | Swift, structured concurrency |
| UI | SwiftUI and AVFoundation |
| Database | GRDB.swift 7.x / SQLite |
| Image loading | Kingfisher 8.x |
| Similarity | Vision feature prints |
| Sensors | CoreLocation and AVFoundation |
| Data pipeline | Python, aiohttp, SQLite |

## License

MIT
