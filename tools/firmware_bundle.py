#!/usr/bin/env python3
"""Packs a built firmware into a folder the Mac app can carry: firmware_bundle.py BUILD_DIR OUT_DIR

The version comes out of the binary itself, the string the board sends when it starts, so the
app can't be told a version that isn't what's really in the image.
"""
import hashlib
import json
import re
import shutil
import sys
from pathlib import Path

build, out = Path(sys.argv[1]), Path(sys.argv[2])
args = json.loads((build / "flasher_args.json").read_text())
app = build / "ttycat.bin"
found = re.search(rb'\{"t":"hello","fw":"([^"\\]+)","b":"([^"\\]+)","p":\d+\}', app.read_bytes())
if not found:
    sys.exit(f"no version in {app}: it may be from an older source, so build the firmware again")

out.mkdir(parents=True, exist_ok=True)
files = []
for offset, name in sorted(args["flash_files"].items(), key=lambda kv: int(kv[0], 16)):
    source = build / name
    shutil.copyfile(source, out / source.name)
    data = source.read_bytes()
    files.append({"offset": offset, "path": source.name, "size": len(data), "sha256": hashlib.sha256(data).hexdigest()})
(out / "manifest.json").write_text(json.dumps({
    "version": found.group(1).decode(),
    "chip": args["extra_esptool_args"]["chip"],
    "board": found.group(2).decode(),
    "flash": args["write_flash_args"],
    "files": files,
}, indent=1))
print(f"firmware {found.group(1).decode()}: {out}")
