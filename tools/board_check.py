#!/usr/bin/env python3
"""Whether ttycat will run on a board, and how to set its folder up. Standard library only.

  board_check.py --chip esp32s3 --screen 480x480 --inches 4 --touch --psram 8
  board_check.py --chip esp32c6 --screen 172x320 --inches 1.47 --touch --stand portrait
  board_check.py --chip esp32s3 --screen 480x480 --inches 2.16 --touch --psram 8 --corner 96

It says yes or no for each requirement, with the reason, then PANEL_W, PANEL_H and ZOOM for the board's
board.c. Exits 0 if the board can run it, 1 if it can't. The memory figures are estimates: board_begin
checks for real on the board, and stops with a message saying so if the picture doesn't fit.
"""
import argparse, math, sys

# What the screens are laid out for, after zooming: gfx.h's SCR_MIN_W, SCR_MIN_H and SCR_MAX.
MIN_W, MIN_H, MAX = 170, 240, 480
# The official board's pixels per inch: 240x320 at 2.8". A zoom near this looks like it.
REFERENCE_PPI = 143

# Roughly the internal RAM left in one piece once the firmware is running, in KB, and how the chip can
# talk to a Mac over USB: "native" has USB serial built in, "uart" needs a USB-to-serial chip on the board.
CHIPS = {
    "esp32": (100, "uart"),  # measured: why most "Cheap Yellow Display" boards can't run it without PSRAM
    "esp32s2": (150, "uart"),  # its own USB isn't the serial kind the firmware uses
    "esp32s3": (250, "native"),
    "esp32c3": (180, "native"),
    "esp32c5": (190, "native"),  # the official board: 150 KB for its 240x320 picture, with room left
    "esp32c6": (250, "native"),
    "esp32c61": (180, "native"),
    "esp32h2": (150, "native"),
    "esp32p4": (300, "native"),
}


def fits(w, h):
    return MIN_W <= w <= MAX and MIN_H <= h <= MAX


def room_for(w, h, zoom, ram_kb, psram):
    """Unzoomed, the screen driver sends from the picture, so it has to be in internal RAM. Zoomed, it can be in PSRAM."""
    return w * h * 2 / 1024 <= ram_kb or (zoom > 1 and psram > 0)


