#!/usr/bin/env bash
# Packs build/Murmur.app into build/Murmur-<version>.dmg (drag-to-Applications layout).
# Signs and notarizes the DMG too when a Developer ID identity and NOTARY_PROFILE are available.
#
#   scripts/make_dmg.sh            # uses an existing build/Murmur.app, or builds one
set -euo pipefail
cd "$(dirname "$0")/.."

APP=build/Murmur.app
[[ -d "$APP" ]] || scripts/build_release.sh

version="$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$APP/Contents/Info.plist")"
DMG="build/Murmur-$version.dmg"
STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT

ditto "$APP" "$STAGE/Murmur.app"
ln -s /Applications "$STAGE/Applications"
rm -f "$DMG"
hdiutil create -volname "Murmur $version" -srcfolder "$STAGE" -fs HFS+ -format ULFO -ov "$DMG" >/dev/null

identity="$(security find-identity -v -p codesigning | sed -n 's/.*"\(Developer ID Application: [^"]*\)".*/\1/p' | head -1 || true)"
if [[ -n "$identity" ]]; then
  codesign --force --sign "$identity" --timestamp "$DMG"
  if [[ -n "${NOTARY_PROFILE:-}" ]]; then
    xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait
    xcrun stapler staple "$DMG"
  fi
else
  echo "No Developer ID identity: the DMG is not signed (fine for local use)" >&2
fi
echo "Built $DMG"
