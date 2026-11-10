#!/usr/bin/env python3
"""Whether a change to the shared code leaves every screen exactly as it was, on every board.

  unchanged.py              this working tree against the last commit
  unchanged.py main         against another commit or branch
  unchanged.py --keep DIR   and save both versions of any frame that differs

Renders every gallery frame (gallery.py) from both: at the official board's size, the narrowest and
biggest sizes the screens are laid out for, a short and a sideways one, a rounded screen, each board in
boards/ with its own size and corners, and Bit's screens with the test art. Then compares them pixel for
pixel. Exits 0 if every frame is the same, 1 if any differs. Needs only `cc` and git, as gallery.py does.

A change for one board's sake must leave this saying "unchanged": see the ttycat-new-board skill.
"""
import argparse, shutil, struct, subprocess, sys, tempfile, zlib
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
CASES = {
    "official": ["--size", "240x320"],
    "narrow": ["--size", "170x320"],
    "short": ["--size", "240x240"],
    "sideways": ["--size", "320x240"],
    "biggest": ["--size", "480x480"],
    "rounded": ["--size", "240x240", "--corner", "48"],
    "art": ["--size", "240x320", "--art", "tools/preview/art/snow.json"],
}


def pixels(path):
    """A PNG as gallery.py writes it, as its size and its rows: enough to compare two of them."""
    data, at, size, idat = path.read_bytes(), 8, None, b""
    while at < len(data):
        n = struct.unpack(">I", data[at:at + 4])[0]
        kind, body = data[at + 4:at + 8], data[at + 8:at + 8 + n]
        if kind == b"IHDR":
            size = body[:8]
        elif kind == b"IDAT":
            idat += body
        at += 12 + n
    return size, zlib.decompress(idat)


def render(tree, case, args, out):
    """Every frame for one case, from the copy of the code in `tree`, into out/CASE."""
    frames = out / case
    run = subprocess.run([sys.executable, "tools/preview/gallery.py", str(out / f"{case}.png"), "--frames", str(frames), *args],
                         cwd=tree, capture_output=True, text=True)
    if run.returncode:
        sys.exit(f"{case}: gallery.py failed in {tree}:\n{run.stderr}")
    return {p.name: p for p in frames.glob("*.png")}


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("ref", nargs="?", default="HEAD", help="the commit to compare with (default: the last one)")
    ap.add_argument("--keep", help="save both versions of each frame that differs here")
    a = ap.parse_args()
    boards = sorted(p.name for p in (ROOT / "boards").iterdir() if (p / "board.c").exists() and p.name != "template")
    cases = dict(CASES, **{f"board-{b}": ["--board", b] for b in boards})

    with tempfile.TemporaryDirectory() as tmp:
        tmp = Path(tmp)
        before = tmp / "before"
        before.mkdir()
        archive = subprocess.run(["git", "-C", str(ROOT), "archive", a.ref, "main", "tools/preview", "boards"], capture_output=True)
        if archive.returncode:
            sys.exit(f"git archive {a.ref}: {archive.stderr.decode().strip()}")
        subprocess.run(["tar", "-x", "-C", str(before)], input=archive.stdout, check=True)

        jobs = []
        with ThreadPoolExecutor() as pool:
            for case, args in cases.items():
                if case.startswith("board-") and not (before / "boards" / case[6:] / "board.c").exists():
                    print(f"{case}: new since {a.ref}, nothing to compare")
                    continue
                jobs.append((case, pool.submit(render, before, case, args, tmp / "out-before"),
                             pool.submit(render, ROOT, case, args, tmp / "out-after")))
            results = [(case, old.result(), new.result()) for case, old, new in jobs]

        changed = []
        for case, old, new in results:
            for name in sorted(old.keys() | new.keys()):
                if name not in old or name not in new:
                    changed.append((case, name, "only " + ("after" if name in new else "before")))
                elif pixels(old[name]) != pixels(new[name]):
                    changed.append((case, name, "differs"))
                    if a.keep:
                        for side, frames in (("before", old), ("after", new)):
                            dest = Path(a.keep) / case / side
                            dest.mkdir(parents=True, exist_ok=True)
                            shutil.copy(frames[name], dest / name)
        frames = sum(len(old) for _, old, _ in results)
        if not changed:
            print(f"unchanged: all {frames} frames in {len(results)} sizes and boards match {a.ref}")
            return
        for case, name, how in changed:
            print(f"{case}: {name[:-4]} {how}")
        print(f"{len(changed)} of {frames} frames changed" + (f": both versions are in {a.keep}" if a.keep else ""))
        sys.exit(1)


main()
