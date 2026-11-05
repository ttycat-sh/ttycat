#!/usr/bin/env python3
"""See the board's screens on this Mac, with no board and no ESP-IDF. Needs only `cc` (the command line tools).

Compiles the real firmware UI, runs it with sample agents and saves the exact frame as a PNG.

  preview.py out.png                                the home screen's agents at work
  preview.py out.png --scene asks --goto queue      a sample scene, on a named screen
  preview.py out.png --goto pet --tap 40,300 --wait 500
  preview.py out.png --goto pet --then one          a prompt arrives while you're looking at it
  preview.py out.png --scale 1                      actual size (default 2x, for looking at)

Scenes: quiet, busy, one, asks, lots (as many as the board can hold, all waiting).
Screens: queue, overview, tab:N, ask:ID, detail:ID, pet, game:bot, and any you add to handle_goto in ui.c.
"""
import argparse, json, struct, subprocess, sys, tempfile, zlib
from pathlib import Path

HERE = Path(__file__).resolve().parent
FW = HERE.parent.parent / "firmware" / "main"
REPLACED = {"main.c", "board.c", "link.c", "sound.c"}  # harness.c stands in for these
W, H = 240, 320
NOW = 1793000000
BLOCKED, ERROR, DONE, WORKING, IDLE = 0, 1, 2, 3, 4
APPROVE = 1


def s(id, project, state, detail="", agent="CC", name="Claude", age=60, tool="", verb="", body="", rev="", ask=0, note=""):
    return dict(id=id, agent=agent, name=name, project=project, state=state, detail=detail, age=age, tool=tool, verb=verb, body=body, rev=rev, ask=ask, note=note)


def prompt(id, project, command, rev, age=12):
    return s(id, project, BLOCKED, command, tool="BASH", verb="wants to run", body=command, rev=rev, ask=APPROVE, age=age)


SCENES = {
    "quiet": [s("a", "recipe-box", IDLE, "waiting for prompt", age=840)],
    "busy": [s("a", "recipe-box", WORKING, "Edit: index.html", age=70), s("b", "riff-9", WORKING, "write: sequencer.c", agent="PI", name="Pi", age=130),
             s("c", "band-site", IDLE, "waiting for prompt", age=840)],
    "one": [prompt("a", "recipe-box", "npm install sharp", "r1")],
    "asks": [prompt("a", "recipe-box", "npm install sharp", "r1"), prompt("b", "band-site", "npx wrangler deploy", "r2", 40),
             s("c", "riff-9", WORKING, "write: sequencer.c", agent="PI", name="Pi", age=130)],
    "lots": [prompt(f"a{i}", f"project-{i}", "npm test", f"r{i}", 30) for i in range(23)] + [s("e", "band-site", ERROR, "build failed", age=90)],
}
Q = json.dumps


def send(scene):
    c = [f"m_reset({NOW}LL);"]
    for x in SCENES[scene]:
        c.append("m_add(" + ",".join(Q(x[k]) for k in ("id", "agent", "name")) + ',"",' + ",".join(Q(x[k]) for k in ("project", "detail", "tool", "verb", "body"))
                 + ',"",' + Q(x["note"]) + "," + Q(x["rev"]) + f',0,0,{x["age"]},{x["state"]},{x["ask"]});')
    return c + ["m_pet(214,5,60,70,60,80,0,0,0,0,12,30,14,0,-1);", "send_model();"]


def script(scene, goto, taps, then, wait):
    c = ["void m_reset(long long);void m_add(const char*,const char*,const char*,const char*,const char*,const char*,const char*,const char*,const char*,const char*,const char*,const char*,int,int,int,int,int);"
         "void m_pet(int,int,int,int,int,int,int,int,int,int,int,int,int,int,int);void send_model(void);void run(int);void go_to(const char*);void touch(int,int);void lift(void);void snap(const char*);",
         "void script(void){", *send(scene), "run(3000);"]
    if goto:
        c += [f"go_to({Q(goto)});", "run(300);"]
    for x, y in taps:
        c += [f"touch({x},{y});", "run(100);", "lift();", "run(300);"]
    if then:
        c += [*send(then), "run(1200);"]
    c += [f"run({wait});", 'snap("frame");', "}"]
    return "\n".join(c)


def png(path, raw, scale):
    rows = bytearray()
    for y in range(H):
        row = bytearray()
        for x in range(W):
            lo, hi = raw[(y * W + x) * 2], raw[(y * W + x) * 2 + 1]
            v = (lo << 8) | hi  # the framebuffer is byte-swapped for the panel
            r, g, b = (v >> 11) << 3, ((v >> 5) & 63) << 2, (v & 31) << 3
            row += bytes((r | r >> 5, g | g >> 6, b | b >> 5)) * scale
        rows += (b"\0" + bytes(row)) * scale

    def chunk(t, d):
        return struct.pack(">I", len(d)) + t + d + struct.pack(">I", zlib.crc32(t + d))
    Path(path).write_bytes(b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", W * scale, H * scale, 8, 2, 0, 0, 0))
                           + chunk(b"IDAT", zlib.compress(bytes(rows))) + chunk(b"IEND", b""))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("out")
    ap.add_argument("--scene", default="busy", choices=SCENES)
    ap.add_argument("--goto")
    ap.add_argument("--tap", action="append", default=[])
    ap.add_argument("--then", choices=SCENES, help="change to this scene after the taps, as if it had just happened")
    ap.add_argument("--wait", type=int, default=100)
    ap.add_argument("--scale", type=int, default=2)
    a = ap.parse_args()
    taps = [tuple(int(n) for n in t.split(",")) for t in a.tap]
    sources = [str(f) for f in sorted(FW.glob("*.c")) if f.name not in REPLACED]
    with tempfile.TemporaryDirectory() as d:
        d = Path(d)
        (d / "script.c").write_text(script(a.scene, a.goto, taps, a.then, a.wait))
        built = subprocess.run(["cc", "-O1", "-w", "-I", str(HERE / "stubs"), "-I", str(FW), *sources, str(HERE / "harness.c"), str(d / "script.c"), "-o", str(d / "fw")],
                               capture_output=True, text=True)
        if built.returncode:
            sys.exit(built.stderr)
        subprocess.run([str(d / "fw"), str(d)], check=True)
        png(a.out, (d / "frame.raw").read_bytes(), a.scale)
    print(a.out)


main()
