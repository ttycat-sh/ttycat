// Immediate-mode drawing into the RGB565 framebuffer. No anti-aliasing:
// everything lands on whole pixels, so the pixel art stays crisp.
#pragma once
#include <stdbool.h>
#include <stdint.h>

// The picture's size. The board sets it with gfx_size before anything is drawn: 240x320 on the
// official board, and anything in these limits elsewhere. Every screen lays itself out to fit.
#define SCR_W gfx_w
#define SCR_H gfx_h
#define SCR_MIN_W 170
#define SCR_MIN_H 240
#define SCR_MAX 480
extern int gfx_w, gfx_h;
// False, and nothing changes, if the size is outside the limits above.
bool gfx_size(int w, int h);
// The glass's shape: the radius of its rounded corners, in the picture's pixels. A board whose screen
// has rounded corners calls this once, after gfx_size. Every other screen is square, and 0 means that.
void gfx_corner(int radius);
// How far in from the left and the right something in rows y to y + h - 1 has to start for the glass
// to show it whole: `margin`, or more where a rounded corner would hide it. Always `margin` when square.
int gfx_inset(int y, int h, int margin);
// How far down something `x` pixels in from the sides can go before a rounded corner hides it: SCR_H when square.
int gfx_bottom(int x);
// For a screen with more pixels than the picture: `zoom` screen rows for each of the picture's
// `rows` rows from `y`, each pixel `zoom` wide, into `out`. Send `out` to the screen as is.
void gfx_zoomed(int zoom, int y, int rows, uint16_t *out);

// 0xRRGGBB to RGB565, byte-swapped for the panel.
#define RGB(c)                                                                         \
  ((uint16_t)((((((c) >> 16) & 0xF8) | (((c) >> 13) & 0x07))) |                        \
              ((((((c) >> 5) & 0xE0) | (((c) >> 3) & 0x1F))) << 8)))

typedef uint16_t color_t;

// What the Mac chose: Bit's skin and the accent, by number. Tables in gfx.c, and the app's Look.swift.
extern color_t accent_color, bit_body, bit_shade;
void look_set(int skin, int accent);
// The same, in colours, 0xRRGGBB: for skins the board's tables don't have.
void look_rgb(uint32_t body, uint32_t shade, uint32_t accent);

typedef struct {
  uint32_t off;
  uint8_t w, h;
  int8_t x, y;  // offset from the pen position on the baseline
  uint8_t adv;
} glyph_t;

typedef struct {
  const uint8_t *bits;
  const glyph_t *g;
  uint8_t size;
  int8_t base;  // baseline, from the top of a line-height:1 box
} font_t;

extern uint16_t *gfx_fb;

void gfx_clear(color_t c);
void gfx_clip(int x, int y, int w, int h);
void gfx_noclip(void);
void gfx_fill(int x, int y, int w, int h, color_t c);
// A 2 px border inside the box. Where a rounded corner of the glass would hide it, it follows the glass.
void gfx_border(int x, int y, int w, int h, color_t c);
void gfx_dashed(int x, int y, int w, int h, color_t c);
// A stepped corner, as on every box: paints the 2x2 corners in the colour behind.
void gfx_corners(int x, int y, int w, int h, color_t behind);
// `.n` box: fill, optional 2 px border, stepped corners.
void gfx_box(int x, int y, int w, int h, color_t bg, const color_t *border, color_t behind);

// Text, y = top of the line-height:1 box.
int gfx_text(const font_t *f, int x, int y, color_t c, const char *s);
int gfx_text_sp(const font_t *f, int x, int y, color_t c, const char *s, int spacing);
int gfx_width(const font_t *f, const char *s, int spacing);
void gfx_center(const font_t *f, int x, int w, int y, color_t c, const char *s, int spacing);
void gfx_right(const font_t *f, int right, int y, color_t c, const char *s);
// As gfx_text, in capitals (Silkscreen labels: CSS text-transform: uppercase).
int gfx_caps(const font_t *f, int x, int y, color_t c, const char *s, int spacing);
int gfx_caps_width(const font_t *f, const char *s, int spacing);
// Word wrap inside w. The first `hl` bytes of s are drawn in `hl_c`. Returns lines.
int gfx_wrap(const font_t *f, int x, int y, int w, int lh, color_t c, const char *s, int hl,
             color_t hl_c);

// 5x5 icon, one byte per row (low 5 bits, MSB = left).
typedef const uint8_t icon5_t[5];
void gfx_icon(icon5_t icon, int x, int y, int scale, color_t c);
// 10x10 sprite: rows of '.', 'o', 'w', 'g'.
void gfx_sprite(const char *const rows[10], int x, int y, int dot, int gap, color_t off,
                color_t o, color_t w, color_t g);
