#!/usr/bin/env python3
"""Every screen at one size, on one sheet: for checking that the layouts fit a board's screen.

  gallery.py out.png                 240x320, the official board
  gallery.py out.png --size 170x320  any size the screens are laid out for (see SCR_MIN_W in gfx.h)
  gallery.py out.png --size 480x480 --frames DIR    also each screen as its own PNG
  gallery.py out.png --size 240x240 --corner 48     a screen with rounded corners, masked as on the glass
  gallery.py out.png --board NAME|FOLDER            the size and shape a board's board.c gives, e.g.
                                                    --board waveshare-esp32-s3-touch-amoled-2-16
  gallery.py out.png --board NAME --cut             and in red, anything drawn where the glass hides it
  gallery.py out.png --art FILE                     and Bit's screens with that art (docs/PROTOCOL.md, "Art"),
                                                    e.g. tools/preview/art/snow.json

Compiles the real firmware UI with the preview harness, as preview.py does. Needs only `cc`.
"""
import argparse, json, re, struct, subprocess, sys, tempfile, zlib
from pathlib import Path

HERE = Path(__file__).resolve().parent
FW = HERE.parent.parent / "main"
REPLACED = {"main.c", "board.c", "link.c", "sound.c"}
NOW = 1793000000
BLOCKED, ERROR, DONE, WORKING, IDLE = 0, 1, 2, 3, 4
APPROVE, TERMINAL, CHOICE = 1, 2, 3
Q = json.dumps


def s(id, project, state, detail="", agent="CC", name="Claude", age=60, tool="", verb="", body="", file="", note="", rev="",
      add=0, dele=0, ask=0, host="", questions=()):
    return dict(id=id, agent=agent, name=name, host=host, project=project, detail=detail, tool=tool, verb=verb, body=body,
                file=file, note=note, rev=rev, add=add, dele=dele, age=age, state=state, ask=ask, questions=questions)


BASH = s("a", "recipe-box", BLOCKED, "npx wrangler pages deploy", tool="BASH", verb="wants to run", ask=APPROVE, rev="r1", age=12,
         body="npm run build && npx wrangler pages deploy dist")
LONG = dict(BASH, id="l", rev="r9", body="rm -rf build dist .cache && npm ci --prefer-offline && npm run build -- --mode production"
            " && npx wrangler pages deploy dist --branch main && echo finished")
EDIT = s("e", "bike-map", BLOCKED, "style.css +2 -1", tool="EDIT", verb="wants to change", ask=APPROVE, rev="r2", age=40,
         file="src/styles/style.css", add=2, dele=1, body="- color: grey;\n+ color: tomato;\n+ font-size: 18px;")
TERM = s("t", "zine-maker", BLOCKED, "npm install sharp", agent="CX", name="Codex", tool="SHELL", verb="wants to run", ask=TERMINAL,
         rev="r3", body="npm install sharp --save-dev", note="Codex can only be answered in its terminal")
QUESTION = s("q", "band-site", BLOCKED, "Where should the recipes be saved?", tool="ASK", verb="is asking", ask=CHOICE, rev="r4", age=4,
             questions=[("Where should the recipes be saved? It can be moved later, but that takes a while.", False,
                         [("Supabase", "Free to start, works anywhere"), ("One file", "Simple, nothing to set up"),
                          ("Browser", "Only on the device you use")])])
WORK = [s("w1", "band-site", WORKING, "Edit: index.html", age=8), s("w2", "riff-9", WORKING, "write: sequencer.c", agent="PI", name="Pi", age=130),
        s("w3", "portfolio", IDLE, "waiting for prompt", age=840), s("w4", "game-jam", DONE, "Resized 214 images", agent="CX", name="Codex"),
        s("w5", "plant-watcher", ERROR, "npm run build: exit 1", agent="CX", name="Codex", age=180),
        s("w6", "riff-9", WORKING, "Edit: voice.c", host="studio", age=90)]
