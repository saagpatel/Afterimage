# Runnable Proof Path

This is the current verification contract for the uncertainty-aware field-walk slice. Run from the repository root unless a step says otherwise. Record exact toolchain, destination, commit/tree, and failures; do not convert a skipped runtime step into a pass.

## 1. Toolchain and project generation

```bash
xcode-select -p
xcodebuild -version
xcrun simctl list devices available
xcodegen --version
xcodegen generate
git diff --check
```

Expected for full proof: a full Xcode installation, an iOS 17+ Simulator, successful project generation, and no whitespace errors. Command Line Tools alone are insufficient for the Xcode build/runtime steps.

## 2. Toolchain-light deterministic checks

These do not require protected media, location, archive downloads, or a running app.

```bash
swiftc Afterimage/Features/Matching/MatchConfidence.swift \
  scripts/verify-match-confidence.swift \
  -o /tmp/verify-match-confidence
/tmp/verify-match-confidence AfterimageTests/Fixtures/match-confidence-v1.json

swiftc -O Afterimage/Features/Matching/MatchConfidence.swift \
  scripts/benchmark-match-confidence.swift \
  -o /tmp/benchmark-match-confidence
/usr/bin/time -lp /tmp/benchmark-match-confidence \
  AfterimageTests/Fixtures/match-confidence-v1.json

cd DataPipeline
python3 -m unittest -v test_pipeline
cd ..

plutil -lint Afterimage/Info.plist Afterimage/Resources/PrivacyInfo.xcprivacy
swiftc -frontend -parse $(rg --files Afterimage AfterimageTests -g '*.swift')
bash -n scripts/capture-screenshots.sh
```

Current fixture acceptance ceilings:

- fixture count at least 12;
- `fixtureBrierScore` at most 0.18;
- `fixtureExpectedCalibrationError` at most 0.18;
- refusal recall exactly 1.0 for known negatives;
- expected disposition accuracy exactly 1.0.

The same verifier also executes non-JSON adversarial cases for NaN, infinity, negative distance/precision, out-of-range heading, negative Vision distance, imprecise compass headings, and low-confidence archive headings. Invalid or unreliable observations must remain missing or be scored at their conservative uncertainty bound; they must not unlock the overlay.

The 2026-09-04 13-case report under Xcode 26.6 / Swift 6.3.3 was fixture Brier 0.0510, fixture ECE 0.1023, refusal recall 1.0, and disposition accuracy 1.0. The optimized policy benchmark completed 250,000 evaluations in 69.37 ms (about 3.60 million evaluations/second) with 6,651,904 bytes maximum resident set size. Those values describe only the frozen fixture corpus and Foundation policy path.

The provenance compatibility layer has a separate Foundation-only verifier:

```bash
swiftc \
  Afterimage/Data/Models/HistoricalAssetProvenance.swift \
  scripts/verify-provenance-contract.swift \
  -o /tmp/verify-provenance-contract
/tmp/verify-provenance-contract
```

It proves only that current index IDs and stored heading confidence are preserved while unavailable lineage stays unavailable. It does not prove that the current archive corpus contains source-record links, ingestion versions, coordinate origins, or other field-confidence metadata.

## 3. Build and XCTest

Choose an actually installed device rather than copying the example name blindly.

```bash
xcodebuild \
  -project Afterimage.xcodeproj \
  -scheme Afterimage \
  -configuration Debug \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max,OS=latest' \
  build

xcodebuild \
  -project Afterimage.xcodeproj \
  -scheme Afterimage \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max,OS=latest' \
  test
```

Required XCTest surfaces include confidence/refusal fixtures, spatial query, heading annotation/filter behavior, offline-injected matching, Vision ranking, database behavior, typed provenance unavailable states, location lifecycle recovery, local pair storage, and plate export.

## 4. Deterministic UI states

Build and install the Debug app, then launch each state separately:

