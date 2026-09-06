#!/bin/bash
# Capture App Store screenshots from the simulator using the DEBUG
# demo launch arguments. Output: screenshots/iphone-69/*.png at the
# simulator's native resolution.
#
# NOTE: the demo comparison fixture uses synthetic proof images. These
# captures verify the pipeline and the chrome; the shipped hero shots
# need real captures at covered locations (see APPSTORE-METADATA.md).
set -euo pipefail

cd "$(dirname "$0")/.."

DEVICE_NAME="${AFTERIMAGE_SIMULATOR_NAME:-iPhone 17 Pro Max}"
BUNDLE_ID="com.afterimage.app"
OUT_DIR="screenshots/iphone-69"

SIMULATOR_ID="$(xcrun simctl list devices available | awk -F '[()]' -v name="$DEVICE_NAME" \
  'index($0, name) { print $2; exit }')"
if [ -z "$SIMULATOR_ID" ]; then
  SIMULATOR_ID="$(xcrun simctl list devices available | awk -F '[()]' \
    '/\(Booted\)/ { print $2; exit }')"
fi
if [ -z "$SIMULATOR_ID" ]; then
  echo "No available $DEVICE_NAME or booted simulator" >&2
  exit 1
fi

DEVICE_NAME="$(xcrun simctl list devices available | awk -F '[()]' -v id="$SIMULATOR_ID" \
  'index($0, id) { sub(/^[[:space:]]*/, "", $1); sub(/[[:space:]]*$/, "", $1); print $1; exit }')"

echo "Building for $DEVICE_NAME ($SIMULATOR_ID)…"
xcodebuild build \
  -scheme Afterimage \
  -destination "platform=iOS Simulator,id=$SIMULATOR_ID" \
  CODE_SIGNING_ALLOWED=NO -quiet

APP_PATH="$(xcodebuild -scheme Afterimage \
  -destination "platform=iOS Simulator,id=$SIMULATOR_ID" \
  -showBuildSettings 2>/dev/null \
  | awk '/ BUILT_PRODUCTS_DIR/ { print $3; exit }')/Afterimage.app"

xcrun simctl boot "$SIMULATOR_ID" 2>/dev/null || true
xcrun simctl bootstatus "$SIMULATOR_ID"
xcrun simctl install "$SIMULATOR_ID" "$APP_PATH"

mkdir -p "$OUT_DIR"

capture() {
  local name="$1"; shift
  xcrun simctl terminate "$SIMULATOR_ID" "$BUNDLE_ID" 2>/dev/null || true
  # SpringBoard can still be completing termination when the next launch is sent.
  sleep 1
  xcrun simctl launch "$SIMULATOR_ID" "$BUNDLE_ID" "$@"
  sleep 6
  xcrun simctl io "$SIMULATOR_ID" screenshot "$OUT_DIR/$name.png"
  echo "captured $OUT_DIR/$name.png"
}

capture "01-fieldwalk-confident" --afterimage-demo-comparison
capture "02-fieldwalk-uncertain" --afterimage-demo-uncertain
capture "03-fieldwalk-conflict" --afterimage-demo-conflict
capture "04-fieldwalk-insufficient" --afterimage-demo-insufficient
capture "05-no-match" --afterimage-demo-no-match
capture "06-location-unavailable" --afterimage-demo-unavailable-location
capture "07-city-selector" --afterimage-demo-cities
capture "08-camera-enable"

xcrun simctl terminate "$SIMULATOR_ID" "$BUNDLE_ID" 2>/dev/null || true
echo "Done. $(sips -g pixelWidth -g pixelHeight "$OUT_DIR/01-fieldwalk-confident.png" | tail -2 | awk '{print $2}' | paste -sd 'x' -) px"
