#include "gfx.h"

#include <ctype.h>
#include <string.h>

static const color_t SKINS[][2] = {
    {RGB(0xFF6A13), RGB(0xB84A0C)},  // Ember
    {RGB(0x3FD38A), RGB(0x1F8F58)},  // Mint
    {RGB(0x5AB8FF), RGB(0x2E78B8)},  // Ice
    {RGB(0xB07CFF), RGB(0x7443C4)},  // Grape
    {RGB(0xFF6FA8), RGB(0xB83E72)},  // Rose
    {RGB(0xD8D8D8), RGB(0x8A8A8A)},  // Mono
};
static const color_t ACCENTS[] = {
    RGB(0xFF6A13),  // Orange
    RGB(0x2DD4BF),  // Teal
    RGB(0x5AB8FF),  // Blue
    RGB(0xB07CFF),  // Violet
    RGB(0xFFC83D),  // Yellow
};

color_t accent_color = RGB(0xFF6A13), bit_body = RGB(0xFF6A13), bit_shade = RGB(0xB84A0C);

void look_set(int skin, int accent) {
  if (skin < 0 || skin >= (int)(sizeof(SKINS) / sizeof(SKINS[0]))) skin = 0;
  if (accent < 0 || accent >= (int)(sizeof(ACCENTS) / sizeof(ACCENTS[0]))) accent = 0;
  bit_body = SKINS[skin][0];
  bit_shade = SKINS[skin][1];
  accent_color = ACCENTS[accent];
}

uint16_t *gfx_fb;
int gfx_w = 240, gfx_h = 320;

static int cx0 = 0, cy0 = 0, cx1 = 240, cy1 = 320;

bool gfx_size(int w, int h) {
  if (w < SCR_MIN_W || h < SCR_MIN_H || w > SCR_MAX || h > SCR_MAX) return false;
  gfx_w = w;
  gfx_h = h;
  gfx_noclip();
  return true;
}

// The glass: for each row from the top or bottom edge, how many columns at each side its corners hide.
static int corner_r;
static uint8_t corner_cut[SCR_MAX / 2];

void gfx_corner(int radius) {
  int most = (SCR_W < SCR_H ? SCR_W : SCR_H) / 2;
  corner_r = radius < 0 ? 0 : radius > most ? most : radius;
  for (int j = 0; j < corner_r; j++) {
    // a pixel shows if its centre is inside the corner's circle: in half pixels, so it's all whole numbers
    int dy = 2 * j + 1 - 2 * corner_r, x = 0;
    while (x < corner_r && (2 * x + 1 - 2 * corner_r) * (2 * x + 1 - 2 * corner_r) + dy * dy > 4 * corner_r * corner_r) x++;
    corner_cut[j] = (uint8_t)x;
  }
}

static int cut_at(int row) {
  if (!corner_r) return 0;
  if (row < 0) row = 0;
  if (row >= SCR_H) row = SCR_H - 1;
  int from_edge = row < SCR_H / 2 ? row : SCR_H - 1 - row;
  return from_edge < corner_r ? corner_cut[from_edge] : 0;
}

int gfx_inset(int y, int h, int margin) {
  int most = margin;
  for (int j = y; corner_r && j < y + h; j++)
    if (cut_at(j) > most) most = cut_at(j);
  return most;
}

int gfx_bottom(int x) {
  int y = SCR_H;
  while (y > 0 && cut_at(y - 1) > x) y--;
  return y;
}

// The part of a border the glass's corners hide, drawn again just inside the glass, so the box stays closed.
static void glass_border(int x, int y, int w, int h, color_t c) {
  for (int j = y; j < y + h; j++) {
    int cut = cut_at(j);
    if (!cut) continue;
    int nearer = cut_at(j < SCR_H / 2 ? j - 2 : j + 2), to = cut + 2 > nearer ? cut + 2 : nearer;
    if (x < cut) gfx_fill(cut, j, (to < x + w ? to : x + w) - cut, 1, c);
    if (x + w > SCR_W - cut) {
      int from = SCR_W - to > x ? SCR_W - to : x;
      gfx_fill(from, j, SCR_W - cut - from, 1, c);
    }
  }
}