MANY = [s(f"m{i}", f"project-{i}", [WORKING, IDLE, DONE][i % 3], "Edit: index.html", age=60 * i) for i in range(20)]
HIST = [("w1", "8s", 0, "Edit: index.html"), ("w1", "1m", 2, "Read 4 files and found the menu that breaks on small phones"),
        ("w1", "3m", 1, "npm test: 2 failing"), ("w1", "4m", 0, "Bash: npm test"), ("w1", "6m", 0, "Read: package.json")]


def model(sessions, grown=60, asleep=0, birthday=0, age=30, hist=(), no_approve=0, ev=0, evk=-1):
    c = [f"m_reset({NOW}LL);", f"m_no_approve({no_approve});"]
    for x in sessions:
        c.append("m_add(" + ",".join(Q(x[k]) for k in ("id", "agent", "name", "host", "project", "detail", "tool", "verb", "body", "file", "note", "rev"))
                 + f',{x["add"]},{x["dele"]},{x["age"]},{x["state"]},{x["ask"]});')
        for text, multi, options in x["questions"]:
            c.append(f"m_q({Q(text)},{int(multi)});")
            c += [f"m_opt({Q(label)},{Q(desc)});" for label, desc in options]
    c += [f"m_hist({Q(i)},{Q(a)},{t},{Q(text)});" for i, a, t, text in hist]
    return c + [f"m_pet(214,5,{grown},{asleep},{birthday},{age},{ev},{evk});", "send_model();"]


def steps():
    """(name, C) for each frame, in order. They run one after another, as on a board."""
    yield "boot", ["run(200);"]
    yield "queue", [*model(WORK, hist=HIST), "run(3000);", 'go_to("queue");', "run(300);"]
    yield "queue-cx", ['go_to("tab:2");', "run(300);"]
    yield "queue-many", [*model(MANY), 'go_to("tab:0");', "run(1200);"]
    yield "overview", [*model(WORK), 'go_to("overview");', "run(1200);"]
    yield "overview-asks", [*model([BASH, EDIT, TERM, *WORK]), "run(1200);"]
    yield "overview-clear", [*model(WORK[:3], asleep=1), "run(1200);"]
    yield "home-lv1", [*model(WORK[2:3], grown=0), 'go_to("pet");', "run(3000);"]
    yield "home-lv8", [*model(WORK[2:3], grown=200, age=120), "run(1500);"]
    yield "home-working", [*model(WORK[:3]), "run(6000);"]
    yield "home-asleep", [*model(WORK[2:3], asleep=1), "run(2000);"]
    yield "home-level-up", [*model(WORK[2:3], grown=27, birthday=1), 'go_to("pet:level");', "run(600);"]
    yield "home-toast", ['ack(0,"no reply from the Mac");', "run(300);"]
    yield "home-after-toast", ["run(3000);"]  # gone again, so it isn't mistaken for part of the next screens
    yield "detail", [*model(WORK, hist=HIST), 'go_to("detail:w1");', "run(600);"]
    yield "detail-remote", ['go_to("detail:w6");', "run(600);"]
    yield "ask", [*model([BASH, *WORK]), 'go_to("ask:a");', "run(800);"]
    yield "ask-on-mac", [*model([BASH, *WORK], no_approve=1), "run(1200);"]
    yield "ask-clipped", [*model([LONG, *WORK]), 'go_to("ask:l");', "run(800);"]
    yield "ask-full", ['go_to("full");', "run(300);"]
    yield "ask-diff", [*model([EDIT, *WORK]), 'go_to("ask:e");', "run(800);"]
    yield "ask-terminal", [*model([TERM, *WORK]), 'go_to("ask:t");', "run(800);"]
    yield "queue-alert", [*model(WORK), 'go_to("tab:2");', "run(1200);", *model([dict(BASH, id="b2", rev="r7"), *WORK]), "run(600);"]
    yield "choice", [*model([QUESTION, *WORK]), 'go_to("ask:q");', "run(800);"]
    yield "keys", ['go_to("keys");', "run(300);"]
    yield "lost", [*model([BASH, *WORK]), 'go_to("ask:a");', "run(800);", "hush(1);", "run(6000);"]


