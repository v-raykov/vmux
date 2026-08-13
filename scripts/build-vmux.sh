#!/usr/bin/env bash
set -euo pipefail

# Builds vmux as a normal (Release) app that coexists with an installed cmux.
#
# reloadp.sh cannot be used for this: it builds cmux's own identity and runs
# `pkill -x cmux`, which would terminate an installed cmux. The isolation here
# follows reloads.sh (the staging Release build): build with the stock identity
# so entitlement signing still resolves, then patch the copied bundle.
#
# Usage:
#   ./scripts/build-vmux.sh              # build, print the app path
#   ./scripts/build-vmux.sh --install    # also install to /Applications/vmux.app
#   ./scripts/build-vmux.sh --launch     # also open the built app

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
cd "$PROJECT_DIR"

APP_NAME="vmux"
BUNDLE_ID="com.vmuxterm.app"
DERIVED_DATA="/tmp/vmux-release"
INSTALL=0
LAUNCH=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --install) INSTALL=1 ;;
    --launch) LAUNCH=1 ;;
    *) echo "Unknown option: $1" >&2; exit 2 ;;
  esac
  shift
done

# Entitlements are dropped, matching what the Debug configuration already does:
# the only entitlement is a keychain access group scoped to the bundle
# identifier, and keeping it makes Release demand a development certificate.
#
# Neither PRODUCT_NAME nor PRODUCT_BUNDLE_IDENTIFIER is overridden at build
# time. PRODUCT_NAME applies to every target, so each SPM resource bundle would
# be renamed and collide on one output path; a rewritten bundle identifier no
# longer matches the entitlements, which then demand a development certificate.
echo "==> Building ${APP_NAME} (Release)"
xcodebuild \
  -project cmux.xcodeproj \
  -scheme cmux \
  -configuration Release \
  -destination 'platform=macOS' \
  -derivedDataPath "$DERIVED_DATA" \
  CODE_SIGN_ENTITLEMENTS="" \
  build

BUILT_APP="${DERIVED_DATA}/Build/Products/Release/cmux.app"
if [[ ! -d "$BUILT_APP" ]]; then
  echo "error: ${BUILT_APP} was not produced" >&2
  exit 1
fi

APP_PATH="${DERIVED_DATA}/Build/Products/Release/${APP_NAME}.app"
rm -rf "$APP_PATH"
cp -R "$BUILT_APP" "$APP_PATH"
INFO_PLIST="${APP_PATH}/Contents/Info.plist"

plist_set() {
  local key="$1" type="$2" value="$3"
  /usr/libexec/PlistBuddy -c "Set :${key} ${value}" "$INFO_PLIST" 2>/dev/null \
    || /usr/libexec/PlistBuddy -c "Add :${key} ${type} ${value}" "$INFO_PLIST"
}

echo "==> Giving it its own identity"
plist_set CFBundleName string "$APP_NAME"
plist_set CFBundleDisplayName string "$APP_NAME"
plist_set CFBundleIdentifier string "$BUNDLE_ID"

# Sparkle's feed is cmux's appcast. Left alone, vmux would replace itself with
# cmux on its next update check.
plist_set SUEnableAutomaticChecks bool false
/usr/libexec/PlistBuddy -c "Delete :SUFeedURL" "$INFO_PLIST" 2>/dev/null || true

# The Release binary defaults to the per-user stable sockets, which an installed
# cmux is already using. Isolate them the way the staging build does.
APP_SUPPORT_DIR="$HOME/Library/Application Support/cmux"
plist_set "LSEnvironment:CMUX_BUNDLE_ID" string "$BUNDLE_ID"
plist_set "LSEnvironment:CMUX_SOCKET_PATH" string "/tmp/vmux.sock"
plist_set "LSEnvironment:CMUXD_UNIX_PATH" string "${APP_SUPPORT_DIR}/cmuxd-vmux.sock"

# Editing a bundle invalidates its signature, so re-sign ad hoc.
codesign --force --deep --sign - "$APP_PATH" >/dev/null 2>&1 || true

if [[ "$INSTALL" -eq 1 ]]; then
  DESTINATION="/Applications/${APP_NAME}.app"
  # Only ever quits vmux; an installed cmux is left running.
  /usr/bin/osascript -e "tell application id \"${BUNDLE_ID}\" to quit" >/dev/null 2>&1 || true
  rm -rf "$DESTINATION"
  cp -R "$APP_PATH" "$DESTINATION"
  APP_PATH="$DESTINATION"
  INFO_PLIST="${APP_PATH}/Contents/Info.plist"
  echo "==> Installed to ${DESTINATION}"
fi

echo "==> Identity"
echo "    bundle id: $(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$INFO_PLIST")"
echo "    name:      $(/usr/libexec/PlistBuddy -c 'Print :CFBundleName' "$INFO_PLIST")"
echo "    version:   $(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$INFO_PLIST") ($(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$INFO_PLIST"))"
echo "    sparkle:   $(/usr/libexec/PlistBuddy -c 'Print :SUFeedURL' "$INFO_PLIST" 2>/dev/null || echo 'feed removed, checks disabled')"
echo "    socket:    $(/usr/libexec/PlistBuddy -c 'Print :LSEnvironment:CMUX_SOCKET_PATH' "$INFO_PLIST")"
echo "==> App"
echo "    ${APP_PATH}"

if [[ "$LAUNCH" -eq 1 ]]; then
  open "$APP_PATH"
fi
