#!/usr/bin/env -S uv run --quiet --script
# /// script
# requires-python = ">=3.10"
# dependencies = ["pillow>=10"]
# ///
"""Renders the design's four pixel fonts to 1-bit C tables (main/fonts.c).

Each font_t is named after the design's type role, keeps that role's line box
(`box`), and is drawn at the nearest size that lands on the font's pixel grid. At
the design's nominal sizes (Silkscreen 9, VT323 14/16/18, Pixelify 13) 1-bit glyphs
break up on this panel: "m" fills in and "e" reads as "o". `base` is the distance
from the top of a CSS line-height:1 box to the baseline, so UI code can use the
design's y values directly. Only ASCII plus the middle dot (char 127) is included,
as in the design's spec ("1-bit, ASCII only").

Glyphs are either FreeType's mono rendering ("mono") or the outline sampled 16x and
thresholded ("over"), whichever is cleaner for that size.
"""
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parent
OUT = ROOT.parent / "main"
# name, file, drawn px, line box px, weight, method
FONTS = [
    ("sk9", "Silkscreen-Bold.ttf", 8, 9, None, "mono"),
    ("sk11", "Silkscreen-Bold.ttf", 11, 11, None, "mono"),
    ("ps12", "PressStart2P-Regular.ttf", 16, 16, None, "mono"),
    ("ps16", "PressStart2P-Regular.ttf", 16, 16, None, "mono"),
    ("ps24", "PressStart2P-Regular.ttf", 24, 24, None, "mono"),
    ("ps32", "PressStart2P-Regular.ttf", 32, 32, None, "mono"),
    ("ps40", "PressStart2P-Regular.ttf", 40, 40, None, "mono"),
    ("px13", "PixelifySans-wght.ttf", 15, 13, 700, "over"),
    ("px16", "PixelifySans-wght.ttf", 16, 16, 700, "mono"),
    ("vt12", "VT323-Regular.ttf", 12, 12, None, "over"),
    ("vt14", "VT323-Regular.ttf", 15, 14, None, "over"),
    ("vt16", "VT323-Regular.ttf", 15, 16, None, "over"),
    ("vt18", "VT323-Regular.ttf", 20, 18, None, "mono"),
]
# VT323 has 4 columns of ink at 15 px, too few for these: m collapses into n, and
# 4 and 9 look alike. Drawn by hand, bottom row on the baseline.
VT15_GLYPHS = {
    "m": ["####.", "#.#.#", "#.#.#", "#.#.#", "#.#.#", "#.#.#"],
    "w": ["#...#", "#...#", "#.#.#", "#.#.#", "#.#.#", ".#.#."],
    "M": ["#...#", "##.##", "#.#.#", "#.#.#", "#...#", "#...#", "#...#", "#...#"],
    "W": ["#...#", "#...#", "#...#", "#...#", "#.#.#", "#.#.#", "#.#.#", ".#.#."],
    "4": ["...#.", "..##.", ".#.#.", "#..#.", "#..#.", "#####", "...#.", "...#."],
    "9": [".###.", "#...#", "#...#", ".####", "....#", "....#", "#...#", ".###."],
}
# VT323's f has a foot, and in a command "-rf" then reads like "-rE".
VT20_GLYPHS = {
    "f": ["...###..", "...###..", "..##....", ".#####..", ".#####..", "..##....",
          "..##....", "..##....", "..##....", "..##....", "..##...."],
}
OVERRIDES = {"vt14": VT15_GLYPHS, "vt16": VT15_GLYPHS, "vt18": VT20_GLYPHS}
# VT323 at 20 px has 6 columns of ink in 8 of advance. One less matches the width
# the design's 18 px text has, so commands wrap where the design wraps them.
ADV_ADJUST = {"vt18": -1}
CHARS = [chr(c) for c in range(32, 127)] + ["·"]


SS = 16


def load(path, size, weight):
    font = ImageFont.truetype(str(ROOT / "fonts" / path), size)
    if weight:
        font.set_variation_by_axes([weight])
    return font


def glyph_rows(font, big, ch, method):
    """Returns (w, h, ox, oy, rows of 0/1) with (ox, oy) from the pen on the baseline."""
    if method == "mono":
        mask, (ox, oy) = font.getmask2(ch, mode="1", anchor="ls")
        w, h = mask.size
        return w, h, ox, oy, [[1 if mask.getpixel((x, y)) else 0 for x in range(w)] for y in range(h)]
    l, t, r, b = big.getbbox(ch, anchor="ls")
    if r <= l or b <= t:
        return 0, 0, 0, 0, []
    x0, y0 = l // SS, t // SS
    x1, y1 = -(-r // SS), -(-b // SS)
    w, h = x1 - x0, y1 - y0
    im = Image.new("L", (w * SS, h * SS), 0)
    ImageDraw.Draw(im).text((-x0 * SS, -y0 * SS), ch, font=big, fill=255, anchor="ls")
    small = im.resize((w, h), Image.BOX)
    rows = [[1 if small.getpixel((x, y)) >= 128 else 0 for x in range(w)] for y in range(h)]
    return w, h, x0, y0, rows


def render(name, path, size, box, weight, method):
    font = load(path, size, weight)
    big = load(path, size * SS, weight)
    asc, desc = font.getmetrics()
    base = round((box - (asc + desc)) / 2) + asc
    bits, glyphs = bytearray(), []
    for ch in CHARS:
        w, h, ox, oy, rows = glyph_rows(font, big, ch, method)
        drawn = OVERRIDES.get(name, {}).get(ch)
        if drawn:
            w, h, ox, oy = len(drawn[0]), len(drawn), 0, -len(drawn)
            rows = [[1 if c == "#" else 0 for c in row] for row in drawn]
        off = len(bits)
        for row in rows:
            for i in range(0, w, 8):
                byte = 0
                for k, v in enumerate(row[i : i + 8]):
                    byte |= v << (7 - k)
                bits.append(byte)
        adv = round(big.getlength(ch) / SS) if method == "over" else round(font.getlength(ch))
        glyphs.append((off, w, h, ox, oy, adv + ADV_ADJUST.get(name, 0)))
    return bits, glyphs, base


def main():
    src = ['// Generated by tools/gen_fonts.py. Do not edit.', '#include "fonts.h"', ""]
    hdr = ["// Generated by tools/gen_fonts.py. Do not edit.", "#pragma once", '#include "gfx.h"', ""]
    for name, path, size, box, weight, method in FONTS:
        bits, glyphs, base = render(name, path, size, box, weight, method)
        src.append(f"static const uint8_t {name}_bits[] = {{")
        for i in range(0, len(bits), 24):
            src.append(",".join(str(b) for b in bits[i : i + 24]) + ",")
        src.append("};")
        src.append(f"static const glyph_t {name}_g[] = {{")
        for g in glyphs:
            src.append("{%d,%d,%d,%d,%d,%d}," % g)
        src.append("};")
        src.append(f"const font_t {name} = {{{name}_bits, {name}_g, {box}, {base}}};")
        src.append("")
        hdr.append(f"extern const font_t {name};")
        print(f"{name}: base {base}, {len(bits)} bytes")
    (OUT / "fonts.c").write_text("\n".join(src) + "\n")
    (OUT / "fonts.h").write_text("\n".join(hdr) + "\n")


if __name__ == "__main__":
    main()
