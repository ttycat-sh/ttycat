#!/usr/bin/env python3
"""Packs a built firmware into a folder the Mac app can carry: firmware_bundle.py BUILD_DIR OUT_DIR

The version comes out of the binary itself, the string the board sends when it starts, so the
app can't be told a version that isn't what's really in the image. See make_image in daemon/flasher.py.
"""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "daemon"))
from flasher import make_image  # noqa: E402

if len(sys.argv) != 3:
    sys.exit("usage: firmware_bundle.py BUILD_DIR OUT_DIR, such as firmware/build-NAME out")
try:
    version = make_image(Path(sys.argv[1]), Path(sys.argv[2]))
except ValueError as e:
    sys.exit(str(e))
print(f"firmware {version}: {sys.argv[2]}")