void gfx_zoomed(int zoom, int y, int rows, uint16_t *out) {
  for (int j = y; j < y + rows; j++) {
    const uint16_t *src = gfx_fb + j * SCR_W;
    uint16_t *line = out;
    for (int i = 0; i < SCR_W; i++)
      for (int k = 0; k < zoom; k++) *out++ = src[i];
    for (int k = 1; k < zoom; k++, out += SCR_W * zoom) memcpy(out, line, SCR_W * zoom * 2);
  }
}

void gfx_clear(color_t c) {
  if ((c & 0xFF) == (c >> 8)) {
    memset(gfx_fb, c & 0xFF, SCR_W * SCR_H * 2);
    return;
  }
  for (int i = 0; i < SCR_W * SCR_H; i++) gfx_fb[i] = c;
}

void gfx_clip(int x, int y, int w, int h) {
  cx0 = x < 0 ? 0 : x;
  cy0 = y < 0 ? 0 : y;
  cx1 = x + w > SCR_W ? SCR_W : x + w;
  cy1 = y + h > SCR_H ? SCR_H : y + h;
}

void gfx_noclip(void) {
  cx0 = cy0 = 0;
  cx1 = SCR_W;
  cy1 = SCR_H;
}

void gfx_fill(int x, int y, int w, int h, color_t c) {
  int x1 = x + w, y1 = y + h;
  if (x < cx0) x = cx0;
  if (y < cy0) y = cy0;
  if (x1 > cx1) x1 = cx1;
  if (y1 > cy1) y1 = cy1;
  for (int j = y; j < y1; j++) {
    uint16_t *p = gfx_fb + j * SCR_W + x;
    for (int i = x; i < x1; i++) *p++ = c;
  }
}

void gfx_border(int x, int y, int w, int h, color_t c) {
  gfx_fill(x, y, w, 2, c);
  gfx_fill(x, y + h - 2, w, 2, c);
  gfx_fill(x, y + 2, 2, h - 4, c);
  gfx_fill(x + w - 2, y + 2, 2, h - 4, c);
  if (corner_r) glass_border(x, y, w, h, c);
}

void gfx_dashed(int x, int y, int w, int h, color_t c) {
  for (int i = 0; i < w; i += 8) {
    int n = w - i < 4 ? w - i : 4;
    gfx_fill(x + i, y, n, 2, c);
    if (h > 2) gfx_fill(x + i, y + h - 2, n, 2, c);
  }
  if (h <= 2) return;
  for (int j = 0; j < h; j += 8) {
    int n = h - j < 4 ? h - j : 4;
    gfx_fill(x, y + j, 2, n, c);
    gfx_fill(x + w - 2, y + j, 2, n, c);
  }
}

void gfx_corners(int x, int y, int w, int h, color_t behind) {
  gfx_fill(x, y, 2, 2, behind);
  gfx_fill(x + w - 2, y, 2, 2, behind);
  gfx_fill(x, y + h - 2, 2, 2, behind);
  gfx_fill(x + w - 2, y + h - 2, 2, 2, behind);
}

void gfx_box(int x, int y, int w, int h, color_t bg, const color_t *border, color_t behind) {
  gfx_fill(x, y, w, h, bg);
  if (border) gfx_border(x, y, w, h, *border);
  gfx_corners(x, y, w, h, behind);
}

static const glyph_t *glyph(const font_t *f, char ch) {
  unsigned char c = (unsigned char)ch;
  if (c == 0xB7 || c == 127) return &f->g[95];  // middle dot
  if (c < 32 || c > 126) c = '?';
  return &f->g[c - 32];
}

