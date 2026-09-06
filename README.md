# Afterimage

Afterimage is an iPhone historical field-walk instrument. It compares a current photo and place with nearby archive records, explains the evidence for and against each candidate, and refuses to show a precise overlay when the available evidence is weak or contradictory.

## What the current build does

- Searches a bundled, read-only SQLite metadata index near the current or user-selected location.
- Preserves location precision, conservative heading compatibility, archive metadata quality, duplicate-record risk, image availability, and on-device Vision distance as typed evidence.
- Produces explicit `confident`, `uncertain`, `insufficientEvidence`, `conflictingSignals`, `unavailableLocation`, and `noMatch` states.
- Unlocks the comparison overlay only for a supported candidate; other states explain why the overlay is withheld.
- Guides a field walk through orienting, inspecting candidates, comparing, adjusting alignment, reviewing provenance and explicit lineage gaps, and saving a protected app-local pair.
- Offers a separate, deliberate system share sheet. Afterimage itself does not upload the user's photo or location.
- Includes local synthetic launch fixtures and a frozen confidence corpus for deterministic verification without protected user data.

The bundled index currently contains records for New York City, Chicago, and San Francisco. Coverage is highly uneven. Washington, D.C., New Orleans, and Boston appear as unavailable targets rather than pretending to be covered.

## Evidence boundary

The internal `fixtureEstimatedProbability` is calibrated only against the bundled 13-case policy-regression corpus. It is not displayed as a real-world probability and is not evidence of field matching efficacy. Historical image files are fetched from their archive hosts when they are not already cached; only metadata is fully bundled.

See `docs/FIELD-INSTRUMENT.md` for the model and refusal policy, `docs/RUNNABLE-PROOF.md` for verification, and `docs/LIMITATIONS.md` for the current claim ceiling.

## Local verification

Prerequisites for the full app path are Xcode 26.3 or newer, an iOS 17+ Simulator/runtime, and XcodeGen. The confidence engine and data pipeline have additional toolchain-light checks:

```bash
xcodegen generate

swiftc Afterimage/Features/Matching/MatchConfidence.swift \
  scripts/verify-match-confidence.swift \
  -o /tmp/verify-match-confidence
/tmp/verify-match-confidence AfterimageTests/Fixtures/match-confidence-v1.json

cd DataPipeline
python3 -m unittest -v test_pipeline
```

For the full build, tests, deterministic UI states, and evidence boundaries, follow `docs/RUNNABLE-PROOF.md`.

## Privacy

There are no accounts, analytics, advertising SDKs, or Afterimage-operated backend. User photos, precise location, and heading are used on device. Archive hosts can receive ordinary network request metadata when Afterimage downloads a historical image. A locally saved pair stays in the app container unless the user intentionally exports a copy through the system share sheet. See `PRIVACY.md`.

## Stack

- SwiftUI and AVFoundation, iOS 17+
- Core Location
- GRDB.swift 7.x with a read-only bundled SQLite database
- Kingfisher 8.x for archive-image cache/fetch
- Vision feature prints for an on-device visual signal
- Python for the development-time archive index pipeline

## License

MIT
