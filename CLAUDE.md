# Afterimage

Free iOS app (iPhone-only): match a photo to a geolocated historical photograph from the same location. Core interaction is a draggable vertical slider revealing the historical image beneath the present-day photo. All matching happens on-device against a bundled SQLite index; no backend, no accounts.

## Stack
- Language: Swift 5 language mode (`SWIFT_VERSION = 5.0`), built with a Swift 6.1+ toolchain
- UI: SwiftUI (iOS 17+ minimum — no UIKit views except AVFoundation camera wrapper)
- Database: SQLite via GRDB.swift 7.x (7.10 locked) — typed Swift wrappers, fast spatial queries
- Image loading: Kingfisher 8.x (8.8 locked) — async fetch + disk cache for thumbnails
- Image ML: Vision framework (`VNGenerateImageFeaturePrintRequest`) — on-device feature print similarity
- Location: CoreLocation (CLLocationManager + CLHeading)
- Camera: AVFoundation (photo capture pipeline)
- Data pipeline: Python 3 (dev-time only, not shipped); collectors need `DataPipeline/requirements.txt` (aiohttp, requests, tqdm), while the index build and its tests are stdlib-only (sqlite3, unittest)

## Build / Test / Run
Xcode 26.6 is what CI uses (GitHub `macos-26` runner image, iOS Simulator 26.5 SDK) and is the only
verified version. The lowest Xcode that can resolve the locked packages is 16.3, because GRDB 7.10
declares `swift-tools-version:6.1`; that floor is untested. `xcodeVersion: "26.3"` in `project.yml` is
only XcodeGen's project-format hint, not a requirement. The first build resolves GRDB and Kingfisher
through SwiftPM, which fetches them from GitHub, so it needs network access unless they are cached.

There is no `Package.swift`: this is an Xcode project,
so everything runs through `xcodebuild` against a simulator. The Makefile wraps that, and picks
the first available iPhone simulator exactly the way `.github/workflows/ci.yml` does.

```sh
make build   # compile for the simulator
make test    # full suite: 58 tests, a few minutes. 5 skip by design (Vision feature
             # print is unavailable on the simulator and needs a real device)
make run     # opens the project in Xcode; an iOS app launches from there, not the CLI
```

The Python data pipeline under `DataPipeline/` is dev-time only, is not shipped in the app,
and has its own fast suite, which needs only the Python standard library:

```sh
(cd DataPipeline && python3 -m unittest -v test_pipeline.py)   # 5 tests, <1s
```

See IMPLEMENTATION-ROADMAP.md for full phase details and verification checklist.

Current phase: **Phase 3: Confidence UI + Polish** (Phases 0–2 complete)

## Conventions
- Use `guard let` or `try?` with explicit fallback — force-unwraps (`!`) only inside `fatalError`/`precondition`
- File naming: PascalCase for Swift types and files, camelCase for variables
- Architecture: feature-based folder structure (`Features/Camera/`, `Features/Matching/`, etc.)
- Async: Swift async/await only — no Combine, no callbacks
- Open `photos.db` as read-only `DatabasePool` (GRDB); write user data elsewhere
- Preprocess images to grayscale before `VNGenerateImageFeaturePrintRequest` (Vision requirement)
- No third-party analytics or crash reporting SDKs in v1

## Gotchas
- `photos.db` is a read-only bundled asset (~80–200MB); opening it writable corrupts the bundle
- Keep all user photos, location data, and usage telemetry strictly on-device — no off-device transmission
- Request camera/location permissions only when the user first taps camera/gallery, not on app launch
- Phase 0 scope gate: data pipeline + SQLite index only; no UI; expand beyond 2 cities only after density audit passes (≥25% of 100m grid cells covered)