def art_calls(art):
    """The art message, built as link.c builds it, through the same checks in art.c."""
    if not isinstance(art, dict) or art.get("t") != "art":
        sys.exit('art: not an art message: it needs "t": "art"')
    if len(json.dumps(art, separators=(",", ":"))) > 8192:
        sys.exit("art: over the 8 KB a board takes")
    c = [f"art_begin(&A,{Q(art.get('id', ''))})", f"{int(art.get('f', 0))}>=1", f"{int(art.get('f', 0))}<=ART_FORMAT"]
    for i, colour in enumerate(art.get("pal", []), 1):
        if not re.fullmatch(r"#[0-9a-fA-F]{6}", str(colour)):
            sys.exit(f"art: {colour!r} isn't a #rrggbb colour")
        c.append(f"art_color(&A,{i},0x{colour[1:]})")
    for sp in art.get("sp", []):
        rows = ",".join(Q(r) for r in sp.get("px", []))
        c.append(f"art_sprite(&A,{int(sp.get('w', 0))},{int(sp.get('h', 0))},{int(sp.get('ms', 0))},"
                 f"(const char*const[]){{{rows or '0'}}},{len(sp.get('px', []))})")
    modes = {"nap": 1, "work": 2, "walk": 4, "hop": 8}
    for w in art.get("wear", []):
        hide = 0
        for m in w.get("not", []):
            if m not in modes:
                sys.exit(f"art: Bit has no mode called {m!r}")
            hide |= modes[m]
        c.append(f"art_wear(&A,{int(w.get('sp', -1))},{Q(w.get('on', ''))},{int(w.get('x', 0))},{int(w.get('y', 0))},{hide})")
    for p in art.get("set", []):
        c.append(f"art_piece(&A,{int(p.get('sp', -1))},{Q(p.get('on', ''))},{int(p.get('x', 0))},{int(p.get('y', 0))})")
    if "fall" in art:
        f = art["fall"]
        c.append(f"art_fall(&A,{int(f.get('sp', -1))},{int(f.get('n', 0))},{int(f.get('vy', 0))},{int(f.get('vx', 0))},{int(f.get('sway', 0))})")
    if "say" in art:
        c.append(f"art_say(&A,{Q(str(art['say']))})")
    c.append("art_finish(&A)")
    checks = "".join(f'if(!({x})){{fputs("art: not shown, at: "{Q(x[:60])}"\\n",stderr);exit(3);}}' for x in c)
    return [checks, "ui_set_art(&A);", f"m_art({Q(art.get('id', ''))});"]


def art_steps(art):
    """Bit's screens with the art, after all the others."""
    yield "art-say", ["hush(0);", *art_calls(art), *model(WORK[2:3]), "run(1200);", 'go_to("pet");', "run(1500);"]
    yield "art-home", ["run(4000);"]
    yield "art-lv8", [*model(WORK[2:3], grown=200, age=120), "run(1500);"]
    yield "art-working", [*model(WORK[:3]), "run(6000);"]
    yield "art-asleep", [*model(WORK[2:3], asleep=1), "run(2000);"]
    yield "art-birthday", [*model(WORK[2:3], birthday=1), "run(1500);"]


def last_steps():
    """Screens added since: after all the others, so those are drawn at the moments they always were."""
    yield "name", ["hush(0);", *model(WORK), "run(1500);", 'go_to("name:w1");', "run(300);"]  # the keyboard, for a session's name


