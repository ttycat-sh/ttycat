#!/usr/bin/env python3
"""A signed core release, for custom boards to be built from: release_core.py [OUT_DIR]

Packs firmware/ without its builds into ttycat-core-VERSION.tar.gz, and writes the release beside it,
ttycat-core-VERSION.json, signed with the key in $TTYCAT_SIGNING_KEY (the base64 secret that
tools/release_key.py gives). The same files can ship in the app and on a server: the app checks the
signature wherever they come from. See daemon/release.py.

  --firmware DIR   pack another firmware folder, such as a copy with a test version
"""
import argparse
import base64
import datetime
import gzip
import hashlib
import io
import json
import os
import re
import sys
import tarfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "daemon"))
import ed25519  # noqa: E402
import release  # noqa: E402

SKIP_DIRS = re.compile(r"build.*|managed_components|__pycache__|\..*")
SKIP_FILES = re.compile(r"sdkconfig|sdkconfig\.old|\..*")


def read(path: Path, pattern: str) -> str:
    found = re.search(pattern, path.read_text(), re.M)
    if not found:
        sys.exit(f"nothing like {pattern} in {path}")
    return found.group(1)


def files(folder: Path) -> list[Path]:
    out = []
    for here, dirs, names in os.walk(folder):
        dirs[:] = sorted(d for d in dirs if not SKIP_DIRS.fullmatch(d))
        out += [Path(here) / n for n in sorted(names) if not SKIP_FILES.fullmatch(n)]
    return out


def archive(folder: Path) -> bytes:
    """The same bytes for the same files, wherever and whenever it's made."""
    raw = io.BytesIO()
    with tarfile.open(fileobj=raw, mode="w", format=tarfile.PAX_FORMAT) as tar:
        for path in files(folder):
            data = path.read_bytes()
            info = tarfile.TarInfo("firmware/" + path.relative_to(folder).as_posix())
            info.size, info.mode, info.mtime = len(data), 0o644, 0
            tar.addfile(info, io.BytesIO(data))
    packed = io.BytesIO()
    with gzip.GzipFile(fileobj=packed, mode="wb", mtime=0) as gz:
        gz.write(raw.getvalue())
    return packed.getvalue()


def main():
    p = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    p.add_argument("out", nargs="?", default=str(ROOT / "firmware" / "build-release-core"))
    p.add_argument("--firmware", default=str(ROOT / "firmware"))
    a = p.parse_args()

    secret_b64 = os.environ.get("TTYCAT_SIGNING_KEY", "")
    try:
        secret = base64.b64decode(secret_b64, validate=True)
    except ValueError:
        secret = b""
    if len(secret) != 32:
        sys.exit("TTYCAT_SIGNING_KEY isn't set to a signing key: see tools/release_key.py")

    firmware = Path(a.firmware).resolve()
    version = read(firmware / "main" / "model.h", r'^#define FW_VERSION "([0-9.]+)"')
    api = int(read(firmware / "main" / "board.h", r"^#define BOARD_API ([0-9]+)"))
    idf = read(firmware / "CMakeLists.txt", r'^set\(TTYCAT_IDF "([0-9.]+)"\)')

    data = archive(firmware)
    out = Path(a.out)
    out.mkdir(parents=True, exist_ok=True)
    name = f"ttycat-core-{version}.tar.gz"
    (out / name).write_bytes(data)
    body = {"kind": release.KIND, "version": version, "board_api": api, "idf": idf,
            "date": datetime.date.today().isoformat(),
            "source": {"file": name, "size": len(data), "sha256": hashlib.sha256(data).hexdigest()}}
    sealed = release.seal(body, secret)
    (out / f"ttycat-core-{version}.json").write_text(json.dumps(sealed, indent=1) + "\n")

    kid = sealed["key"]
    print(f"core {version}, board interface {api}, ESP-IDF {idf}: {out} ({len(data) // 1024} KB, key {kid})")
    if kid not in release.trusted_keys():
        print(f"warning: key {kid} isn't in daemon/release_keys.json, so apps won't build this release", file=sys.stderr)
    # The one check that matters, made as an app would make it.
    release.open_release(out / f"ttycat-core-{version}.json", {kid: ed25519.public_key(secret)})


if __name__ == "__main__":
    main()