## Key Decisions
| Decision | Choice | Rationale |
|----------|--------|-----------|
| Index approach | Bundled SQLite (`photos.db`, ~80–200MB) | Live API per photo = 2–4s added latency + offline broken |
| NYC photos source | OldNYC dataset (GitHub, ~25K geolocated NYPL photos) | NYPL Space/Time archived Oct 2024; OldNYC has same photos with GPS coords |
| Vision role | Re-ranking only (not primary filter) | Vision needs thumbnails downloaded first; can't cold-filter |
| Heading filter | ±45° window | Magnetometer error in urban canyons can reach ±40°; ±30° drops valid matches |
| iOS minimum | iOS 17 | `VNFeaturePrintObservation` 768-dim normalized vectors require iOS 17 |
| Composite score | GPS/heading 70% + Vision 30% | Historical photos are stylistically dissimilar; Vision alone unreliable |
| V1 cities | NYC, SF, Chicago, DC, New Orleans, Boston | Highest OldNYC + Wikimedia photo density with GPS metadata |
| Monetization | Free, no paywall | Viral sharing is the growth mechanic — paywalls kill it |
| Design language | "Archival plate" — all color/type tokens live in `Afterimage/DesignSystem/Theme.swift` | One subject-derived identity: silver-gelatin darks, museum-label bone, albumen sepia reserved for the historical layer's voice (datelines, era chips, handle ring) |
| Color scheme | Dark-only (`.preferredColorScheme(.dark)` at root) | Camera-first app set in the plate archive's dark; system chrome must match |

<!-- portfolio-context:start -->
# Portfolio Context

## What This Project Is

Afterimage is a free iOS app (iPhone-only) that matches a photo you take — or select from your camera roll — to a geolocated historical photograph from the same location. The core interaction is a draggable vertical slider revealing the historical image beneath the present-day photo. All matching happens on-device against a bundled SQLite index; no backend, no accounts.

## Current State

**Phase 3: Confidence UI + Polish** (Phases 0–2 complete)
See IMPLEMENTATION-ROADMAP.md for full phase details and verification checklist.

## Stack

- Language: Swift 5 language mode (`SWIFT_VERSION = 5.0`), built with a Swift 6.1+ toolchain
- UI: SwiftUI (iOS 17+ minimum — no UIKit views except AVFoundation camera wrapper)
- Database: SQLite via GRDB.swift 7.x (7.10 locked) — typed Swift wrappers, fast spatial queries
- Image loading: Kingfisher 8.x (8.8 locked) — async fetch + disk cache for thumbnails
- Image ML: Vision framework (`VNGenerateImageFeaturePrintRequest`) — on-device feature print similarity
- Location: CoreLocation (CLLocationManager + CLHeading)
- Camera: AVFoundation (photo capture pipeline)
- Data pipeline: Python 3 (dev-time only, not shipped); collectors need `DataPipeline/requirements.txt` (aiohttp, requests, tqdm), while the index build and its tests are stdlib-only (sqlite3, unittest)

## How To Run

```sh
make build   # xcodebuild for the first available iPhone simulator (same as CI)
make test    # full XCTest suite
(cd DataPipeline && python3 -m unittest -v test_pipeline.py)
```

Xcode 26.6 is the CI-verified version; see Build / Test / Run above for the floor and the SwiftPM network fetch. Coding conventions are listed under Conventions above.

## Known Risks

- Do not add features not in the current phase of IMPLEMENTATION-ROADMAP.md
- Do not open `photos.db` as writable — it is a read-only bundled asset; never write user data to it
- Do not transmit user photos, location data, or any usage telemetry off-device
- Do not request camera or location permissions on app launch — only when the user first taps camera/gallery
- Do not run `VNGenerateImageFeaturePrintRequest` on color images — always convert to grayscale first
- Do not use Combine or callback-based async — async/await only
- Do not add UI in Phase 0 — Phase 0 is data pipeline and SQLite index only
- Do not widen Phase 0 to more than 2 cities until density audit passes (≥25% of 100m grid cells covered)

## Next Recommended Move

Use this context plus the README and supporting docs to resume the next active task, then promote the repo beyond minimum-viable by capturing a dedicated handoff, roadmap, or discovery artifact.

<!-- portfolio-context:end -->

<!-- secondbrain-breadcrumb -->
## SecondBrain knowledge vault

Prior lessons, decisions, and context for this project live in SecondBrain at `wiki/maps/projects/afterimage.md`. The whole vault is searchable via the `engraph` MCP — query it for this project + its stack before non-trivial work.
