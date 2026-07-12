# Afterimage repository guide

Afterimage is an iPhone-only SwiftUI app that ranks geolocated historical photographs against a captured or selected photo. User-photo processing and matching are local. Historical image files are fetched from archive hosts named in the bundled metadata; the product is not fully offline.

## Source of truth

- `project.yml` defines the Xcode project; run `xcodegen generate` after adding or removing sources.
- `Afterimage/Resources/photos.db` is the shipped, read-only metadata index.
- `DataPipeline/audit_coverage.py` is the density gate; do not lower it merely to obtain a green result.
- `README.md`, `docs/RUNNABLE-PROOF.md`, and `APPSTORE-METADATA.md` must describe the current binary and bundled data, not planned features.

## Current shipped-data facts

- 26,044 records; approximately 13 MB.
- NYC: 25,657; Chicago: 245; San Francisco: 142.
- Sources: OldNYC and Wikimedia Commons.
- Historical thumbnails are remote HTTPS resources.
- The Manhattan 100 m grid audit is currently 24.0% against the existing 25% gate.

## Stack and conventions

- iOS 17+, SwiftUI, Swift structured concurrency.
- GRDB 7.x for read-only SQLite access.
- Kingfisher 8.x for remote historical images and disk cache.
- Vision feature prints for local visual re-ranking.
- CoreLocation for position and heading; AVFoundation for capture.
- Python/aiohttp/SQLite for the development-time data pipeline.
- Prefer explicit user-visible fallback states over `fatalError`, silent return, swallowed errors, or unbounded waits.
- Preserve actor/concurrency boundaries; do not pass non-Sendable AVFoundation, CoreLocation, or Vision objects between isolation domains.
- No analytics, advertising, account, or crash-reporting SDKs without an explicit product/privacy decision.
- Never transmit the user photo or precise user location to an Afterimage service.

## Build and verification

```bash
xcodegen generate
python3 -m unittest discover -s DataPipeline -p 'test_*.py' -v
python3 -m compileall -q DataPipeline
test "$(sqlite3 Afterimage/Resources/photos.db 'PRAGMA integrity_check;')" = ok
xcodebuild build -project Afterimage.xcodeproj -scheme Afterimage \
  -configuration Release -destination 'generic/platform=iOS Simulator' \
  CODE_SIGNING_ALLOWED=NO
```

Run tests on an installed iPhone simulator as documented in `README.md`. Vision feature-print tests may skip on simulator runtimes that do not expose the Vision engine; CI or physical-device evidence is needed for those paths.

## Release boundary

Do not claim App Store readiness while the deep security scan, 25% density gate, physical-device sensor proof, signing archive, privacy/support URLs, screenshots, or App Store Connect validation remain open. Do not upload or submit a build, accept agreements, or change Apple-account state without explicit operator approval.
