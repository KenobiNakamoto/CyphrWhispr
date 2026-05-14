#!/usr/bin/env bash
# Capture the CyphrWhispr Settings window to a PNG without requiring
# Screen Recording permission for the calling process.
#
# How it works:
#   1. Ensure CyphrWhispr is running (relaunches /Applications/CyphrWhispr.app
#      if not). Without a running instance the URL scheme can't fire.
#   2. Open `cyphr-whispr://open-settings` so the Settings window comes
#      forward — this routes through AppDelegate.handleURL.
#   3. Read the autosaved Settings window frame from NSUserDefaults
#      (`NSWindow Frame CyphrWhisprSettingsWindow`). Format is
#      "x y w h screenX screenY screenW screenH" in AppKit (bottom-left)
#      coordinates.
#   4. Convert to top-left coordinates (screencapture's coordinate system)
#      and call `screencapture -R x,y,w,h`. Region capture works without
#      Screen Recording permission for the caller (full-display capture
#      doesn't, but -R does — quirk of the system binary).
#
# Usage:
#   ./scripts/dev-screenshot.sh                       # writes /tmp/cyphr-settings.png
#   ./scripts/dev-screenshot.sh /tmp/foo.png          # custom path
#   ./scripts/dev-screenshot.sh --title-only out.png  # crops to just the title bar

set -euo pipefail

OUTPUT="${1:-/tmp/cyphr-settings.png}"
TITLE_ONLY=false
if [ "${1:-}" = "--title-only" ]; then
    TITLE_ONLY=true
    OUTPUT="${2:-/tmp/cyphr-settings-title.png}"
fi

APP="/Applications/CyphrWhispr.app"
BUNDLE_ID="com.cyphr.whispr"

# 1. Ensure the app is running. We don't `pkill` and relaunch — if the
#    user has dictation context, that would blow it away.
if ! pgrep -x CyphrWhispr >/dev/null; then
    echo "==> CyphrWhispr not running; launching."
    open "$APP"
    sleep 1
fi

# 2. Open the Settings window via the URL scheme registered in Info.plist.
echo "==> Requesting Settings window via cyphr-whispr://open-settings"
open "cyphr-whispr://open-settings"
# Let the window finish drawing before we capture. SwiftUI on first open
# does an internal layout pass; 0.6s is comfortably past that on Apple
# Silicon.
sleep 0.7

# 3. Find the running Settings window's actual CG bounds. We query
#    CGWindowListCopyWindowInfo directly via Swift — that returns
#    top-left-origin coordinates in the global CG coordinate space,
#    which is exactly what `screencapture -R` consumes. This is
#    multi-display-safe (the autosave frame on the secondary screen
#    needed manual y-flipping that broke on stacked displays).
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FRAME=$(swift "$SCRIPT_DIR/dev-find-settings-window.swift" 2>&1)
if [[ "$FRAME" != FRAME* ]]; then
    echo "ERROR: Settings window not found on screen." >&2
    echo "       Swift helper said: $FRAME" >&2
    exit 1
fi
# FRAME line looks like "FRAME 277 -937 880 632"
read -r _ WX TOP_Y WW WH <<< "$FRAME"

# 4. Capture the region.
if [ "$TITLE_ONLY" = true ]; then
    # The Settings window title strip is 28pt tall (see SettingsView.swift,
    # `titleStripHeight`). Capture that band only — the traffic-light row
    # plus the centred title.
    BAR_H=28
    echo "==> Capturing title bar only: ${WW}x${BAR_H} at (${WX},${TOP_Y})"
    screencapture -R "${WX},${TOP_Y},${WW},${BAR_H}" "$OUTPUT"
else
    echo "==> Capturing full Settings window: ${WW}x${WH} at (${WX},${TOP_Y})"
    screencapture -R "${WX},${TOP_Y},${WW},${WH}" "$OUTPUT"
fi

ls -lh "$OUTPUT"
echo "==> Saved: $OUTPUT"
