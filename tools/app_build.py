#!/usr/bin/env python3
"""What app/build.sh puts into the app's daemon folder, and the app's version for Info.plist:

  app_build.py DAEMON_DIR [VERSION]     prints "SHORT BUILD"

With a VERSION, from a release's tag, it's a release: X.Y.Z is prod, X.Y.Z-dev.N is dev.
  build.json          the daemon then ignores TTYCAT_TRUST_KEY and TTYCAT_UPDATES_URL (daemon/build_info.py)
  release_keys.json   prod's keys; a dev build trusts dev's too (daemon/release_keys_dev.json)
BUILD is what Sparkle compares: it always grows, and a dev build counts below the release it leads to.
Without a VERSION it's a developer's build: 0.0.0, build 0, no build.json, prod's keys.
"""
import json
import re
import sys
from pathlib import Path

DAEMON = Path(__file__).resolve().parents[1] / "daemon"
VERSION = re.compile(r"([0-9]{1,3})\.([0-9]{1,3})\.([0-9]{1,3})(?:-dev\.([0-9]{1,3}))?")
UPDATES = {"prod": "https://api.ttycat.sh/v1/updates", "dev": "https://api.dev.ttycat.sh/v1/updates"}
RELEASED = 999  # the dev builds of X.Y.Z are 1 to 998, and X.Y.Z itself is above them all


def build_number(version: str) -> tuple[str, int, str]:
    """X.Y.Z or X.Y.Z-dev.N: the short version, the build number, and the environment. Raises ValueError."""
    found = VERSION.fullmatch(version)
    if not found:
        raise ValueError(f"a version is X.Y.Z or X.Y.Z-dev.N, not {version!r}")
    x, y, z = (int(found.group(i)) for i in (1, 2, 3))
    dev = found.group(4)
    if dev is not None and not 1 <= int(dev) < RELEASED:
        raise ValueError(f"dev builds are numbered 1 to {RELEASED - 1}, not {dev}")
    n = int(dev) if dev is not None else RELEASED
    return f"{x}.{y}.{z}", ((x * 1000 + y) * 1000 + z) * 1000 + n, "dev" if dev is not None else "prod"


def keys(env: str | None) -> dict:
    trusted = json.loads((DAEMON / "release_keys.json").read_text())
    if env == "dev":
        trusted["keys"] = trusted.get("keys", []) + json.loads((DAEMON / "release_keys_dev.json").read_text())["keys"]
    return trusted


def main(argv: list[str]) -> int:
    if len(argv) not in (2, 3):
        print(__doc__, file=sys.stderr)
        return 2
    out = Path(argv[1])
    if len(argv) == 3:
        try:
            short, build, env = build_number(argv[2])
        except ValueError as e:
            print(f"app_build.py: {e}", file=sys.stderr)
            return 1
        (out / "build.json").write_text(json.dumps(
            {"release": True, "env": env, "version": argv[2], "build": build, "updates": UPDATES[env]}, indent=1) + "\n")
    else:
        short, build, env = "0.0.0", 0, None
        (out / "build.json").unlink(missing_ok=True)
    (out / "release_keys.json").write_text(json.dumps(keys(env), indent=1) + "\n")
    print(short, build)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
