#include "pet.h"

#include <stdio.h>
#include <string.h>

#include "esp_random.h"
#include "esp_timer.h"
#include "fonts.h"
#include "gfx.h"

#define ORANGE accent_color
#define SHADE bit_shade
#define INK RGB(0x0B0B0B)
#define WHITE RGB(0xFFFFFF)
#define GREEN RGB(0x3FD38A)
#define MUTED RGB(0x9A9A9A)
#define GOLD RGB(0xFFD34D)
#define LAPTOP RGB(0xC4C4C4)
#define LAPTOP_EDGE RGB(0x7A7A7A)

enum {
  COLS = 16,
  LEFT = 6,
  HOP_MS = 420,
  STEP_MS = 170,
  REACT_MS = 1300,
  TYPE_MS = 170,
};

// Set by pet_stage, for the screen it's on. These are the official board's.
static int D = 5;          // screen pixels per sprite pixel
static int GROUND = 112;   // the line it stands on
static int STAGE_W = 240;
static int RIGHT = 240 - COLS * 5 - 6;
static int HOP_UP = 3 * 5;
static int DESK = LEFT + 15 * 5;  // where it works: the middle of the stage

typedef enum { SIT, WALK, HOP, NAP, WORK } pet_mode_t;

static const char *const BODY[12] = {
    "..oo........oo..",
    "..ooo......ooo..",
    "..oooooooooooo..",
    ".oooooooooooooo.",
    ".oooooooooooooo.",
    ".oooooooooooooo.",
    ".oooooooooooooo.",
    ".oooooooooooooo.",
    ".oooooooooooooo.",
    ".oooooooooooooo.",
    ".dooooooooooood.",
    "..dddddddddddd..",
};

typedef const char *const icon_t[6];
static icon_t HEART = {".oo.oo.", "ooooooo", "ooooooo", ".ooooo.", "..ooo..", "...o..."};

static pet_mode_t mode = SIT;
static int x = LEFT + 14 * 5;  // always a whole sprite pixel from LEFT, or it never lands on a target
static int target;
static int64_t mode_until, step_at, hop_start;
static int hops;
static int64_t blink_at, blink_end, look_until;
static int look;
static int64_t react_start, banner_until, hello_until;
static pet_reaction_t react_kind;
static int top_y = 112 - 14 * 5;

void pet_stage(int width, int ground, int dot) {
  D = dot;
  GROUND = ground;
  STAGE_W = width;
  RIGHT = width - COLS * D - 6;
  HOP_UP = 3 * D;
  DESK = LEFT + ((width - COLS * D) / 2 - LEFT + D / 2) / D * D;
  x = LEFT + 14 * D > RIGHT ? DESK : LEFT + 14 * D;
  target = x;
  top_y = GROUND - 14 * D;
}

int pet_level(int32_t total) {
  int n = 1;
  while (3 * n * n <= total) n++;
  return n;
}

int pet_progress(int32_t total, int of) {
  int n = pet_level(total);
  int32_t from = 3 * (n - 1) * (n - 1), to = 3 * n * n;
  return (int)((total - from) * of / (to - from));
}

static uint32_t rnd(uint32_t n) { return esp_random() % n; }

static void block(int col, int y, int cols, int rows, color_t c) {
  gfx_fill(x + col * D, y, cols * D, rows * D, c);
}

static void icon(icon_t rows, int ix, int iy, int dot, color_t c) {
  for (int j = 0; j < 6; j++)
    for (int i = 0; i < 7; i++)
      if (rows[j][i] == 'o') gfx_fill(ix + i * dot, iy + j * dot, dot, dot, c);
}

// Which body rows are drawn, top to bottom. Leaving one out is how it breathes.
static int layout(int *rows, bool flat, bool breath_in) {
  int n = 0;
  for (int r = 0; r < 12; r++) {
    if (flat && (r == 3 || r == 4)) continue;
    if (!breath_in && r == 4) continue;
    rows[n++] = r;
  }
  return n;
}

static void start_hops(int64_t now, int n) {
  mode = HOP;
  hops = n;
  hop_start = now;
}

