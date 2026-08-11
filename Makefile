.PHONY: build test clean run

SCHEME := Afterimage
# First available iPhone simulator, matching what .github/workflows/ci.yml does.
SIM_ID = $(shell xcrun simctl list devices available | awk -F '[()]' '/iPhone/ { print $$2; exit }')
DEST = platform=iOS Simulator,id=$(SIM_ID)

build:
	xcodebuild build -scheme $(SCHEME) -destination "$(DEST)" CODE_SIGNING_ALLOWED=NO

test:
	xcodebuild test -scheme $(SCHEME) -destination "$(DEST)" CODE_SIGNING_ALLOWED=NO

# An iOS app bundle cannot be launched from the CLI the way a SwiftPM executable can.
run:
	open $(SCHEME).xcodeproj

clean:
	xcodebuild clean -scheme $(SCHEME)
