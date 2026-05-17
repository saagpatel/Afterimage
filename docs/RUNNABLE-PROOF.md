# Afterimage — Runnable Proof Path

A one-pass walkthrough from a clean checkout to a working in-simulator demo of
the historical photo overlay. Each step has a command, an expected result, and
a quick "if it fails" pointer.

> **Audience:** anyone resuming after a long pause, demoing the app to someone
> else, or capturing a baseline before changes.

## Latest verification

Verified on 2026-05-17:

- `xcodegen generate` recreated `Afterimage.xcodeproj` without leaving tracked
  file changes.
- XcodeBuildMCP simulator tests passed on the `Afterimage` scheme: 48 passed,
  0 failed, 5 skipped.
- XcodeBuildMCP build/run succeeded on the configured iPhone simulator, launched
  bundle `com.afterimage.app`, and exposed the main UI controls for gallery,
  capture, and map.

Still requiring manual or device proof:

- Physical camera capture, live GPS/heading behavior, and share-sheet export.
- A seeded simulator photo/location walkthrough that reaches a non-empty match
  result and slider reveal.

---

## 0. Prerequisites

- macOS (iOS toolchain required)
- Xcode 26.3+ (matches `project.yml`)
- Python 3.11+ (for `DataPipeline/`)
- XcodeGen (`brew install xcodegen`) — `project.yml` is the source of truth
- A real Apple developer account if you want to run on a device. Simulator
  works without one.

```bash
xcodebuild -version
xcodegen --version
python3 --version
```

---

## 1. Regenerate the Xcode project from `project.yml`

```bash
cd /Users/d/Projects/Afterimage
xcodegen generate
```

**Expected:** `Afterimage.xcodeproj` is rebuilt against `project.yml`. No
warnings.

**If it fails:** `xcodegen --quiet generate` to see clean errors; usually a
missing folder or new file not declared in `project.yml`.

---

## 2. Build for simulator

```bash
xcodebuild \
  -project Afterimage.xcodeproj \
  -scheme Afterimage \
  -configuration Debug \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro,OS=latest' \
  build
```

**Expected:** `BUILD SUCCEEDED`. Warnings about deprecated APIs are OK if they
are not new (compare against the last green commit `c29f1ef`).

**If it fails:**
- Verify `DEVELOPMENT_TEAM` is set in `project.yml` (commit `95f2915`).
- `xcodebuild -showsdks` to confirm an iOS 17+ SDK is available.
- Clean the build with `xcodebuild clean` then retry.

---

## 3. Run the unit-test suite

```bash
xcodebuild \
  -project Afterimage.xcodeproj \
  -scheme Afterimage \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro,OS=latest' \
  test
```

**Expected:** `TEST SUCCEEDED`. Coverage includes:
- `DatabaseManagerTests` — SQLite open + schema
- `HeadingFilterTests` — heading window filter (45° default, skip when
  `headingAccuracy > 45°`)
- `MatchingServiceTests` — composite score (70% geo + 30% vision)
- `SpatialQueryTests` — bounding-box + Haversine ≤100m

**If it fails:** look at the test name; the test file is at
`AfterimageTests/<TestName>.swift`. Most failures are fixture-data or
GRDB-version-related.

---

## 4. Verify the data pipeline (optional but recommended)

The data pipeline builds the `photos.db` SQLite index that gets bundled into
the app. It is **dev-time only** — not run on device.

```bash
cd /Users/d/Projects/Afterimage/DataPipeline
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt

# Ingest one source as a smoke test (Wikimedia is the most stable)
python3 ingest_wikimedia.py --city nyc

# Build the index from all ingested rows
python3 build_index.py

# Coverage audit (gate that Phase 0 widens past 2 cities)
python3 audit_coverage.py
```

**Expected:**
- `photos.db` produced under `DataPipeline/output/`
- Coverage audit reports ≥25% of 100m grid cells covered for the cities you
  ingested
