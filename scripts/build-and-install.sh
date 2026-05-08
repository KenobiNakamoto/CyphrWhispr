#!/usr/bin/env bash
# Build CyphrWhispr from source, install to /Applications, and relaunch.
#
# This is the canonical local-dev workflow — no Xcode UI required. After
# running this once, /Applications/CyphrWhispr.app is the live app the user
# launches like any other macOS app. Re-run whenever source changes to update
# the installed copy in place.
#
# Usage:
#   ./scripts/build-and-install.sh           # debug build, default
#   ./scripts/build-and-install.sh release   # release build (smaller, faster)
#   ./scripts/build-and-install.sh --no-launch   # build + install but don't open
#
# Side effects:
#   - Kills any running CyphrWhispr instance (so the binary can be replaced).
#   - Replaces /Applications/CyphrWhispr.app entirely.
#   - Re-launches the app unless --no-launch is passed.

set -euo pipefail

# --- Configuration ---
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="CyphrWhispr"
INSTALL_PATH="/Applications/${APP_NAME}.app"

# --- Argument parsing ---
CONFIGURATION="Debug"
LAUNCH=true
for arg in "$@"; do
    case "$arg" in
        release|--release|Release)
            CONFIGURATION="Release"
            ;;
        debug|--debug|Debug)
            CONFIGURATION="Debug"
            ;;
        --no-launch)
            LAUNCH=false
            ;;
        *)
            echo "Unknown argument: $arg" >&2
            echo "Usage: $0 [debug|release] [--no-launch]" >&2
            exit 2
            ;;
    esac
done

echo "==> Building ${APP_NAME} (${CONFIGURATION})"

# --- Kill running instance so the binary can be replaced ---
# pkill returns 1 if nothing matched; that's fine.
if pkill -x "${APP_NAME}" 2>/dev/null; then
    echo "    Stopped running instance."
    # Give launchd a beat to process the exit before we try to overwrite.
    sleep 1
fi

# --- Regenerate Xcode project from project.yml so any new files are picked up ---
# Cheap (<1s) and avoids the "I added a file but it's not in the project" foot-gun.
if command -v xcodegen >/dev/null 2>&1 && [ -f "${REPO_ROOT}/project.yml" ]; then
    cd "${REPO_ROOT}"
    xcodegen generate >/dev/null
    echo "    Regenerated Xcode project."
fi

# --- Build ---
cd "${REPO_ROOT}"
xcodebuild \
    -project "${APP_NAME}.xcodeproj" \
    -scheme "${APP_NAME}" \
    -configuration "${CONFIGURATION}" \
    -destination 'platform=macOS' \
    build \
    2>&1 | tail -20

# --- Locate the freshly-built .app ---
# DerivedData paths include a hash; -td orders by mtime so head -1 is freshest.
BUILT_APP=$(ls -td ~/Library/Developer/Xcode/DerivedData/${APP_NAME}-*/Build/Products/${CONFIGURATION}/${APP_NAME}.app 2>/dev/null | head -1)
if [ ! -d "${BUILT_APP}" ]; then
    echo "ERROR: Built app not found in DerivedData." >&2
    exit 1
fi
echo "    Built: ${BUILT_APP}"

# --- Replace the installed copy ---
# rm -rf the old bundle entirely (a partial overwrite via cp -R can leave stale
# files behind — bundles aren't atomic).
if [ -d "${INSTALL_PATH}" ]; then
    rm -rf "${INSTALL_PATH}"
fi
cp -R "${BUILT_APP}" "${INSTALL_PATH}"
echo "    Installed: ${INSTALL_PATH}"

# --- Launch ---
if [ "${LAUNCH}" = true ]; then
    open "${INSTALL_PATH}"
    echo "==> Launched ${APP_NAME}."
else
    echo "==> Build complete (launch skipped)."
fi
