#include "art.h"

#include <string.h>

static art_t now_showing;  // id "" is nothing

// ---------------------------------------------------------------- building one

bool art_begin(art_t *a, const char *id) {
  memset(a, 0, sizeof(*a));
  for (int s = 0; s < ART_SLOTS; s++) a->wear[s].sprite = -1;
  a->fall.sprite = -1;
  size_t n = strlen(id);
  if (n < 1 || n >= sizeof(a->id)) return false;
  for (size_t i = 0; i < n; i++) {
    char c = id[i];
    if (!((c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || (c >= '0' && c <= '9') || c == '-')) return false;
  }
  memcpy(a->id, id, n + 1);
  return true;
}

bool art_color(art_t *a, int index, uint32_t rgb) {
  if (index < 1 || index > ART_COLORS || rgb > 0xFFFFFF) return false;
  a->pal[index] = RGB(rgb);
  if (index > a->colors) a->colors = (uint8_t)index;
  return true;
}

static int dot_value(char c) {
  if (c == '.') return 0;
  if (c >= '1' && c <= '9') return c - '0';
  if (c >= 'a' && c <= 'f') return c - 'a' + 10;
  return -1;
}

static void put_dot(art_t *a, int i, int v) {
  uint8_t *b = &a->px[i >> 1];
  *b = (i & 1) ? (uint8_t)((*b & 0x0F) | (v << 4)) : (uint8_t)((*b & 0xF0) | v);
}

static int get_dot(const art_t *a, int i) {
  uint8_t b = a->px[i >> 1];
  return (i & 1) ? b >> 4 : b & 0x0F;
}

bool art_sprite(art_t *a, int w, int h, int ms, const char *const *rows, int n) {
  if (a->sprites >= ART_SPRITES || w < 1 || h < 1 || w > ART_SPRITE_MAX || h > ART_SPRITE_MAX) return false;
  if (n < h || n % h || n / h > ART_FRAMES || ms < 0 || ms > 60000) return false;
  if (a->dots + w * n > ART_DOTS) return false;
  art_sprite_t *s = &a->sp[a->sprites];
  s->w = (uint8_t)w;
  s->h = (uint8_t)h;
  s->frames = (uint8_t)(n / h);
  s->ms = (uint16_t)ms;
  s->at = a->dots;
  for (int r = 0; r < n; r++) {
    if (!rows[r] || (int)strlen(rows[r]) != w) return false;
    for (int c = 0; c < w; c++) {
      int v = dot_value(rows[r][c]);
      if (v < 0) return false;
      put_dot(a, s->at + r * w + c, v);
    }
  }
  a->dots += (uint16_t)(w * n);
  a->sprites++;
  return true;
}

static int slot_named(const char *on) {
  static const char *const names[ART_SLOTS] = {"head", "face", "body", "neck"};
  for (int i = 0; i < ART_SLOTS; i++)
    if (!strcmp(on, names[i])) return i;
  return -1;
}

enum { ON_LEFT, ON_CENTRE, ON_RIGHT, ON_SKY };

static int place_named(const char *on) {
  static const char *const names[] = {"left", "centre", "right", "sky"};
  for (int i = 0; i < 4; i++)
    if (!strcmp(on, names[i])) return i;
  return -1;
}

bool art_wear(art_t *a, int sprite, const char *on, int x, int y, int hide) {
  int slot = slot_named(on);
  if (slot < 0 || a->wear[slot].sprite >= 0 || sprite < 0 || sprite >= ART_SPRITES) return false;
  if (x < -ART_SPRITE_MAX || x > ART_SPRITE_MAX || y < -ART_SPRITE_MAX || y > ART_SPRITE_MAX || hide < 0 || hide > 15) return false;
  a->wear[slot] = (art_wear_t){.sprite = (int8_t)sprite, .x = (int8_t)x, .y = (int8_t)y, .hide = (uint8_t)hide};
  return true;
}

bool art_piece(art_t *a, int sprite, const char *on, int x, int y) {
  int place = place_named(on);
  if (place < 0 || a->pieces >= ART_PIECES || sprite < 0 || sprite >= ART_SPRITES) return false;
  if (x < -64 || x > 64 || y < -ART_SPRITE_MAX || y > 64) return false;
  a->set[a->pieces++] = (art_piece_t){.sprite = (uint8_t)sprite, .on = (uint8_t)place, .x = (int8_t)x, .y = (int8_t)y};
  return true;
}

bool art_fall(art_t *a, int sprite, int n, int vy, int vx, int sway) {
  if (a->fall.sprite >= 0 || sprite < 0 || sprite >= ART_SPRITES || n < 1 || n > ART_FALLING) return false;
  if (vy < -40 || vy > 40 || vx < -40 || vx > 40 || sway < 0 || sway > 8) return false;
  a->fall = (art_fall_t){.sprite = (int8_t)sprite, .n = (uint8_t)n, .vy = (int8_t)vy, .vx = (int8_t)vx, .sway = (uint8_t)sway};
  return true;
}

bool art_say(art_t *a, const char *text) {
  size_t n = strlen(text);
  if (n > ART_SAY) return false;
  for (size_t i = 0; i < n; i++)
    if (text[i] < 32 || text[i] > 126) return false;
  memcpy(a->say, text, n + 1);
  return true;
}

bool art_finish(const art_t *a) {
  for (int i = 0; i < a->dots; i++)
    if (get_dot(a, i) > a->colors) return false;
  for (int s = 0; s < ART_SLOTS; s++)
    if (a->wear[s].sprite >= a->sprites) return false;
  for (int i = 0; i < a->pieces; i++)
    if (a->set[i].sprite >= a->sprites) return false;
  return a->fall.sprite < a->sprites;
}

// ---------------------------------------------------------------- what's showing

void art_use(const art_t *a) {
  if (a) {
    memcpy(&now_showing, a, sizeof(now_showing));
  } else {
    now_showing.id[0] = 0;
  }
}

const char *art_id(void) { return now_showing.id; }

static bool showing(void) { return now_showing.id[0] != 0; }

// ---------------------------------------------------------------- drawing

static int frame_at(const art_sprite_t *s, int64_t now, uint32_t offset) {
  if (s->frames < 2 || !s->ms) return 0;
  return (int)(((uint64_t)now + offset) / s->ms % s->frames);
}

// Each row's runs of one colour as one fill, as Bit's body is drawn.
static void draw_sprite(const art_sprite_t *s, int frame, int x, int y, int dot) {
  const art_t *a = &now_showing;
  for (int r = 0; r < s->h; r++) {
    int row = s->at + (frame * s->h + r) * s->w;
    for (int c = 0; c < s->w;) {
      int v = get_dot(a, row + c), e = c + 1;
      while (e < s->w && get_dot(a, row + e) == v) e++;
      if (v) gfx_fill(x + c * dot, y + r * dot, (e - c) * dot, dot, a->pal[v]);
      c = e;
    }
  }
}

static int64_t wrap(int64_t v, int64_t span) { return span > 0 ? ((v % span) + span) % span : 0; }

// The same every time for each one, and apart from esp_random, so Bit's own wandering is unchanged.
static uint32_t mix(uint32_t v) {
  v ^= v >> 16;
  v *= 0x7FEB352Du;
  v ^= v >> 15;
  v *= 0x846CA68Bu;
  v ^= v >> 16;
  return v;
}

// Whether the glass shows the whole box: only rounded corners hide anything.
static bool glass_shows(int x, int y, int w, int h) {
  int side = gfx_inset(y, h, 0);
  return x >= side && x + w <= SCR_W - side;
}

static void draw_falling(int64_t now, int width, int top, int ground, int dot) {
  const art_fall_t *f = &now_showing.fall;
  const art_sprite_t *s = &now_showing.sp[f->sprite];
  int sw = s->w * dot, sh = s->h * dot;
  int span_x = width - 12 - sw, span_y = ground - top + sh;
  if (span_x <= 0) return;
  for (int i = 0; i < f->n; i++) {
    uint32_t a = mix(2 * i + 1), b = mix(2 * i + 2);
    int64_t x = 6 + wrap((int64_t)(a % (uint32_t)span_x) + now * f->vx * dot / 1000, span_x);
    int64_t y = top - sh + wrap((int64_t)(b % (uint32_t)span_y) + now * f->vy * dot / 1000, span_y);
    if (f->sway) {
      int period = 1600 + (int)(a % 1200), amp = f->sway * dot;
      int t = (int)wrap(now + b, period), tri = t < period / 2 ? t : period - t;
      x += tri * 2 * amp / period - amp / 2;
    }
    x -= wrap(x, dot);  // on whole dots, as Bit is
    y -= wrap(y, dot);
    if (!glass_shows((int)x, (int)y, sw, sh)) continue;
    draw_sprite(s, frame_at(s, now, b), (int)x, (int)y, dot);
  }
}

// The stage as last drawn: what Bit wears stays on it too.
static int stage_w, stage_top, stage_ground;

void art_draw_stage(int64_t now, int width, int top, int ground, int dot) {
  stage_w = width;
  stage_top = top;
  stage_ground = ground;
  if (!showing()) return;
  gfx_clip(0, top, width, ground - top);
  for (int i = 0; i < now_showing.pieces; i++) {
    const art_piece_t *p = &now_showing.set[i];
    const art_sprite_t *s = &now_showing.sp[p->sprite];
    int w = s->w * dot, h = s->h * dot;
    int y = p->on == ON_SKY ? top + p->y * dot : ground - (p->y * dot + h);
    int side = gfx_inset(y, h, 6);
    int x = p->on == ON_LEFT ? side + p->x * dot : p->on == ON_RIGHT ? width - side - p->x * dot - w : (width - w) / 2 + p->x * dot;
    // a piece that doesn't fit this stage isn't drawn, rather than drawn over something
    if (x < side || x + w > width - side || y < top || y + h > ground) continue;
    draw_sprite(s, frame_at(s, now, 0), x, y, dot);
  }
  if (now_showing.fall.sprite >= 0) draw_falling(now, width, top, ground, dot);
  gfx_noclip();
}

bool art_wears(art_slot_t slot) { return showing() && slot < ART_SLOTS && now_showing.wear[slot].sprite >= 0; }

void art_draw_wear(art_slot_t slot, int64_t now, int x, int y, int dot, int modes) {
  if (!art_wears(slot)) return;
  const art_wear_t *w = &now_showing.wear[slot];
  if (w->hide & modes) return;
  const art_sprite_t *s = &now_showing.sp[w->sprite];
  gfx_clip(0, stage_top, stage_w, stage_ground - stage_top);
  draw_sprite(s, frame_at(s, now, 0), x + w->x * dot, y + w->y * dot, dot);
  gfx_noclip();
}

const char *art_said(void) { return showing() ? now_showing.say : ""; }