static void put_glyph(const font_t *f, const glyph_t *g, int px, int base, color_t c) {
  const uint8_t *row = f->bits + g->off;
  int stride = (g->w + 7) / 8;
  for (int j = 0; j < g->h; j++, row += stride) {
    int y = base + g->y + j;
    if (y < cy0 || y >= cy1) continue;
    for (int i = 0; i < g->w; i++) {
      if (!(row[i >> 3] & (0x80 >> (i & 7)))) continue;
      int x = px + g->x + i;
      if (x >= cx0 && x < cx1) gfx_fb[y * SCR_W + x] = c;
    }
  }
}

int gfx_text_sp(const font_t *f, int x, int y, color_t c, const char *s, int spacing) {
  int base = y + f->base;
  for (; *s; s++) {
    const glyph_t *g = glyph(f, *s);
    put_glyph(f, g, x, base, c);
    x += g->adv + spacing;
  }
  return x;
}

int gfx_text(const font_t *f, int x, int y, color_t c, const char *s) {
  return gfx_text_sp(f, x, y, c, s, 0);
}

int gfx_width(const font_t *f, const char *s, int spacing) {
  int w = 0;
  for (; *s; s++) w += glyph(f, *s)->adv + spacing;
  return w;
}

void gfx_center(const font_t *f, int x, int w, int y, color_t c, const char *s, int spacing) {
  gfx_text_sp(f, x + (w - gfx_width(f, s, spacing)) / 2, y, c, s, spacing);
}

void gfx_right(const font_t *f, int right, int y, color_t c, const char *s) {
  gfx_text(f, right - gfx_width(f, s, 0), y, c, s);
}

int gfx_caps(const font_t *f, int x, int y, color_t c, const char *s, int spacing) {
  int base = y + f->base;
  for (; *s; s++) {
    const glyph_t *g = glyph(f, (char)toupper((unsigned char)*s));
    put_glyph(f, g, x, base, c);
    x += g->adv + spacing;
  }
  return x;
}

int gfx_caps_width(const font_t *f, const char *s, int spacing) {
  int w = 0;
  for (; *s; s++) w += glyph(f, (char)toupper((unsigned char)*s))->adv + spacing;
  return w;
}

int gfx_wrap(const font_t *f, int x, int y, int w, int lh, color_t c, const char *s, int hl,
             color_t hl_c) {
  int lines = 1, pen = 0;
  const char *start = s;
  while (*s) {
    if (*s == '\n') {
      s++;
      lines++;
      y += lh;
      pen = 0;
      continue;
    }
    // the next word, with the spaces in front of it
    const char *e = s;
    int ww = 0;
    while (*e == ' ') ww += glyph(f, *e++)->adv;
    int spaces = ww;
    while (*e && *e != ' ' && *e != '\n') ww += glyph(f, *e++)->adv;
    if (pen && pen + ww > w) {
      lines++;
      y += lh;
      pen = 0;
      while (*s == ' ') s++;  // no spaces at a line's start
      spaces = 0;
    }
    (void)spaces;
    for (; s < e; s++) {
      if (*s == ' ' && !pen) continue;
      const glyph_t *g = glyph(f, *s);
      if (pen && pen + g->adv > w) {  // a word longer than the line
        lines++;
        y += lh;
        pen = 0;
      }
      put_glyph(f, g, x + pen, y + f->base, s - start < hl ? hl_c : c);
      pen += g->adv;
    }
  }
  return lines;
}

void gfx_icon(icon5_t icon, int x, int y, int scale, color_t c) {
  for (int j = 0; j < 5; j++)
    for (int i = 0; i < 5; i++)
      if (icon[j] & (0x10 >> i)) gfx_fill(x + i * scale, y + j * scale, scale, scale, c);
}

void gfx_sprite(const char *const rows[10], int x, int y, int dot, int gap, color_t off, color_t o,
                color_t w, color_t g) {
  for (int j = 0; j < 10; j++)
    for (int i = 0; i < 10; i++) {
      char k = rows[j][i];
      color_t c = k == 'o' ? o : k == 'w' ? w : k == 'g' ? g : off;
      gfx_fill(x + i * (dot + gap), y + j * (dot + gap), dot, dot, c);
    }
}
