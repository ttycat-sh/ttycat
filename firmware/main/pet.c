#include "pet.h"

#include <stdio.h>
#include <string.h>

#include "esp_random.h"
#include "esp_timer.h"
#include "fonts.h"
#include "gfx.h"

#define ORANGE accent_color
#define SHADE bit_shade
#define SICK_BODY RGB(0xA8B04A)
#define SICK_SHADE RGB(0x737A2E)
#define INK RGB(0x0B0B0B)
#define WHITE RGB(0xFFFFFF)
#define GREEN RGB(0x3FD38A)
#define MUTED RGB(0x9A9A9A)
#define GOLD RGB(0xFFD34D)
#define BROWN RGB(0x8A5A2B)
#define RED RGB(0xE5484D)
#define LAPTOP RGB(0xC4C4C4)
#define LAPTOP_EDGE RGB(0x7A7A7A)

enum {
  D = 5,           // screen pixels per sprite pixel
  COLS = 16,
  GROUND = 112,    // the line it stands on
  LEFT = 6,
  RIGHT = 240 - COLS * D - 6,
  HOP_MS = 420,
  HOP_UP = 3 * D,
  STEP_MS = 170,
  EAT_MS = 1400,
  REACT_MS = 1300,
  DESK = LEFT + 15 * D,  // where it works: the middle of the stage
  TYPE_MS = 170,
};

typedef enum { SIT, WALK, HOP, NAP, EAT, WORK } pet_mode_t;

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
static icon_t FOOD = {"...o...", ".oo.oo.", "ooooooo", "ooooooo", ".ooooo.", "..ooo.."};
static icon_t POOP = {"...o...", "..ooo..", ".ooooo.", ".ooooo.", "ooooooo", "ooooooo"};
static icon_t CROSS = {"..ooo..", "..ooo..", "ooooooo", "ooooooo", "..ooo..", "..ooo.."};
static icon_t ZZZ = {"ooooo..", "...o...", "..o....", ".o.....", "ooooo..", "......."};
static icon_t BORED = {".oooo..", "o....o.", "...oo..", "..o....", ".......", "..o...."};
static icon_t SPARK = {"...o...", "..o.o..", ".o...o.", "..o.o..", "...o...", "......."};

static pet_mode_t mode = SIT;
static int x = LEFT + 14 * D;  // always a whole sprite pixel from LEFT, or it never lands on a target
static int target;
static int64_t mode_until, step_at, hop_start, eat_start;
static int hops;
static int64_t blink_at, blink_end, look_until;
static int look;
static int64_t react_start, plus_start, banner_until;
static pet_reaction_t react_kind;
static int plus_n;
static int top_y = GROUND - 14 * D;

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
  if (what == PET_EAT) {
    mode = EAT;
    eat_start = now;
    react_start = 0;
  } else {
    start_hops(now, 2);
  }
}

void pet_reward(int n, bool level_up) {
  int64_t now = esp_timer_get_time() / 1000;
  start_hops(now, n > 5 ? 5 : n < 1 ? 1 : n);
  plus_start = now;
  plus_n = n;
  if (level_up) banner_until = now + 4000;
}

void pet_bounds(int *bx, int *by, int *bw, int *bh) {
  *bx = x - 8;
  *by = top_y - 8;
  *bw = COLS * D + 16;
  *bh = GROUND - top_y + 12;
}