void pet_react(int64_t now, pet_reaction_t what) {
  react_kind = what;
  react_start = now;
  if (what == PET_RESTED || what == PET_WELCOME || what == PET_BIRTHDAY) {  // rested, and glad to see you
    start_hops(now, what == PET_RESTED ? 3 : 5);
    hello_until = now + 4000;
    react_start = 0;  // its hops and the words say it
  } else {
    start_hops(now, 2);
  }
}

void pet_reward(int n, bool level_up) {
  int64_t now = esp_timer_get_time() / 1000;
  start_hops(now, n > 5 ? 5 : n < 1 ? 1 : n);
  if (level_up) banner_until = now + 4000;
}

void pet_bounds(int *bx, int *by, int *bw, int *bh) {
  *bx = x - 8;
  *by = top_y - 8;
  *bw = COLS * D + 16;
  *bh = GROUND - top_y + 12;
}

static void choose_next(int64_t now) {
  if (rnd(100) < 45u) {
    int steps = (RIGHT - LEFT) / D;
    target = LEFT + (int)rnd((uint32_t)steps + 1) * D;
    mode = WALK;
    step_at = now;
  } else {
    mode = SIT;
    mode_until = now + 2500 + rnd(4000);
  }
}

static void advance(int64_t now, const pet_look_t *look_in) {
  if (mode == HOP) {
    if (now - hop_start >= HOP_MS * hops) {
      mode = SIT;
      mode_until = now + 1500;
    }
    return;
  }
  if (look_in->asleep) {
    mode = NAP;
    return;
  }
  if (mode == NAP) {  // just woken: a moment to come round
    mode = SIT;
    mode_until = now + 2000;
    look = 0;
    return;
  }
  if (look_in->working > 0) {  // off to the desk, or on with the work
    target = DESK;
    if (x == DESK) {
      mode = WORK;
      return;
    }
    if (mode != WALK) {
      mode = WALK;
      step_at = now;
    }
  } else if (mode == WORK) {  // all finished
    mode = SIT;
    mode_until = now + 1500;
  }
  if (mode == WALK) {
    if (x == target) {
      mode = SIT;
      mode_until = now + 2000 + rnd(4000);
    } else if (now >= step_at) {
      x += x < target ? D : -D;
      step_at = now + STEP_MS;
    }
    if (target != x) look = target > x ? 1 : -1;
    return;
  }
  if (now >= mode_until) {
    choose_next(now);
  }
  if (now >= look_until) {
    look = (int)rnd(3) - 1;
    look_until = now + 1200 + rnd(2500);
  }
}

// The lid faces us, so its hands show either side of it, taking turns on the keys.
static void draw_laptop(int64_t now, int lx, int ly, int dot, int seed, color_t hand) {
  bool left_down = (now / TYPE_MS + seed) % 2 == 0;
  gfx_fill(lx + 1 * dot, ly + (left_down ? 10 : 9) * dot, 2 * dot, 2 * dot, hand);
  gfx_fill(lx + 13 * dot, ly + (left_down ? 9 : 10) * dot, 2 * dot, 2 * dot, hand);
  gfx_fill(lx + 3 * dot, ly + 8 * dot, 10 * dot, 5 * dot, LAPTOP);
  gfx_fill(lx + 2 * dot, ly + 13 * dot, 12 * dot, dot, LAPTOP_EDGE);
  gfx_fill(lx + 7 * dot, ly + 10 * dot, 2 * dot, dot, (now / 600 + seed) % 2 ? bit_body : LAPTOP_EDGE);
}

void pet_worker(int64_t now, int wx, int wy, int dot, int seed) {
  for (int r = 0; r < 12; r++)
    for (int c = 0; c < COLS; c++) {
      char k = BODY[r][c];
      if (k != '.') gfx_fill(wx + c * dot, wy + r * dot, dot, dot, k == 'd' ? SHADE : bit_body);
    }
  bool blink = (now / 100 + seed * 7) % 40 == 0;
  gfx_fill(wx + 4 * dot, wy + (blink ? 7 : 6) * dot, 2 * dot, (blink ? 1 : 2) * dot, INK);
  gfx_fill(wx + 10 * dot, wy + (blink ? 7 : 6) * dot, 2 * dot, (blink ? 1 : 2) * dot, INK);
  draw_laptop(now, wx, wy, dot, seed, SHADE);
}