def script(art=None):
    c = ["#include <stdio.h>\n#include <stdlib.h>\n#include \"ui.h\"\nstatic art_t A;void m_art(const char*);",
         "void m_reset(long long);void m_no_approve(int);void m_add(const char*,const char*,const char*,const char*,const char*,const char*,"
         "const char*,const char*,const char*,const char*,const char*,const char*,int,int,int,int,int);void m_q(const char*,int);"
         "void m_opt(const char*,const char*);void m_hist(const char*,const char*,int,const char*);void m_pet(int,int,int,int,int,int,int,int);"
         "void send_model(void);void run(int);void go_to(const char*);void ack(int,const char*);void hush(int);void snap(const char*);",
         "void script(void){"]
    names = []
    for name, body in [*steps(), *(art_steps(art) if art else []), *last_steps()]:
        c += body + [f"snap({Q(name)});"]
        names.append(name)
    return "\n".join(c + ["}"]), names


def rgb(raw, w, h):
    px = []
    for i in range(w * h):
        v = (raw[i * 2] << 8) | raw[i * 2 + 1]  # the framebuffer is byte-swapped for the panel
        r, g, b = (v >> 11) << 3, ((v >> 5) & 63) << 2, (v & 31) << 3
        px.append((r | r >> 5, g | g >> 6, b | b >> 5))
    return px


def png(path, w, h, pixel):
    rows = bytearray()
    for y in range(h):
        rows += b"\0" + b"".join(bytes(pixel(x, y)) for x in range(w))

    def chunk(t, d):
        return struct.pack(">I", len(d)) + t + d + struct.pack(">I", zlib.crc32(t + d))
    Path(path).write_bytes(b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 2, 0, 0, 0))
                           + chunk(b"IDAT", zlib.compress(bytes(rows))) + chunk(b"IEND", b""))


def board_shape(name):
    """The picture's size and its corners, from the #defines in a board's board.c, as its board_begin works them out."""
    folder = Path(name).expanduser()  # a folder of your own, or the name of one in boards/
    path = (folder if folder.is_dir() else HERE.parent.parent / "boards" / name) / "board.c"
    if not path.exists():
        sys.exit(f"no board called {name}: see the folders in boards/")
    defs = {k: int(v) for k, v in re.findall(r"^#define\s+(\w+)\s+(\d+)\b", path.read_text(), re.M)}
    zoom, inset = defs.get("ZOOM", 1), defs.get("EDGE_INSET", 0)
    w, h = (defs["PANEL_W"] - 2 * inset) // zoom, (defs["PANEL_H"] - 2 * inset) // zoom
    return w, h, max(0, defs.get("CORNER_RADIUS", 0) - inset) // zoom


def seen(x, y, w, h, r):
    """Whether the glass shows the picture's pixel at x, y: its centre is inside the rounded corners. As gfx_corner works it out."""
    cx, cy = x + 0.5, y + 0.5
    dx = r - cx if cx < r else cx - (w - r) if cx > w - r else 0
    dy = r - cy if cy < r else cy - (h - r) if cy > h - r else 0
    return not (dx and dy) or dx * dx + dy * dy <= r * r


