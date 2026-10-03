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

## Verification

Run from the repository root with full Xcode matching `project.yml` (currently
26.3) selected (`xcode-select -p`)
and an installed, available iPhone simulator runtime. Command Line Tools alone
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

For the field-walk confidence policy, the portable Swift fixture verifier can
run without building the iOS app:

```bash
swiftc Afterimage/Features/Matching/MatchConfidence.swift \
  scripts/verify-match-confidence.swift \
  -o /tmp/verify-match-confidence
/tmp/verify-match-confidence AfterimageTests/Fixtures/match-confidence-v1.json
```

XcodeGen is needed only when regenerating the project after `project.yml`
changes; the checked-in project can be built and tested directly. For the full
build, deterministic UI states and evidence boundaries, follow
[`docs/RUNNABLE-PROOF.md`](docs/RUNNABLE-PROOF.md).

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