- Commit `bfc2390` widened the pipeline to NYC, SF, Chicago — re-running with
  `--city all` should reproduce the 3-city dataset

**If it fails:**
- Wikimedia/LoC APIs throttle — wait, retry. The ingest scripts log rate-limit
  hits.
- Memory ballooning during index build → reduce batch size in
  `build_index.py`.

---

## 5. Replace the bundled `photos.db` (if you regenerated one in step 4)

```bash
cp DataPipeline/output/photos.db Afterimage/Resources/photos.db
```

Rebuild (step 2) so Xcode picks up the new bundle resource.

**Skip this step if you're demoing the as-shipped DB.** The bundle's existing
`photos.db` is the one tied to the most recent commit.

---

## 6. Launch the app in simulator and walk the demo

```bash
open -a Simulator
# In the simulator: Features > Location > Custom Location...
#   NYC: 40.7128, -74.0060
#   SF:  37.7749, -122.4194
#   Chicago: 41.8781, -87.6298
```

Then in Xcode: hit Run (Cmd-R) on the `Afterimage` scheme with the simulator
selected.

### Demo flow

1. **Permission prompts** — Location, Camera. Accept both. Without Location,
   no spatial query; without Camera, only camera-roll mode works.
2. **Capture or pick a photo**. For a quick simulator demo, use a known
   camera-roll photo set to the NYC location. (Simulator → Features > Photos
   > Add to Library, then set location via Features > Location.)
3. **Wait for match**. The matching pipeline runs:
   - Spatial query (≤100m, ~20 candidates)
   - Heading filter (±45° if `headingAccuracy` is good)
   - Thumbnail fetch (Kingfisher, concurrent)
   - Vision feature-print ranking (composite score: 70% geo + 30% vision)
4. **Slider reveal**. Drag the vertical slider on the comparison view. The
   historical image fades in beneath the present-day photo.
5. **Share composite**. Tap Share → `UIActivityViewController` opens with the
   composite image rendered.

### What "works" looks like

- Match returns at least 1 candidate for the NYC test location
- Slider drag is smooth (60 FPS)
- Composite share renders both images
- No crash, no permission loops

---

## 7. Verify the security/privacy posture

```bash
# Privacy manifest present (commit 651a5f4)
ls Afterimage/PrivacyInfo.xcprivacy

# DEVELOPMENT_TEAM set for App Store signing (commit 95f2915)
grep DEVELOPMENT_TEAM project.yml

# No accounts / backend dependencies
grep -r "https://api\." Afterimage --include='*.swift' | head -5
# Expected: empty or only Wikimedia thumbnail fetches
```

---

## 8. App Store metadata sanity (commit `c29f1ef`)

```bash
cat APPSTORE-METADATA.md | head -20
```

Verify subtitle, description, keywords, and privacy questions match the
intended pitch. Screenshots are committed separately when ready.

---

## Build-proof source of truth

This checklist mirrors the build proof captured at commits:

- `bfc2390` — pipeline expanded to NYC, SF, Chicago
- `78d9f1e` — vision: double continuation resume fix
- `651a5f4` — privacy manifest
- `95f2915` — DEVELOPMENT_TEAM for App Store signing
- `c29f1ef` — App Store Connect metadata

If a step regresses, bisect against these commits.

---

## What "Phase 1" success means (per CLAUDE.md)

Phase 1 is "Core App — Camera → Match → Slider". Success criteria for the
runnable proof:

| Capability | Verification step |
|---|---|
| Camera capture works | Step 6, action 2 |
| Camera-roll picker works | Step 6, action 2 alternative |
| MatchingService returns ≥1 candidate at known cities | Step 6, action 3 |
| Slider overlay reveals historical image | Step 6, action 4 |
| Share composite renders | Step 6, action 5 |
| Privacy manifest present | Step 7 |
| Tests pass | Step 3 |

Phase 1 widening (more cities, more sources, ML re-ranking refinements) is
out-of-scope here; this doc only proves the current state runs.