def lost_here(f, i, w, h, r):
    """Whether something is lost at hidden pixel i: it isn't just the background, or a box's fill or border,
    carrying on behind the glass, which shows as one of the first eight colours the glass does show
    inward from it, along its row or up or down its column. Black counts only between two runs of the
    same colour, as black lettering on a coloured box does: anywhere else it's the background. A run that
    goes out to the picture's edge is a frame round the whole screen, which gfx_border draws again inside
    the glass, so the black between the two is background too."""
    x0, y0 = i % w, i // w
    if f[i] == (0, 0, 0):
        def near(step):
            for k in range(1, 4):
                x = x0 + k * step
                if 0 <= x < w and f[y0 * w + x] != (0, 0, 0):
                    return x
        outward = -1 if x0 < w // 2 else 1
        out, back = near(outward), near(-outward)
        if out is None or back is None or f[y0 * w + out] != f[y0 * w + back]:
            return False
        x = out
        while 0 <= x < w and f[y0 * w + x] == f[y0 * w + out]:
            x += outward
        if not 0 <= x < w:
            return False
    for dx, dy in ((1 if x0 < w // 2 else -1, 0), (0, 1 if y0 < h // 2 else -1)):
        x, y, shown = x0, y0, []
        while 0 <= x < w and 0 <= y < h and len(shown) < 8:
            if seen(x, y, w, h, r):
                shown.append(f[y * w + x])
            x, y = x + dx, y + dy
        if f[i] in shown:
            return False
    return True


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("out")
    ap.add_argument("--size", default="240x320")
    ap.add_argument("--frames", help="also save each screen here, as NAME.png")
    ap.add_argument("--columns", type=int, default=6)
    ap.add_argument("--corner", type=int, default=0, help="the radius of the glass's rounded corners, in the picture's pixels")
    ap.add_argument("--board", help="the size and corners this board's board.c gives the picture")
    ap.add_argument("--cut", action="store_true", help="show in red anything drawn where the glass hides it")
    ap.add_argument("--art", help="also Bit's screens with this art message, as a JSON file")
    a = ap.parse_args()
    art = None
    if a.art:
        try:
            art = json.loads(Path(a.art).read_text())
        except (OSError, ValueError) as e:
            sys.exit(f"art: {e}")
    w, h = (int(n) for n in a.size.lower().split("x"))
    corner = a.corner
    if a.board:
        w, h, corner = board_shape(a.board)
    sources = [str(f) for f in sorted(FW.glob("*.c")) if f.name not in REPLACED]
    with tempfile.TemporaryDirectory() as d:
        d = Path(d)
        text, names = script(art)
        (d / "script.c").write_text(text)
        built = subprocess.run(["cc", "-O1", "-w", "-I", str(HERE / "stubs"), "-I", str(FW), *sources, str(HERE / "harness.c"), str(d / "script.c"),
                                "-o", str(d / "fw")], capture_output=True, text=True)
        if built.returncode:
            sys.exit(built.stderr)
        if subprocess.run([str(d / "fw"), str(d), str(w), str(h), str(corner)]).returncode:
            sys.exit(1)
        frames = [rgb((d / f"{n}.raw").read_bytes(), w, h) for n in names]
    if corner:  # the glass hides the corners: they're the sheet's grey, as round as the glass
        hidden = [i for i in range(w * h) if not seen(i % w, i // w, w, h, corner)]
        lost = []
        for n, f in zip(names, frames):
            cut, drawn = 0, list(f)
            for i in hidden:
                if lost_here(drawn, i, w, h, corner):
                    cut += 1
                    if a.cut:
                        f[i] = (230, 40, 40)
                        continue
                f[i] = (60, 60, 60)
            if cut:
                lost.append(f"{n} ({cut} px)")
        print("hidden by the corners: " + (", ".join(lost) if lost else "nothing"), file=sys.stderr)
    if a.frames:
        Path(a.frames).mkdir(parents=True, exist_ok=True)
        for n, f in zip(names, frames):
            png(Path(a.frames) / f"{n}.png", w, h, lambda x, y, f=f: f[y * w + x])
    cols, gap = min(a.columns, len(frames)), 8
    rows = (len(frames) + cols - 1) // cols
    sw, sh = cols * (w + gap) + gap, rows * (h + gap) + gap
    grey = (60, 60, 60)

    def sheet(x, y):
        c, r = (x - gap) // (w + gap), (y - gap) // (h + gap)
        fx, fy = x - gap - c * (w + gap), y - gap - r * (h + gap)
        i = r * cols + c
        if x < gap or y < gap or fx >= w or fy >= h or i >= len(frames):
            return grey
        return frames[i][fy * w + fx]
    png(a.out, sw, sh, sheet)
    print(a.out, " ".join(names))


main()
