#!/bin/sh
# A release: Developer ID signed, in a disk image, notarized by Apple so it opens on any Mac.
#   app/vendor.sh     once, for the bundled Python and esptool
#   xcrun notarytool store-credentials ttycat    once, with an app-specific password
#   app/release.sh
# NOTARIZE=no stops before anything is sent to Apple.
set -eu

HERE=$(cd "$(dirname "$0")" && pwd)
APP="$HERE/build/ttycat.app"
DMG="$HERE/build/ttycat.dmg"

[ -d "$HERE/.vendor/python" ] || { echo "run app/vendor.sh first: a release can't rely on the buyer's Python" >&2; exit 1; }
IDENTITY=$(security find-identity -v -p codesigning | awk -F'"' '/Developer ID Application/ {print $2; exit}')
[ -n "$IDENTITY" ] || { echo "no Developer ID Application certificate in the keychain" >&2; exit 1; }

TTYCAT_SIGN_IDENTITY="$IDENTITY" TTYCAT_SIGN_TIMESTAMP=--timestamp "$HERE/build.sh"

ROOT=$(mktemp -d)
ditto "$APP" "$ROOT/ttycat.app"
ln -s /Applications "$ROOT/Applications"
rm -f "$DMG"
hdiutil create -quiet -volname "ttycat" -srcfolder "$ROOT" -ov -format UDZO "$DMG"
codesign --force --timestamp --sign "$IDENTITY" "$DMG"
rm -rf "$ROOT"
echo "image: $DMG ($(du -h "$DMG" | cut -f1))"

if [ "${NOTARIZE:-yes}" = no ]; then
  echo "not notarized: it won't open on another Mac without a warning"
  exit 0
fi
xcrun notarytool submit "$DMG" --keychain-profile ttycat --wait
xcrun stapler staple "$DMG"
spctl --assess --type open --context context:primary-signature --verbose "$DMG"
echo "ready: $DMG"
