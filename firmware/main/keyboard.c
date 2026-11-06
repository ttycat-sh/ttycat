#include "keyboard.h"

#include <stdio.h>
#include <string.h>

#include "fonts.h"
#include "gfx.h"
#include "model.h"

#define BLACK RGB(0x000000)
#define KEY RGB(0x1E1E1E)
#define KEY_ALT RGB(0x0C0C0C)
#define LINE RGB(0x262626)
#define WHITE RGB(0xFFFFFF)
#define ORANGE accent_color
#define MUTED RGB(0x9A9A9A)
#define FAINT RGB(0x505050)
#define CODE RGB(0x0B0B0B)

// Ten keys fill the width, and four rows of them sit at the bottom, under the text: on the official
// 240x320 board, keys 24x48, and three lines of text.
static int row_step(void) {
  int step = (SCR_H - 94) / 4;
  return step > 52 ? 52 : step;
}
#define KEY_W (SCR_W / 10)
#define ROW_STEP row_step()
#define KEYS_TOP (SCR_H - 2 - 4 * ROW_STEP)
#define KEY_H (ROW_STEP - 4)
#define BOX_H (KEYS_TOP - 4 - BOX_TOP)
#define TEXT_LINES ((BOX_H - 26) / 18)

enum {
  BOX_TOP = 24,
  // not characters
  K_SHIFT = 1,
  K_PAGE = 2,    // the two symbol pages
  K_BACK = 3,
  K_LAYER = 4,   // letters and symbols
  K_DONE = 5,
  REPEAT_AFTER_MS = 500,
  REPEAT_EVERY_MS = 90,
};

typedef enum { LOWER, UPPER, SYM1, SYM2 } layer_t;

static const char *const ROWS[4][3] = {
    {"qwertyuiop", "asdfghjkl", "zxcvbnm"},
    {"QWERTYUIOP", "ASDFGHJKL", "ZXCVBNM"},
    {"1234567890", "-/:;()$&@\"", ".,?!'+="},
    {"[]{}#%^*~|", "_\\<>`", ".,?!'+="},
};

typedef struct {
  int16_t x, w;
  uint8_t code;
} key_t_;

static char *buf;
static size_t cap;
static char saved[TYPED_MAX + 1];
static char prompt_text[72];
static layer_t layer;
static bool caps_lock;
static int64_t shift_at, press_at, repeat_at;
static bool pressing;

static void match_case(void) {
  if (layer == LOWER || layer == UPPER) layer = buf[0] == 0 || caps_lock ? UPPER : LOWER;
}

void keyboard_open(char *text, size_t text_cap, const char *prompt) {
  buf = text;
  cap = text_cap;
  strlcpy(saved, text, sizeof(saved));
  strlcpy(prompt_text, prompt, sizeof(prompt_text));
  layer = LOWER;
  caps_lock = false;
  pressing = false;
  match_case();
}

// The keys of one row, left to right. A row a rounded corner of the glass reaches into keeps clear of
// it (gfx_inset), with narrower keys if it has to: the others, and every row on a square screen, span the width.
static int row_keys(int row, key_t_ *out) {
  int n = 0, edge = gfx_inset(KEYS_TOP + row * ROW_STEP, KEY_H, 0), room = SCR_W - 2 * edge;
  if (row == 3) {
    static const struct { int8_t w; uint8_t code; } bottom[5] = {{2, K_LAYER}, {1, ','}, {4, ' '}, {1, '.'}, {2, K_DONE}};
    int unit = 10 * KEY_W > room ? room / 10 : KEY_W;
    int x = (SCR_W - 10 * unit) / 2;
    for (int i = 0; i < 5; i++) {
      out[n++] = (key_t_){(int16_t)x, (int16_t)(bottom[i].w * unit), bottom[i].code};
      x += bottom[i].w * unit;
    }
    return n;
  }
  const char *keys = ROWS[layer][row];
  int count = (int)strlen(keys);
  if (row == 2) {  // wide keys either side
    int unit = (count + 2) * KEY_W > room ? room / (count + 2) : KEY_W;
    int side = (SCR_W - count * unit) / 2;
    out[n++] = (key_t_){(int16_t)edge, (int16_t)(side - edge), (uint8_t)(layer <= UPPER ? K_SHIFT : K_PAGE)};
    for (int i = 0; i < count; i++) out[n++] = (key_t_){(int16_t)(side + i * unit), (int16_t)unit, (uint8_t)keys[i]};
    out[n++] = (key_t_){(int16_t)(SCR_W - side), (int16_t)(side - edge), K_BACK};
    return n;
  }
  int unit = count * KEY_W > room ? room / count : KEY_W;
  int x0 = (SCR_W - count * unit) / 2;
  for (int i = 0; i < count; i++) out[n++] = (key_t_){(int16_t)(x0 + i * unit), (int16_t)unit, (uint8_t)keys[i]};
  return n;
}