```bash
xcrun simctl launch booted com.afterimage.app --afterimage-demo-comparison
xcrun simctl launch booted com.afterimage.app --afterimage-demo-uncertain
xcrun simctl launch booted com.afterimage.app --afterimage-demo-conflict
xcrun simctl launch booted com.afterimage.app --afterimage-demo-insufficient
xcrun simctl launch booted com.afterimage.app --afterimage-demo-unavailable-location
xcrun simctl launch booted com.afterimage.app --afterimage-demo-no-match
xcrun simctl launch booted com.afterimage.app --afterimage-demo-cities
```

Or capture all scripted states with:

```bash
bash scripts/capture-screenshots.sh
```

The fixture images are generated inside the Debug build. They prove no real historical match and are not publication assets.

## 5. Visual and accessibility readback

For every required state, preserve a fresh screenshot and inspect the live accessibility hierarchy. Confirm:

- candidate title, city/date when available, distance, and disposition are distinguishable;
- only `confident` exposes `comparison-slider`;
- uncertain, conflicting, and insufficient states expose `overlay-refusal` and the primary reason;
- `unavailable-location-state` and `no-match-state` are separate;
- `match-confidence-summary`, `why-this-match`, `alignment-controls`, `match-provenance`, explicit lineage gaps, and `local-save-result` are announced coherently;
- the comparison slider responds to VoiceOver adjustable actions;
- alignment values and provenance reflow at accessibility Dynamic Type sizes;
- contrast, truncation, scrolling, and 44-point controls are acceptable on the smallest supported screen.

Source identifiers are not runtime accessibility proof.

## 6. Performance, memory, and energy

Use a Release or profiling build and project-owned fixtures first. Measure at least:

- capture/selection to first candidate list;
- spatial query, thumbnail load, Vision ranking, and total match latency (existing logs identify stages);
- overlay drag frame pacing before and after alignment changes;
- export render time and local write time;
- peak/resident memory while cycling all fixture states;
- energy over a representative orient → inspect → align → save session.

Use Instruments Time Profiler, Allocations, and Energy Log (or equivalent current Xcode tools). Preserve the destination, OS, build configuration, sample length, and raw trace location. Do not use the command-line confidence verifier as a substitute for camera/overlay/app profiling.

## 7. Bounded device field proof

This step requires a physical iPhone and explicit use of the operator's own test scene/photo. Do not access arbitrary Photos or location history.

Verify permission prompts, location accuracy, heading availability and dropout, candidate/refusal comprehension, archive-network failure, alignment, local save, and user-initiated share. Label each observation by its actual evidence boundary. A few local scenes cannot establish general matching efficacy.

## 8. Current verified state

On 2026-09-06, `/Applications/Xcode.app/Contents/Developer` is active with Xcode 26.6 / Swift 6.3.3, the iOS 26.5 Simulator runtime is installed, and an iPhone 17 Pro Simulator is available. XcodeGen regeneration, build, link, and the complete XCTest suite pass from a task-owned DerivedData directory. XCTest executed 75 tests with zero failures; five Vision feature-print tests skipped because this Simulator could not create an Espresso context.

The Debug app was installed and launched for confident, uncertain, conflicting, insufficient-evidence, no-match, unavailable-location, city-selector, and camera-entry states. Fresh 1206 x 2622 screenshots were visually inspected. The confidence states were distinct, only the confident fixture exposed the overlay, refusal states showed their primary reason, and no-match and unavailable-location rendered as separate recovery states. Increased Contrast rendered without a visible regression. A largest-accessibility-size run exposed a compressed header; the header was changed to stack responsively and a fresh screenshot confirmed readable, scrollable output.

This does not establish VoiceOver hierarchy/order or adjustable-action behavior because no accessibility-inspection tool was available in this run. It also does not establish Vision feature-print execution, app-level profiling, physical camera/location behavior, or real-world field efficacy. Exact next proof is an accessibility readback plus profiling on a destination that supports the required tools, followed separately by an explicitly authorized physical-device field session.

See `LIMITATIONS.md` for the exact claim ceiling and unblock condition.
