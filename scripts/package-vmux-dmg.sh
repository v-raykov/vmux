#!/usr/bin/env bash
set -euo pipefail

# Packages a built vmux.app into a drag-to-Applications DMG.
#
# Upstream's release pipeline uses the npm `create-dmg`, which would mean a
# global node install for one artifact; hdiutil ships with macOS and produces
# the same layout: the app beside an Applications alias.
#
# Usage:
#   ./scripts/package-vmux-dmg.sh                      # packages /Applications/vmux.app
#   ./scripts/package-vmux-dmg.sh path/to/vmux.app

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
cd "$PROJECT_DIR"

APP_PATH="${1:-/Applications/vmux.app}"
if [[ ! -d "$APP_PATH" ]]; then
  echo "error: ${APP_PATH} not found. Build it with ./scripts/build-vmux.sh" >&2
  exit 1
fi

INFO_PLIST="${APP_PATH}/Contents/Info.plist"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$INFO_PLIST")"
VOLUME_NAME="vmux ${VERSION}"
OUTPUT_DIR="${PROJECT_DIR}/dist"
OUTPUT="${OUTPUT_DIR}/vmux-${VERSION}-macos.dmg"

mkdir -p "$OUTPUT_DIR"
rm -f "$OUTPUT"

STAGING="$(mktemp -d)"
trap 'rm -rf "$STAGING"' EXIT

echo "==> Staging ${APP_PATH}"
# ditto rather than cp: it preserves the bundle's signature and symlinks.
ditto "$APP_PATH" "${STAGING}/vmux.app"
ln -s /Applications "${STAGING}/Applications"

echo "==> Building ${OUTPUT}"
hdiutil create \
  -volname "$VOLUME_NAME" \
  -srcfolder "$STAGING" \
  -fs HFS+ \
  -format UDZO \
  -ov \
  "$OUTPUT" >/dev/null

echo "==> Result"
echo "    $(du -h "$OUTPUT" | awk '{print $1}')  ${OUTPUT}"
echo "    signature: $(codesign -dv "${STAGING}/vmux.app" 2>&1 | rg '^Signature' || echo unknown)"
