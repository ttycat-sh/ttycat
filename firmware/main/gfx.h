// Immediate-mode drawing into the 240x320 RGB565 framebuffer. No anti-aliasing:
// everything lands on whole pixels, as the design's pixel system asks.
#pragma once
#include <stdbool.h>
#include <stdint.h>

#define SCR_W 240
#define SCR_H 320

// 0xRRGGBB to RGB565, byte-swapped for the panel.
#define RGB(c)                                                                         \
  ((uint16_t)((((((c) >> 16) & 0xF8) | (((c) >> 13) & 0x07))) |                        \
              ((((((c) >> 5) & 0xE0) | (((c) >> 3) & 0x1F))) << 8)))

typedef uint16_t color_t;

// What the Mac chose: Bit's skin and the accent, by number. Tables in gfx.c, and the app's Look.swift.
extern color_t accent_color, bit_body, bit_shade;
void look_set(int skin, int accent);

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
// A 2 px border inside the box.
void gfx_border(int x, int y, int w, int h, color_t c);
void gfx_dashed(int x, int y, int w, int h, color_t c);
// The design's stepped corner: paints the 2x2 corners in the colour behind.
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
