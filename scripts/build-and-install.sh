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
# Force xcodebuild to output into a repo-local DerivedData. Without this,
# xcodebuild picks a project-hashed folder under ~/Library/Developer/
# Xcode/DerivedData/ where the hash can change subtly across runs (cwd
# differences, Xcode previews touching files), and `ls -td` would
# sometimes pick a stale .app from a *different* DerivedData folder
# than the one xcodebuild actually wrote to. Repo-local kills that
# entire class of bug — and lives inside .gitignore'd build/.
DERIVED_DATA_PATH="${REPO_ROOT}/build/derived"

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
# -derivedDataPath pins output to our repo-local folder, so we know
# exactly where to copy from afterwards.
cd "${REPO_ROOT}"
set +e
xcodebuild \
    -project "${APP_NAME}.xcodeproj" \
    -scheme "${APP_NAME}" \
    -configuration "${CONFIGURATION}" \
    -destination 'platform=macOS' \
    -derivedDataPath "${DERIVED_DATA_PATH}" \
    build \
    2>&1 | tail -20
BUILD_EXIT=${PIPESTATUS[0]}
set -e

# --- Locate the freshly-built .app ---
BUILT_APP="${DERIVED_DATA_PATH}/Build/Products/${CONFIGURATION}/${APP_NAME}.app"

# --- Codesign retry for the iCloud xattr race ---
# The project sits inside ~/Library/Mobile Documents/com~apple~CloudDocs/
# (iCloud Drive). iCloud's FileProvider periodically re-attaches
# com.apple.FinderInfo and other xattrs to bundle contents DURING the
# build, after the pre-build "Strip iCloud xattrs" phase has already
# run. When that happens, codesign fails with
#   "resource fork, Finder information, or similar detritus not allowed"
# even though the Swift compile itself was clean. Detect the case (build
# exited non-zero AND the .app exists), strip xattrs from the bundle,
# and re-sign manually before giving up.
if [ ${BUILD_EXIT} -ne 0 ] && [ -d "${BUILT_APP}" ]; then
    echo "    Build exited ${BUILD_EXIT}; checking whether codesign was the only failure..."
    xattr -cr "${BUILT_APP}" 2>/dev/null || true
    ENT="${DERIVED_DATA_PATH}/Build/Intermediates.noindex/${APP_NAME}.build/${CONFIGURATION}/${APP_NAME}.build/${APP_NAME}.app.xcent"
    if [ -f "${ENT}" ]; then
        # Sign nested helper dylibs first (--deep won't traverse them on macOS 14+).
        find "${BUILT_APP}/Contents/MacOS" -name '*.dylib' -print0 | while IFS= read -r -d '' lib; do
            xattr -cr "${lib}" 2>/dev/null || true
            codesign --force --sign "CyphrWhispr Dev" -o runtime --generate-entitlement-der "${lib}" 2>/dev/null || true
        done
        # Sign the bundle proper.
        if codesign --force --sign "CyphrWhispr Dev" -o runtime \
                --entitlements "${ENT}" --generate-entitlement-der "${BUILT_APP}" 2>&1; then
            echo "    Manual codesign recovered the build."
            BUILD_EXIT=0
        else
            echo "    Manual codesign also failed — bailing." >&2
            exit ${BUILD_EXIT}
        fi
    fi
fi

if [ ${BUILD_EXIT} -ne 0 ]; then
    exit ${BUILD_EXIT}
fi

if [ ! -d "${BUILT_APP}" ]; then
    echo "ERROR: Built app not found at expected path: ${BUILT_APP}" >&2
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