static void choose_next(int64_t now, bool sad) {
  if (rnd(100) < (sad ? 15u : 45u)) {  // a sad pet mostly sits
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
  bool sad = look_in->need != PET_NEED_NONE;
  if (mode == HOP) {
    if (now - hop_start >= HOP_MS * hops) {
      mode = SIT;
      mode_until = now + 1500;
    }
    return;
  }
  if (mode == EAT) {
    if (now - eat_start >= EAT_MS) {
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
      step_at = now + (sad ? STEP_MS * 2 : STEP_MS);
    }
    if (target != x) look = target > x ? 1 : -1;
    return;
  }
  if (now >= mode_until) {
    if (look_in->sick) mode_until = now + 3000;  // too ill to wander
    else choose_next(now, sad);
  }
  if (now >= look_until) {
    look = (int)rnd(3) - 1;
    look_until = now + 1200 + rnd(2500);
  }
}

static void draw_poops(int count) {
  static const int spots[3] = {16, 204, 110};
  for (int i = 0; i < count && i < 3; i++) icon(POOP, spots[i], GROUND - 18, 3, BROWN);
}

static void draw_bubble(int head_y, pet_need_t need) {
  icon_t *what = need == PET_NEED_SICK ? &CROSS : need == PET_NEED_FOOD ? &FOOD : need == PET_NEED_MESS ? &POOP
               : need == PET_NEED_TIRED ? &ZZZ : &BORED;
  color_t c = need == PET_NEED_SICK ? RED : need == PET_NEED_FOOD ? ORANGE : need == PET_NEED_MESS ? BROWN : INK;
  int bx = x + COLS * D - 8;
  if (bx + 22 > 238) bx = x - 14;
  int by = head_y - 18;
  if (by < 18) by = 18;
  gfx_fill(bx + 2, by, 18, 18, WHITE);
  gfx_fill(bx, by + 2, 22, 14, WHITE);
  icon(*what, bx + 4, by + 3, 2, c);
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
  static const int spots[] = {6, 202, 40, 168, 74, 134};
  enum { W = COLS * 2 };
  for (int i = 0, seed = 1; i < 6 && count > 0; i++) {
    if (spots[i] + W > x && spots[i] < x + COLS * D) continue;
    pet_worker(now, spots[i], GROUND - 14 * 2, 2, seed++);
    count--;
  }
}

void pet_draw(int64_t now, const pet_look_t *p) {
  advance(now, p);
  draw_poops(p->poops);
  draw_helpers(now, p->asleep ? p->working : p->working - 1);

  bool napping = mode == NAP, hopping = mode == HOP, walking = mode == WALK, eating = mode == EAT, working = mode == WORK;
  bool joyful = hopping || now < banner_until;
  bool sad = !joyful && !eating && p->need != PET_NEED_NONE;
  color_t body = p->sick ? SICK_BODY : bit_body, shade = p->sick ? SICK_SHADE : SHADE;

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
  int shift = napping || joyful || eating || working ? 0 : look;
  if (now >= blink_end && now >= blink_at) {
    blink_end = now + 130;
    blink_at = now + 2200 + rnd(3500);
  }
  bool blinking = now < blink_end;
  if (napping) {
    block(3, ry[6], 3, 1, INK);
    block(10, ry[6], 3, 1, INK);
  } else if (joyful || eating) {
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
  } else if (sad) {  // heavy lids
    block(4 + shift, ry[6], 2, 2, INK);
    block(10 + shift, ry[6], 2, 2, INK);
    block(3 + shift, ry[5], 3, 1, shade);
    block(10 + shift, ry[5], 3, 1, shade);
  } else {
    block(4 + shift, ey, 2, 3, INK);
    block(10 + shift, ey, 2, 3, INK);
    block(4 + shift, ey, 1, 1, WHITE);
    block(10 + shift, ey, 1, 1, WHITE);
  }
  // mouth
  if (working) {
    // behind the lid
  } else if (eating) {
    bool open = (now - eat_start) / 170 % 2 == 0;
    block(6, ry[8], 4, open ? 2 : 1, INK);
  } else if (joyful) {
    block(6, ry[8], 4, 1, INK);
    block(7, ry[9], 2, 1, INK);
  } else if (sad) {
    block(7, ry[8], 2, 1, INK);
    block(6, ry[9], 1, 1, INK);
    block(9, ry[9], 1, 1, INK);
  } else if (!napping) {
    block(7, ry[9], 2, 1, shade);
  }

  // what it has earned: a headset at 3, an antenna at 5, a crown at 8
  if (p->level >= 3) {
    block(4, ry[1], 8, 1, WHITE);
    block(0, ry[5], 2, 3, WHITE);
    block(14, ry[5], 2, 3, WHITE);
    if (!joyful && !napping && !sad && !eating && !working) block(12, ry[9], 2, 1, WHITE);
  }
  if (p->level >= 8) {
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
  if (eating) {  // the bites get smaller
    int left = EAT_MS - (int)(now - eat_start);
    int dot = left > EAT_MS * 2 / 3 ? 3 : left > EAT_MS / 3 ? 2 : 1;
    icon(FOOD, cx - 7 * dot / 2, top_y - 4 - 6 * dot, dot, GREEN);
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
    if (hy > 18) {
      if (react_kind == PET_HEAL) icon(CROSS, cx - 7, hy, 2, GREEN);
      else if (react_kind == PET_SPARKLE) {
        icon(SPARK, cx - 26, hy + 8, 2, WHITE);
        icon(SPARK, cx + 12, hy, 2, WHITE);
      } else icon(HEART, cx - 7, hy, 2, WHITE);
    }
  }
  if (plus_start && now - plus_start < 1800 && plus_n > 0) {
    char plus[12];
    snprintf(plus, sizeof(plus), "+%d", plus_n);
    int py = top_y - 16 - (int)((now - plus_start) * 10 / 1800);
    if (py < 18) py = 18;
    gfx_text(&vt18, cx + 22, py, GREEN, plus);
  }
  if (now < banner_until && (now / 300) % 4 != 3) {
    char b[16];
    snprintf(b, sizeof(b), "Level %d", p->level);
    gfx_caps(&sk11, 6, 22, GREEN, b, 1);
  } else if (p->need != PET_NEED_NONE && !napping && !hopping && !eating) {
    draw_bubble(y0, p->need);
  }
}