// Generous: anything on a row belongs to its nearest key, so the gaps aren't dead.
static bool key_at(int x, int y, key_t_ *found, int *row_out) {
  if (y < KEYS_TOP - 4) return false;
  int row = (y - KEYS_TOP) / ROW_STEP;
  if (row < 0) row = 0;
  if (row > 3) row = 3;
  key_t_ keys[14];
  int n = row_keys(row, keys);
  if (x < keys[0].x) x = keys[0].x;
  if (x >= keys[n - 1].x + keys[n - 1].w) x = keys[n - 1].x + keys[n - 1].w - 1;
  for (int i = 0; i < n; i++)
    if (x >= keys[i].x && x < keys[i].x + keys[i].w) {
      *found = keys[i];
      *row_out = row;
      return true;
    }
  return false;
}

static void backspace(void) {
  size_t len = strlen(buf);
  if (len) buf[len - 1] = 0;
  match_case();
}

static const char *key_label(uint8_t code, char *one) {
  switch (code) {
    case K_SHIFT: return caps_lock ? "CAP" : layer == UPPER ? "UP" : "up";
    case K_PAGE: return layer == SYM1 ? "#+=" : "123";
    case K_BACK: return "DEL";
    case K_LAYER: return layer <= UPPER ? "123" : "abc";
    case K_DONE: return "Done";
    case ' ': return "space";
    default:
      one[0] = (char)code;
      one[1] = 0;
      return one;
  }
}

