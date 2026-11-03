#!/bin/sh
# Prepares what the app carries so it needs nothing installed: Python, and esptool for the board.
# Downloads from GitHub and PyPI, pinned by version and, for Python, by hash. The result is cached
# in .vendor/, and app/build.sh copies it into the app.
set -eu

HERE=$(cd "$(dirname "$0")" && pwd)
OUT="$HERE/.vendor/python"
STAMP="$HERE/.vendor/stamp"

PY_TAG=20261026
PY_VERSION=3.13.18
PY_FILE="cpython-$PY_VERSION+$PY_TAG-aarch64-apple-darwin-install_only_stripped.tar.gz"
PY_SHA=8392b6ea51d94391befb2c31ebe75463f045d0b69dfcf5e1bb3234e1f5fa3405
PY_URL="https://github.com/astral-sh/python-build-standalone/releases/download/$PY_TAG/$(printf '%s' "$PY_FILE" | sed 's/+/%2B/')"
PACKAGES="esptool==4.12.0 pyserial==3.5 intelhex==2.3.0"
WANT="$PY_FILE $PACKAGES"

if [ -f "$STAMP" ] && [ "$(cat "$STAMP")" = "$WANT" ]; then
  echo "vendor: ready"
  exit 0
fi

mkdir -p "$HERE/.vendor"
TAR="$HERE/.vendor/$PY_FILE"
[ -f "$TAR" ] || curl -fsSL --retry 3 -o "$TAR" "$PY_URL"
if [ "$(shasum -a 256 "$TAR" | cut -d' ' -f1)" != "$PY_SHA" ]; then
  rm -f "$TAR"
  echo "vendor: $PY_FILE doesn't match its hash" >&2
  exit 1
fi

rm -rf "$OUT" "$HERE/.vendor/unpack"
mkdir -p "$HERE/.vendor/unpack"
tar -xzf "$TAR" -C "$HERE/.vendor/unpack"
mv "$HERE/.vendor/unpack/python" "$OUT"
rm -rf "$HERE/.vendor/unpack"

PY="$OUT/bin/python3"
LIB="$OUT/lib/python3.13"
# Only what the flasher uses: its secure-boot and eFuse tools, and their dependencies, aren't needed.
"$PY" -m pip install --quiet --no-deps --no-compile --target "$LIB/site-packages" $PACKAGES

# What a daemon that only uses the standard library will never load.
rm -rf "$OUT/include" "$OUT/share" "$OUT/lib/pkgconfig" "$OUT/lib/itcl"* "$OUT/lib/tcl"* "$OUT/lib/tk"* "$OUT/lib/thread"* \
  "$OUT/lib/libtcl"* "$OUT/lib/libtk"* "$LIB/test" "$LIB/idlelib" "$LIB/tkinter" "$LIB/turtledemo" "$LIB/ensurepip" \
  "$LIB/lib2to3" "$LIB/pydoc_data" "$LIB/site-packages/pip" "$LIB/site-packages/pip-"* "$LIB/config-3.13-darwin"
rm -f "$LIB/lib-dynload/_tkinter"* "$OUT/bin/pip"* "$OUT/bin/idle"* "$OUT/bin/pydoc"* "$OUT/bin/2to3"* \
  "$OUT/bin/python3-config" "$OUT/bin/python3.13-config"
rm -rf "$LIB/site-packages/espefuse" "$LIB/site-packages/espsecure" "$LIB/site-packages/espefuse.py" \
  "$LIB/site-packages/espsecure.py" "$LIB/site-packages/esp_rfc2217_server"* "$LIB/site-packages/bin"
find "$OUT" -name '__pycache__' -type d -prune -exec rm -rf {} +

# Compiled ahead: the app's folder is signed, so nothing can be written there later. "unchecked" so
# that copying the app, which changes file times, can't make them count as stale.
"$PY" -E -s -m compileall -q --invalidation-mode unchecked-hash "$LIB" >/dev/null 2>&1 || true

printf '%s' "$WANT" > "$STAMP"
echo "vendor: python $PY_VERSION, $PACKAGES: $(du -sh "$OUT" | cut -f1)"