def choose(panel_w, panel_h, inches, stand, ram_kb, psram):
    """The best (w, h, zoom, turned) for the screen, or None. turned: the picture is rotated a quarter turn.
    One the memory can hold, if there's one."""
    options = []
    for turned in (False, True):
        w, h = (panel_h, panel_w) if turned else (panel_w, panel_h)
        if stand == "portrait" and w > h or stand == "landscape" and w < h:
            continue
        for zoom in range(1, 5):
            if w % zoom == 0 and h % zoom == 0 and fits(w // zoom, h // zoom):
                options.append((w // zoom, h // zoom, zoom, turned))
    if not options:
        return None
    options = [o for o in options if room_for(o[0], o[1], o[2], ram_kb, psram)] or options
    if inches:
        ppi = math.hypot(panel_w, panel_h) / inches
        want = ppi / REFERENCE_PPI
        # closest to the official board's look, then the screen as it comes, then the bigger picture
        return min(options, key=lambda o: (abs(o[2] - want), o[3], -o[0] * o[1]))
    return min(options, key=lambda o: (o[3], o[2]))  # as it comes, unzoomed if that fits


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--chip", required=True, help="as ESP-IDF names it: " + ", ".join(CHIPS))
    ap.add_argument("--screen", required=True, help="the panel's own resolution, WIDTHxHEIGHT")
    ap.add_argument("--inches", type=float, help="the screen's diagonal: picks the zoom")
    ap.add_argument("--touch", action="store_true", help="it has a touch screen")
    ap.add_argument("--psram", type=float, default=0, help="PSRAM in MB, if any")
    ap.add_argument("--usb", choices=("native", "uart"), help="how its USB port reaches the chip, if not the chip's usual")
    ap.add_argument("--stand", choices=("portrait", "landscape", "either"), default="either", help="how it'll stand on the desk")
    ap.add_argument("--speaker", action="store_true", help="it has a speaker, or a socket for one with an amp")
    ap.add_argument("--round", action="store_true", help="the screen is round")
    ap.add_argument("--corner", type=int, default=0, help="the radius of the glass's rounded corners, in the panel's pixels, if they're rounded")
    ap.add_argument("--inset", type=int, default=0, help="how much of the panel the glass or a bezel hides along every edge, in its pixels")
    a = ap.parse_args()

    ok = True

    def say(good, what, why=""):
        nonlocal ok
        ok = ok and good is not False
        mark = "yes " if good is True else "no  " if good is False else "note"
        print(f"{mark} {what}" + (f": {why}" if why else ""))

    chip = a.chip.lower().replace("-", "")
    if chip not in CHIPS:
        say(False, f"chip {a.chip}", "not one ttycat knows. Supported: " + ", ".join(CHIPS))
        sys.exit(1)
    ram_kb, usb = CHIPS[chip]
    usb = a.usb or usb
    say(True, f"chip {chip}")
    if usb == "uart":
        say(None, "USB", "through a USB-to-serial chip, such as a CH340: set CONFIG_ESP_CONSOLE_UART_DEFAULT in "
            "sdkconfig.defaults. Nobody has tried this on a real board yet")
    else:
        say(True, "USB", "straight to the chip")

    say(True if a.touch else False, "touch", "" if a.touch else "the whole interface is tapping and swiping")
    if a.round:
        say(False, "screen", "round screens aren't supported yet: the screens are laid out for rectangles")
        sys.exit(1)

    try:
        panel_w, panel_h = (int(n) for n in a.screen.lower().split("x"))
    except ValueError:
        sys.exit("--screen is WIDTHxHEIGHT, such as 240x320")
    shown_w, shown_h = panel_w - 2 * a.inset, panel_h - 2 * a.inset  # what the glass shows of it
    best = choose(shown_w, shown_h, a.inches, a.stand, ram_kb, a.psram)
    if not best:
        say(False, f"screen {panel_w}x{panel_h}", f"no whole-number zoom or quarter turn gives a picture from {MIN_W}x{MIN_H} "
            f"to {MAX}x{MAX}" + (f" standing {a.stand}" if a.stand != "either" else ""))
        sys.exit(1)
    w, h, zoom, turned = best
    how = (" turned a quarter, " if turned else " ") + (f"each pixel {zoom}x{zoom}" if zoom > 1 else "unzoomed")
    say(True, f"screen {panel_w}x{panel_h}", f"a {w}x{h} picture,{how}" + (f", {a.inset} px in from each edge" if a.inset else ""))
    corner = max(0, a.corner - a.inset) // zoom
    if not a.corner and not a.inset:
        say(None, "glass", "look at it: if its corners are rounded, or it hides part of the panel along the edges, "
            "say how much with --corner and --inset, so the screens keep clear of them")
    elif corner * 2 > min(w, h):
        say(False, "glass", f"corners {a.corner} px round are more round than square: round screens aren't supported yet")
        sys.exit(1)
    elif corner:
        say(True, "glass", f"rounded corners, {corner} px in the picture: the screens keep clear of them. "
            f"Check with tools/preview/gallery.py --size {w}x{h} --corner {corner} --cut"
            + (", especially this round" if corner * 4 > min(w, h) else ""))
    if (w, h) == (240, 320):
        say(None, "layout", "the same as the official board")
    elif h < 300:
        say(None, "layout", "a short screen: each screen uses its short form, with smaller buttons and less above them")
    else:
        say(None, "layout", "every screen lays itself out to fit; check them with tools/preview/gallery.py --size %dx%d" % (w, h))
    if not a.inches:
        say(None, "zoom", "give --inches to pick the zoom for how big the pixels are")

    picture_kb = w * h * 2 / 1024
    if zoom == 1 and picture_kb <= ram_kb:
        say(True, "memory", f"the {picture_kb:.0f} KB picture fits in internal RAM (about {ram_kb} KB free in one piece)")
    elif zoom > 1 and (picture_kb <= ram_kb or a.psram):
        where = "internal RAM" if picture_kb <= ram_kb else "PSRAM"
        say(True, "memory", f"the {picture_kb:.0f} KB picture fits in {where}, and goes to the screen a few rows at a time")
    elif a.psram:
        say(False, "memory", f"the {picture_kb:.0f} KB picture is too big for internal RAM (about {ram_kb} KB). "
            "Unzoomed, it has to be there for the screen driver to send it. A zoom would let it go in PSRAM")
    else:
        say(False, "memory", f"the {picture_kb:.0f} KB picture needs about {picture_kb:.0f} KB in one piece, and this chip has about {ram_kb} KB")

    if a.speaker:
        say(True, "speaker", "for the chime: the board's folder plays it, as the official board's speaker.c does")
    else:
        say(None, "speaker", "none given: no chime, and everything else works")
    print()
    if ok:
        print("For the board's board.c:")
        print(f"  #define PANEL_W {panel_h if turned else panel_w}")
        print(f"  #define PANEL_H {panel_w if turned else panel_h}")
        print(f"  #define ZOOM {zoom}")
        print(f"  #define CORNER_RADIUS {a.corner}")
        print(f"  #define EDGE_INSET {a.inset}")
        if turned:
            print("  and turn the screen a quarter in board_begin (esp_lcd_panel_swap_xy, then mirror as needed), and touch with it")
    else:
        print("ttycat won't run on this board as it is.")
    sys.exit(0 if ok else 1)


main()