void keyboard_draw(int64_t now, bool finger_down, int fx, int fy) {
  int hl = gfx_inset(2, 16, 6);  // the header's ends, clear of any rounded corner
  gfx_icon((const uint8_t[5]){0x02, 0x04, 0x08, 0x04, 0x02}, hl, 8, 1, WHITE);
  gfx_caps(&sk9, hl + 9, 5, WHITE, "Cancel", 0);
  char count[12];
  size_t len = strlen(buf);
  snprintf(count, sizeof(count), "%d/%d", (int)len, (int)cap - 1);
  gfx_right(&vt16, SCR_W - hl, 2, len + 1 >= cap ? ORANGE : FAINT, count);

  gfx_box(6, BOX_TOP, SCR_W - 12, BOX_H, CODE, NULL, BLACK);
  int pl = gfx_inset(BOX_TOP + 2, 15, 12);  // further in if a rounded corner reaches this far down
  gfx_clip(pl, BOX_TOP + 2, SCR_W - 2 * pl, 15);
  gfx_text(&vt14, pl, BOX_TOP + 2, MUTED, prompt_text);
  gfx_noclip();

  // the end of the text, and a blinking caret: the box only holds a few lines
  static char shown[TYPED_MAX + 2];
  snprintf(shown, sizeof(shown), "%s%c", buf, (now / 500) % 2 ? ' ' : '_');
  int top = BOX_TOP + 22, tl = gfx_inset(top, 18, 12);
  gfx_clip(0, 0, 0, 0);
  int lines = gfx_wrap(&vt18, tl, 0, SCR_W - 2 * tl, 18, WHITE, shown, 0, 0);
  gfx_clip(tl - 2, top, SCR_W - 2 * tl + 4, TEXT_LINES * 18);
  gfx_wrap(&vt18, tl, top - (lines > TEXT_LINES ? (lines - TEXT_LINES) * 18 : 0), SCR_W - 2 * tl, 18, WHITE, shown, 0, 0);
  gfx_noclip();

  key_t_ held = {0};
  int held_row = -1;
  if (finger_down && !key_at(fx, fy, &held, &held_row)) held_row = -1;
  for (int row = 0; row < 4; row++) {
    key_t_ keys[14];
    int n = row_keys(row, keys);
    int y = KEYS_TOP + row * ROW_STEP;
    for (int i = 0; i < n; i++) {
      const key_t_ *k = &keys[i];
      bool is_held = row == held_row && k->x == held.x;
      bool on = k->code == K_SHIFT && (layer == UPPER || caps_lock);
      bool done = k->code == K_DONE;
      bool alt = k->code < ' ';
      color_t bg = is_held ? WHITE : done || on ? ORANGE : alt ? KEY_ALT : KEY;
      gfx_box(k->x + 1, y, k->w - 2, KEY_H, bg, NULL, BLACK);
      char one[2];
      const char *label = key_label(k->code, one);
      color_t ink = is_held || done || on ? BLACK : alt ? MUTED : WHITE;
      const font_t *f = k->code >= ' ' && k->code != ' ' ? &vt18 : &vt14;
      gfx_center(f, k->x, k->w, y + (KEY_H - f->size) / 2, ink, label, 0);
    }
  }

  // the finger hides the key: show it above
  if (held_row >= 0 && held.code > ' ') {
    int bw = 36, bx = held.x + held.w / 2 - bw / 2;
    int by = KEYS_TOP + held_row * ROW_STEP - 42;
    if (bx < 2) bx = 2;
    if (bx + bw > SCR_W - 2) bx = SCR_W - 2 - bw;
    gfx_box(bx, by, bw, 40, WHITE, NULL, BLACK);
    char one[2] = {(char)held.code, 0};
    gfx_center(&ps24, bx, bw, by + 8, BLACK, one, 0);
  }

  // holding Delete keeps deleting
  if (finger_down && held_row >= 0 && held.code == K_BACK) {
    if (!pressing) {
      pressing = true;
      press_at = now;
      repeat_at = now + REPEAT_AFTER_MS;
    } else if (now >= repeat_at) {
      backspace();
      repeat_at = now + REPEAT_EVERY_MS;
    }
  } else if (!finger_down) {
    pressing = false;
  }
}

keyboard_result_t keyboard_release(int x, int y, int64_t now) {
  if (y < 22) {
    if (x < gfx_inset(2, 16, 6) + 74) {
      strlcpy(buf, saved, cap);
      return KEYBOARD_CANCELLED;
    }
    return KEYBOARD_TYPING;
  }
  bool repeated = pressing && now >= press_at + REPEAT_AFTER_MS;
  pressing = false;
  key_t_ k;
  int row;
  if (!key_at(x, y, &k, &row)) return KEYBOARD_TYPING;
  size_t len = strlen(buf);
  switch (k.code) {
    case K_SHIFT:
      // twice quickly locks capitals, as on a phone
      if (caps_lock) {
        caps_lock = false;
        layer = LOWER;
      } else if (layer == UPPER && now - shift_at < 400) {
        caps_lock = true;
      } else {
        layer = layer == UPPER ? LOWER : UPPER;
        shift_at = now;
      }
      break;
    case K_PAGE: layer = layer == SYM1 ? SYM2 : SYM1; break;
    case K_LAYER:
      if (layer <= UPPER) {
        layer = SYM1;
      } else {
        layer = LOWER;
        match_case();
      }
      break;
    case K_BACK:
      if (!repeated) backspace();
      break;
    case K_DONE: return KEYBOARD_DONE;
    default:
      if (len + 1 < cap) {
        buf[len] = (char)k.code;
        buf[len + 1] = 0;
      }
      match_case();
      break;
  }
  return KEYBOARD_TYPING;
}
