#!/usr/bin/env python3
"""Signs the app's disk image for release, as the release workflow in ttycat-pro does:

  release_app.py DMG VERSION OUT.json [--min-macos 14.0]

TTYCAT_APP_KEY is the environment's app update key: the secret tools/release_key.py printed. It
signs twice. The disk image itself, for Sparkle (sparkle:edSignature: Ed25519 over its bytes, checked
against SUPublicEDKey in the app it replaces). And OUT.json, the release the update server takes
(kind ttycat-app), whose body holds that signature and what Sparkle's feed needs. The server only
takes an app release signed by an app update key, and never firmware or a core signed by one.
"""
import argparse
import base64
import hashlib
import json
import os
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parent / "daemon"))
sys.path.insert(0, str(HERE))
import app_build  # noqa: E402
import ed25519  # noqa: E402
import release  # noqa: E402

KIND = "ttycat-app"


def seal_app(dmg: Path, version: str, secret: bytes, min_macos: str = "14.0") -> dict:
    _, build, _ = app_build.build_number(version)
    data = Path(dmg).read_bytes()
    body = {"kind": KIND, "version": version, "build": build, "min_macos": min_macos, "file": Path(dmg).name,
            "size": len(data), "sha256": hashlib.sha256(data).hexdigest(),
            "ed_signature": base64.b64encode(ed25519.sign(secret, data)).decode()}
    return release.seal(body, secret)


def main() -> int:
    p = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    p.add_argument("dmg")
    p.add_argument("version", help="X.Y.Z or X.Y.Z-dev.N")
    p.add_argument("out")
    p.add_argument("--min-macos", default="14.0", help="LSMinimumSystemVersion, as app/build.sh sets it")
    a = p.parse_args()
    raw = os.environ.get("TTYCAT_APP_KEY", "")
    try:
        secret = base64.b64decode(raw, validate=True)
    except ValueError:
        secret = b""
    if len(secret) != 32:
        sys.exit("TTYCAT_APP_KEY isn't set to an app update key")
    try:
        sealed = seal_app(Path(a.dmg), a.version, secret, a.min_macos)
    except (OSError, ValueError) as e:
        sys.exit(f"release_app.py: {e}")
    Path(a.out).write_text(json.dumps(sealed, indent=1) + "\n")
    print(f"{a.out}: {a.version}, signed by app update key {sealed['key']}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
