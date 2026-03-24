# Afterimage

## Overview
Afterimage is a free iOS app (iPhone-only) that matches a photo you take — or select from your camera roll — to a geolocated historical photograph from the same location. The core interaction is a draggable vertical slider revealing the historical image beneath the present-day photo. All matching happens on-device against a bundled SQLite index; no backend, no accounts.

## Tech Stack
- Language: Swift 5.10+
- UI: SwiftUI (iOS 17+ minimum — no UIKit views except AVFoundation camera wrapper)
- Database: SQLite via GRDB.swift 6.x — typed Swift wrappers, fast spatial queries
- Image loading: Kingfisher 7.x — async fetch + disk cache for thumbnails
- Image ML: Vision framework (`VNGenerateImageFeaturePrintRequest`) — on-device feature print similarity
- Location: CoreLocation (CLLocationManager + CLHeading)
- Camera: AVFoundation (photo capture pipeline)
- Data pipeline: Python 3.12 + aiohttp + sqlite3 (dev-time only, not shipped)

## Development Conventions
- Swift: no force-unwraps (`!`) outside of fatalError/precondition; use `guard let` or `try?` with explicit fallback
- File naming: PascalCase for Swift types and files, camelCase for variables
- Architecture: feature-based folder structure (Features/Camera/, Features/Matching/, etc.)
- No third-party analytics or crash reporting SDKs in v1
- All async work via Swift async/await — no Combine, no callbacks
- GRDB: always open `photos.db` as read-only `DatabasePool`
- Vision: always preprocess images to grayscale before `VNGenerateImageFeaturePrintRequest`

## Current Phase
**Phase 1: Core App — Camera → Match → Slider**
See IMPLEMENTATION-ROADMAP.md for full phase details and verification checklist.

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

## Do NOT
- Do not add features not in the current phase of IMPLEMENTATION-ROADMAP.md
- Do not open `photos.db` as writable — it is a read-only bundled asset; never write user data to it
- Do not transmit user photos, location data, or any usage telemetry off-device
- Do not request camera or location permissions on app launch — only when the user first taps camera/gallery
- Do not run `VNGenerateImageFeaturePrintRequest` on color images — always convert to grayscale first
- Do not use Combine or callback-based async — async/await only
- Do not add UI in Phase 0 — Phase 0 is data pipeline and SQLite index only
- Do not widen Phase 0 to more than 2 cities until density audit passes (≥25% of 100m grid cells covered)
