#!/bin/sh
# Builds "ttycat.app" without Xcode (the command line tools are enough).
#   app/build.sh            build it into app/build/
#   app/build.sh install    also put it in /Applications and start it
set -eu

HERE=$(cd "$(dirname "$0")" && pwd)
ROOT=$(dirname "$HERE")
APP="$HERE/build/ttycat.app"
VERSION=0.1.0

cd "$HERE"
# An extended build adds its flags and its sources: see Extensions.swift.
swift build -c release ${TTYCAT_SWIFT_ARGS:-}
BIN=$(swift build -c release ${TTYCAT_SWIFT_ARGS:-} --show-bin-path)/TTYCat

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/ttycat"
cp "$ROOT"/tools/fonts/*.ttf "$ROOT"/tools/fonts/OFL-*.txt "$APP/Contents/Resources/"

# The firmware this app can put on the board. It's only ever the last build: firmware/ isn't built here.
# app/release.sh gives it the signed release image instead (TTYCAT_FIRMWARE_IMAGE), as is: the daemon
# writes ttycat's own firmware only from a signed image.
FIRMWARE=${TTYCAT_FIRMWARE_BUILD:-$ROOT/firmware/build}
if [ -n "${TTYCAT_FIRMWARE_IMAGE:-}" ]; then
  ditto "$TTYCAT_FIRMWARE_IMAGE" "$APP/Contents/Resources/firmware"
elif [ -f "$FIRMWARE/flasher_args.json" ]; then
  # A firmware build it can't use mustn't stop here: an app with no Info.plist crashes when it's opened.
  # It goes without, as with no build at all, and app/release.sh won't release one like that.
  python3 "$ROOT/tools/firmware_bundle.py" "$FIRMWARE" "$APP/Contents/Resources/firmware" \
    || echo "warning: that firmware build can't be used; this app can't update the board" >&2
  if python3 -c 'import json, re, sys; sys.exit(not re.fullmatch(r"[0-9.]+", json.load(open(sys.argv[1]))["version"]))' \
      "$APP/Contents/Resources/firmware/manifest.json" 2>/dev/null; then
    echo "warning: that's a release build, but not signed, so this app won't write it: see tools/release_firmware.sh" >&2
  fi
  if [ -n "$(find "$ROOT/firmware/main" "$ROOT/firmware/boards" -newer "$FIRMWARE/ttycat.bin" -print -quit)" ]; then
    echo "warning: firmware has changes that aren't built; the app carries the older build" >&2
  fi
else
  echo "warning: no firmware build found; this app can't update the board" >&2
fi

# The signed core release it builds for boards of people's own (tools/release_core.py), if there is one.
# The daemon checks its signature before building it, whatever's here.
CORE=${TTYCAT_CORE_RELEASE:-$ROOT/firmware/build-release-core}
if ls "$CORE"/ttycat-core-*.json >/dev/null 2>&1; then
  mkdir -p "$APP/Contents/Resources/core"
  cp "$CORE"/ttycat-core-*.json "$CORE"/ttycat-core-*.tar.gz "$APP/Contents/Resources/core/"
else
  echo "warning: no core release found; this app can't update boards of people's own" >&2
fi

# The daemon, and the Python to run it: the app needs nothing else on the Mac. Without app/vendor.sh
# it still builds, and uses the system's Python, for working on it. A release needs it: see release.sh.
mkdir -p "$APP/Contents/Resources/daemon"
cp "$ROOT"/daemon/*.py "$ROOT/daemon/agent_rules.json" "$ROOT/daemon/agent_rules.LICENSE" "$APP/Contents/Resources/daemon/"
cp "$ROOT/LICENSE" "$ROOT/NOTICE" "$ROOT/THIRD_PARTY.md" "$APP/Contents/Resources/"
# Anything an extended build adds to the app, such as a daemon plugin: see daemon/plugins.py.
if [ -n "${TTYCAT_EXTRA_RESOURCES:-}" ]; then
  ditto "$TTYCAT_EXTRA_RESOURCES" "$APP/Contents/Resources"
fi
if [ -d "$HERE/.vendor/python" ]; then
  ditto "$HERE/.vendor/python" "$APP/Contents/Resources/python"
  find "$APP/Contents/Resources" -name '*.py' -not -path "*/Resources/python/*" -exec dirname {} \; | sort -u | while read -r folder; do
    "$APP/Contents/Resources/python/bin/python3" -E -s -m compileall -q --invalidation-mode unchecked-hash "$folder"
  done
else
  echo "warning: no bundled Python (run app/vendor.sh): this build uses the system's" >&2
fi

cat > "$APP/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>ttycat</string>
  <key>CFBundleDisplayName</key><string>ttycat</string>
  <key>CFBundleIdentifier</key><string>sh.ttycat.app</string>
  <key>CFBundleExecutable</key><string>ttycat</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>$VERSION</string>
  <key>CFBundleVersion</key><string>$VERSION</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSUIElement</key><true/>
  <key>LSMultipleInstancesProhibited</key><true/>
  <key>TTYCatBuilt</key><real>$(date +%s)</real>
</dict>
</plist>
EOF

ICONSET="$HERE/build/AppIcon.iconset"
rm -rf "$ICONSET"
"$APP/Contents/MacOS/ttycat" --iconset "$ICONSET"
iconutil -c icns -o "$APP/Contents/Resources/AppIcon.icns" "$ICONSET"

# Your Apple Development certificate if there is one; otherwise signed for this Mac only.
# release.sh passes a Developer ID instead. Hardened either way, so a test build behaves like a release.
IDENTITY=${TTYCAT_SIGN_IDENTITY:-$(security find-identity -v -p codesigning | awk -F'"' '/Apple Development/ {print $2; exit}')}
STAMP=${TTYCAT_SIGN_TIMESTAMP:---timestamp=none}
# Everything that runs is signed on its own, from the inside out.
find "$APP/Contents/Resources" -type f | while read -r file; do
  case "$(file -b "$file")" in
    *Mach-O*) codesign --force --options runtime "$STAMP" --sign "${IDENTITY:--}" "$file" ;;
  esac
done
codesign --force --options runtime "$STAMP" --sign "${IDENTITY:--}" "$APP"
codesign --verify --strict "$APP"
echo "built: $APP (signed: ${IDENTITY:-ad hoc}, $(du -sh "$APP" | cut -f1))"

if [ "${1:-}" = install ]; then
  DEST="/Applications/ttycat.app"
  if pgrep -x ttycat >/dev/null; then
    pkill -TERM -x ttycat
    while pgrep -x ttycat >/dev/null; do sleep 0.2; done
  fi
  rm -rf "$DEST"
  ditto "$APP" "$DEST"
  open -g "$DEST"  # in the background: installing must not take the focus
  echo "installed: $DEST"
fi
