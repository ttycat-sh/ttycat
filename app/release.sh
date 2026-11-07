#!/bin/sh
# A release: Developer ID signed, in a disk image, notarized by Apple so it opens on any Mac.
#   TTYCAT_VERSION=X.Y.Z (prod) or X.Y.Z-dev.N (dev): required, and normally from the release's tag
#   app/vendor.sh     once, for the bundled Python and esptool
#   the firmware and core it carries, signed for that environment: tools/release_firmware.sh here, or
#     TTYCAT_FIRMWARE_IMAGE and TTYCAT_CORE_RELEASE, as CI gives them
#   notarizing: NOTARY_KEY_FILE, NOTARY_KEY_ID and NOTARY_ISSUER (an App Store Connect API key, as CI
#     has), or else `xcrun notarytool store-credentials ttycat` once on this Mac
#   app/release.sh
# NOTARIZE=no stops before anything is sent to Apple.
set -eu

HERE=$(cd "$(dirname "$0")" && pwd)
CORE_ROOT=$(dirname "$HERE")
APP="$HERE/build/ttycat.app"
VERSION=${TTYCAT_VERSION:-}
echo "$VERSION" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+(-dev\.[0-9]+)?$' \
  || { echo "TTYCAT_VERSION is X.Y.Z or X.Y.Z-dev.N, not '$VERSION': a release has a version" >&2; exit 1; }
DMG="$HERE/build/ttycat-$VERSION.dmg"

[ -d "$HERE/.vendor/python" ] || { echo "run app/vendor.sh first: a release can't rely on the buyer's Python" >&2; exit 1; }
# ttycat's own Apple developer team, and no other, even with other teams' certificates in the keychain.
# Sparkle also refuses an update signed by another team than the app it replaces.
TEAM=${TTYCAT_TEAM_ID:-D4N534TM9Q}
# The one that runs longest, by its fingerprint: a renewed certificate has the same name as the old one.
FOUND=$(python3 "$CORE_ROOT/tools/signing_identity.py" "Developer ID Application" "$TEAM")
IDENTITY=${FOUND%%	*}
NAME=${FOUND#*	}
[ -n "$IDENTITY" ] || { echo "no Developer ID Application certificate for team $TEAM in the keychain" >&2; exit 1; }

# What it carries: given, as from CI, or what tools/release_firmware.sh made here.
if [ -n "${TTYCAT_FIRMWARE_IMAGE:-}" ]; then
  IMAGE=$TTYCAT_FIRMWARE_IMAGE
else
  FIRMWARE="$CORE_ROOT/firmware/build-release"
  IMAGE="$CORE_ROOT/firmware/build-release-image"
  [ -f "$FIRMWARE/ttycat.bin" ] && [ -f "$IMAGE/release.json" ] || { echo "run tools/release_firmware.sh first" >&2; exit 1; }
  [ -z "$(find "$CORE_ROOT/firmware/main" "$CORE_ROOT/firmware/boards" -newer "$FIRMWARE/ttycat.bin" -print -quit)" ] \
    || { echo "the firmware has changed: run tools/release_firmware.sh again" >&2; exit 1; }
fi
CORE_RELEASE=${TTYCAT_CORE_RELEASE:-$CORE_ROOT/firmware/build-release-core}
ls "$CORE_RELEASE"/ttycat-core-*.json >/dev/null 2>&1 || { echo "no signed core release in $CORE_RELEASE" >&2; exit 1; }

TTYCAT_FIRMWARE_IMAGE=$IMAGE TTYCAT_CORE_RELEASE=$CORE_RELEASE TTYCAT_SIGN_IDENTITY="$IDENTITY" TTYCAT_SIGN_NAME="$NAME" \
  TTYCAT_SIGN_TIMESTAMP=--timestamp "$HERE/build.sh"

# Checked as the app will check them: by its own daemon, with the keys and build.json it was built with.
# Sold as ttycat's firmware, so it has to say so: a custom build would never be offered as an update.
"$APP/Contents/Resources/python/bin/python3" -E -s -B - "$APP/Contents/Resources/daemon" "$APP/Contents/Resources" <<'EOF' \
  || { echo "what this app carries doesn't check out with the keys it trusts" >&2; exit 1; }
import glob, re, sys
sys.path.insert(0, sys.argv[1])
import build_info, flasher, release
assert build_info.is_release(), "build.json doesn't say it's a release"
image = flasher.read_image(sys.argv[2] + "/firmware")
assert image["signed"] and re.fullmatch(r"[0-9]+(\.[0-9]+)*", image["version"]), "the firmware isn't a signed release"
cores = glob.glob(sys.argv[2] + "/core/ttycat-core-*.json")
assert cores, "no core release"
for path in cores:
    release.open_release(path)
print("carries firmware", image["version"], "and", len(cores), "core release(s), signed by keys it trusts")
EOF

STAGE=$(mktemp -d)
ditto "$APP" "$STAGE/ttycat.app"
ln -s /Applications "$STAGE/Applications"
rm -f "$DMG"
hdiutil create -quiet -volname "ttycat" -srcfolder "$STAGE" -ov -format UDZO "$DMG"
codesign --force --timestamp --sign "$IDENTITY" "$DMG"
rm -rf "$STAGE"
echo "image: $DMG ($(du -h "$DMG" | cut -f1))"

if [ "${NOTARIZE:-yes}" = no ]; then
  echo "not notarized: it won't open on another Mac without a warning"
  exit 0
fi
if [ -n "${NOTARY_KEY_FILE:-}" ]; then
  xcrun notarytool submit "$DMG" --key "$NOTARY_KEY_FILE" --key-id "$NOTARY_KEY_ID" --issuer "$NOTARY_ISSUER" --wait
else
  xcrun notarytool submit "$DMG" --keychain-profile ttycat --wait
fi
xcrun stapler staple "$DMG"
spctl --assess --type open --context context:primary-signature --verbose "$DMG"
echo "ready: $DMG"