// One small mascot for each agent it can't stand in for, wherever it isn't standing.
static void draw_helpers(int64_t now, int count) {
  enum { W = COLS * 2 };
  // from the edges inwards, taking turns
  const int spots[] = {6, STAGE_W - 38, 40, STAGE_W - 72, 74, STAGE_W - 106};
  int used[6], n = 0;
  for (int i = 0, seed = 1; i < 6 && count > 0; i++) {
    bool clear = !(spots[i] + W > x && spots[i] < x + COLS * D) && spots[i] >= 6 && spots[i] + W <= STAGE_W - 6;
    for (int k = 0; k < n && clear; k++)
      if (spots[i] + W > used[k] && spots[i] < used[k] + W) clear = false;
    if (!clear) continue;
    pet_worker(now, spots[i], GROUND - 14 * 2, 2, seed++);
    used[n++] = spots[i];
    count--;
  }
}

void pet_draw(int64_t now, const pet_look_t *p) {
  advance(now, p);
  draw_helpers(now, p->asleep ? p->working : p->working - 1);

  bool napping = mode == NAP, hopping = mode == HOP, walking = mode == WALK, working = mode == WORK;
  bool joyful = hopping || now < banner_until || now < hello_until;
  color_t body = bit_body, shade = SHADE;

  int lift = 0;
  if (hopping) {
    int t = (int)((now - hop_start) % HOP_MS);
    lift = 4 * HOP_UP * t * (HOP_MS - t) / (HOP_MS * HOP_MS);
    lift -= lift % D;  // stays on the sprite's pixel grid
  }

  int rows[12];
  int breath_ms = napping ? 1600 : 900;
  int n = layout(rows, napping, (now / breath_ms) % 2 == 0);
  int feet = napping ? 0 : 2;
  int y0 = GROUND - lift - (n + feet) * D;
  top_y = y0;
  int ry[12];
  memset(ry, 0, sizeof(ry));
  for (int i = 0; i < n; i++) {
    int r = rows[i], y = y0 + i * D;
    ry[r] = y;
    for (int c = 0; c < COLS;) {
      char k = BODY[r][c];
      int e = c;
      while (e < COLS && BODY[r][e] == k) e++;
      if (k != '.') block(c, y, e - c, 1, k == 'd' ? shade : body);
      c = e;
    }
  }

  // feet: when walking, one is up
  if (feet && !working) {
    int fy = y0 + n * D;
    int phase = walking ? (x / D) % 2 : 2;
    if (hopping && lift) {
      block(2, fy, 3, 1, body);
      block(11, fy, 3, 1, body);
    } else {
      block(3, fy, 2, phase == 0 ? 1 : 2, phase == 0 ? shade : body);
      block(11, fy, 2, phase == 1 ? 1 : 2, phase == 1 ? shade : body);
    }
    // arms
    int ay = ry[joyful ? 5 : 8];
    block(0, ay, 1, 2, joyful ? body : shade);
    block(15, ay, 1, 2, joyful ? body : shade);
  }

  // face
  int ey = ry[5];
  int shift = napping || joyful || working ? 0 : look;
  if (now >= blink_end && now >= blink_at) {
    blink_end = now + 130;
    blink_at = now + 2200 + rnd(3500);
  }
  bool blinking = now < blink_end;
  if (napping) {
    block(3, ry[6], 3, 1, INK);
    block(10, ry[6], 3, 1, INK);
  } else if (joyful) {
    for (int side = 0; side < 2; side++) {
      int c = side ? 10 : 3;
      block(c, ry[6], 1, 1, INK);
      block(c + 1, ry[5], 1, 1, INK);
      block(c + 2, ry[6], 1, 1, INK);
    }
    block(2, ry[8], 2, 1, shade);
    block(12, ry[8], 2, 1, shade);
  } else if (blinking) {
    block(4 + shift, ry[7], 2, 1, INK);
    block(10 + shift, ry[7], 2, 1, INK);
  } else if (working) {  // eyes on the screen
    block(4, ry[6], 2, 2, INK);
    block(10, ry[6], 2, 2, INK);
  } else {
    block(4 + shift, ey, 2, 3, INK);
    block(10 + shift, ey, 2, 3, INK);
    block(4 + shift, ey, 1, 1, WHITE);
    block(10 + shift, ey, 1, 1, WHITE);
  }
  // mouth
  if (working) {
    // behind the lid
  } else if (joyful) {
    block(6, ry[8], 4, 1, INK);
    block(7, ry[9], 2, 1, INK);
  } else if (!napping) {
    block(7, ry[9], 2, 1, shade);
  }

  // what it has earned: a headset at 3, an antenna at 5, a crown at 8
  if (p->level >= 3) {
    block(4, ry[1], 8, 1, WHITE);
    block(0, ry[5], 2, 3, WHITE);
    block(14, ry[5], 2, 3, WHITE);
    if (!joyful && !napping && !working) block(12, ry[9], 2, 1, WHITE);
  }
  if (p->scarf && !working && !napping) {  // what it keeps from its first 100 days
    block(1, ry[10], 14, 1, GREEN);
    block(10, ry[10] + D, 2, 1, GREEN);
  }
  if (p->birthday) {  // a party hat, for the day, in place of whatever it has earned up there
    block(5, ry[1] - D, 6, 1, GOLD);
    block(6, ry[1] - 2 * D, 4, 1, WHITE);
    block(7, ry[1] - 3 * D, 2, 1, GOLD);
  } else if (p->level >= 8) {
    block(5, ry[1] - D, 6, 1, GOLD);
    block(5, ry[1] - 2 * D, 1, 1, GOLD);
    block(7, ry[1] - 2 * D, 2, 1, GOLD);
    block(10, ry[1] - 2 * D, 1, 1, GOLD);
  } else if (p->level >= 5) {
    block(7, ry[1] - 2 * D, 2, 2, MUTED);
    block(7, ry[1] - 3 * D, 2, 1, (now / 500) % 2 ? GREEN : WHITE);
  }

  if (working) draw_laptop(now, x, GROUND - 14 * D, D, 0, shade);

  // what floats above it
  int cx = x + COLS * D / 2;
  if (working) {  // its work drifts off
    static const char *const bits[3] = {"1", "0", ";"};
    for (int i = 0; i < 3; i++) {
      int t = (int)((now + i * 800) % 2400);
      int by = top_y + 20 - t * 34 / 2400;
      if (by > 18) gfx_text(&vt16, cx + 46 + i * 8, by, GREEN, bits[(now + i * 800) / 2400 % 3]);
    }
  }
  if (napping) {
    for (int i = 0; i < 2; i++) {
      int t = (int)((now + i * 1400) % 2800);
      int zy = y0 - 2 - t * 22 / 2800;
      if (zy > 18) gfx_text(&sk9, cx + 26 + t * 14 / 2800, zy, i ? MUTED : ORANGE, "Z");
    }
  }
  if (react_start && now - react_start < REACT_MS) {
    int t = (int)(now - react_start);
    int hy = top_y - 14 - t * 16 / REACT_MS;
    if (hy > 18) icon(HEART, cx - 7, hy, 2, WHITE);
  }
  int bx = gfx_inset(22, 12, 6);  // in from the side, or further where a rounded corner needs it
  if (now < banner_until && (now / 300) % 4 != 3) {
    char b[16];
    snprintf(b, sizeof(b), "Level %d", p->level);
    gfx_caps(&sk11, bx, 22, GREEN, b, 1);
  } else if (now < hello_until) {
    gfx_caps(&sk11, bx, 22, GREEN, react_kind == PET_BIRTHDAY ? "Happy birthday" : "Welcome back", 1);
  }
}
