# Afterimage Repository Guide

Afterimage is an iPhone historical field-walk instrument. It uses a bundled read-only archive metadata index plus current on-device signals to present candidates, explain uncertainty, and refuse overlays when evidence is insufficient or contradictory.

## Current product contract

- A historical candidate is not a verified identification.
- `MatchEvidence` contains observations; `MatchConfidenceEngine` owns decision policy; `MatchExplanationPresenter` owns wording.
- Only `.confident` may display an overlay.
- Missing heading, image, provenance, or visual evidence must stay missing.
- Candidate scores must not be normalized against the current result set.
- Manual alignment is presentation state and must never strengthen confidence.
- Automated tests may use only bundled fixtures, generated images, and injected local loaders.
- The bundled database is read-only. User pairs are stored separately under Application Support.
- Afterimage does not upload user photos, location, or heading. Archive thumbnail requests still disclose ordinary network metadata to archive hosts.
- Sharing is always a distinct, user-initiated system action.

## Stack

- Swift / SwiftUI, iOS 17+
- AVFoundation camera wrapper
- Core Location
- GRDB.swift 7.x, read-only `DatabasePool`
- Kingfisher 8.x archive thumbnail cache/fetch
- Vision grayscale feature prints
- Python development-time data pipeline
- XcodeGen; `project.yml` is the project source of truth

## Main surfaces

- `Afterimage/Features/Matching/MatchConfidence.swift` — evidence, refusal policy, calibration
- `Afterimage/Data/Models/HistoricalPhoto.swift` — archive record and `MatchCandidate`
- `Afterimage/Features/Matching/MatchingService.swift` — spatial, heading, image, Vision orchestration
- `Afterimage/Features/Comparison/FieldWalkView.swift` — instrument flow and accessibility
- `Afterimage/Features/Comparison/LocalPairStore.swift` — protected app-local saves
- `AfterimageTests/Fixtures/match-confidence-v1.json` — frozen deterministic corpus
- `docs/FIELD-INSTRUMENT.md` — product/model contract
- `docs/LIMITATIONS.md` — current claim ceiling
- `docs/RUNNABLE-PROOF.md` — exact verification path

## Build and checks

```bash
xcodegen generate
xcodebuild -project Afterimage.xcodeproj -scheme Afterimage \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max,OS=latest' test
```

Toolchain-light confidence and pipeline checks are documented in `docs/RUNNABLE-PROOF.md`. Do not claim build or runtime success when only syntax parsing or fixture verification ran.

## Current data facts

The bundled index has 26,044 records: New York City 25,657, Chicago 245, and San Francisco 142. Washington, D.C., New Orleans, and Boston have zero bundled records and must remain disabled unless the database changes and the live count is re-read. Most records lack heading metadata; see `docs/LIMITATIONS.md`.

## Engineering constraints

- Preserve async/await; do not introduce Combine for pipeline work.
- Keep Vision preprocessing grayscale.
- Keep permissions user-initiated and recoverable.
- Do not silently discard candidates because optional evidence or an archive image is unavailable.
- Keep Xcode project changes generated from `project.yml`.
- Update fixture calibration and limitation docs whenever confidence policy changes.
- Treat thumbnails and full-resolution images as different quality/privacy/performance surfaces.
- No accounts, analytics, tracking, cloud sync, or credentials.

## Current state

The uncertainty-aware vertical slice is implemented locally. On 2026-09-06 under Xcode 26.6 / Swift 6.3.3 and iOS 26.5, it builds, links, installs, and launches on an iPhone 17 Pro Simulator; the full suite executed 75 tests with zero failures and five explicitly skipped Vision feature-print tests. Eight deterministic UI states plus Increased Contrast and largest-accessibility-size layouts were visually inspected, including a responsive-header fix. Live VoiceOver hierarchy/action readback, app-level profiling, supported-device Vision execution, and bounded physical-device field evidence remain separate gates.
