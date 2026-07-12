# Afterimage runnable proof

This runbook separates deterministic simulator evidence from physical-device and release evidence. A green simulator run does not prove camera hardware, GPS, compass, signing, or App Store acceptance.

## 1. Toolchain and project generation

Requirements: Xcode 26.3+, XcodeGen 2.45+, Python 3.11+.

```bash
cd /Users/d/Projects/Afterimage
xcodebuild -version
xcodegen --version
python3 --version
xcodegen generate
git diff --exit-code -- Afterimage.xcodeproj/project.pbxproj
```

The final command should be clean when the committed project matches `project.yml`. If a new Swift file was intentionally added, inspect and commit the generated project change.

## 2. Deterministic repository checks

```bash
git diff --check
python3 -m unittest discover -s DataPipeline -p 'test_*.py' -v
python3 -m compileall -q DataPipeline
test "$(sqlite3 Afterimage/Resources/photos.db 'PRAGMA integrity_check;')" = ok
```

These prove pipeline safety-unit behavior, Python syntax, patch hygiene, and SQLite structural integrity. They do not prove fresh remote ingestion or data density.

## 3. Release-configuration simulator build

```bash
xcodebuild build \
  -project Afterimage.xcodeproj \
  -scheme Afterimage \
  -configuration Release \
  -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath /tmp/afterimage-release-derived \
  CODE_SIGNING_ALLOWED=NO
```

Expected: `BUILD SUCCEEDED`. This is unsigned simulator evidence, not an archive or device build.

## 4. Simulator tests

```bash
SIMULATOR_ID="$(xcrun simctl list devices available | awk -F '[()]' '/iPhone/ { print $2; exit }')"
test -n "$SIMULATOR_ID"
xcodebuild test \
  -project Afterimage.xcodeproj \
  -scheme Afterimage \
  -destination "platform=iOS Simulator,id=${SIMULATOR_ID}" \
  -derivedDataPath /tmp/afterimage-test-derived \
  CODE_SIGNING_ALLOWED=NO
```

Expected: `TEST SUCCEEDED`. Record the executed, failed, and skipped totals. Vision feature-print tests may skip when that simulator runtime does not expose its Vision execution engine; CI or device evidence must cover the omitted path.

## 5. Deterministic comparison UI

The Debug build supports a synthetic comparison launch argument:

```bash
xcrun simctl launch booted com.afterimage.app --afterimage-demo-comparison
```

Verify:

- Slider, Side by Side, and Fade modes render.
- The slider responds to touch and VoiceOver adjustable actions.
- Multiple-match controls are reachable when multiple fixtures are supplied.
- Share produces a 1200×800 composite and opens the system share sheet.

This fixture does not prove camera, Photos metadata, remote image availability, or matching quality.

## 6. Bundled-data audit

```bash
python3 DataPipeline/audit_coverage.py Afterimage/Resources/photos.db
```

Current known state at the hardening checkpoint: 26,044 records, two sources, three populated cities, and 24.0% Manhattan grid coverage against the existing 25% gate. A nonzero exit is a real no-go signal; do not lower the threshold just to produce a passing receipt.

Remote ingestion is optional, slow, and provider-limited. Use an isolated virtual environment:

```bash
python3 -m venv /tmp/afterimage-pipeline-venv
/tmp/afterimage-pipeline-venv/bin/pip install -r DataPipeline/requirements.txt
```

The importers use bounded retry/backoff and atomic staging replacement. A provider failure must exit nonzero and preserve the previous staging snapshot. `build_index.py` validates multiple sources, NYC/SF/Chicago presence, and HTTPS thumbnails before atomically replacing its output. Never copy `DataPipeline/output/photos.db` into the app until its integrity and coverage audits pass.

## 7. Physical-device acceptance

Run on an iPhone using the intended signing team. Verify at minimum:

1. Denying and later granting Camera permission produces recoverable UI.
2. Capture starts once, takes a photo, and surfaces capture/configuration errors.
3. Location denial and a location timeout return to a usable screen.
4. A real location and compass heading produce bounded matching behavior.
5. Photos selection works with and without embedded location metadata.
6. Map fallback supplies a location for a GPS-less photo.
7. Real historical thumbnails load over HTTPS and attribution remains visible.
8. Slider, Side by Side, Fade, match selection, and share work with genuine images.
9. City galleries for NYC, San Francisco, and Chicago load and show details.
10. Airplane/offline mode produces honest image-unavailable states instead of implying full offline support.

Capture the device model, iOS version, commit SHA, and pass/fail notes. Camera/GPS/heading readiness remains unproven without this receipt.

## 8. Release and privacy preflight

Before any upload:

```bash
plutil -lint Afterimage/Info.plist
plutil -lint Afterimage/Resources/PrivacyInfo.xcprivacy
```

Then verify:

- the deep security scan completed;
- privacy wording acknowledges third-party archive image requests;
- App Privacy answers match actual behavior;
- public privacy-policy and support URLs resolve;
- authentic current-product screenshots exist;
- a signed Release archive validates using the intended Apple account.

Uploading, creating public listings, accepting agreements, changing pricing/territories, and submitting for review are operator-only actions.
