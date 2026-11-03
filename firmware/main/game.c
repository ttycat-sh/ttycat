#include "game.h"

#include <stdio.h>

#include "esp_random.h"
#include "fonts.h"
#include "gfx.h"

#define GREEN RGB(0x3FD38A)
#define ORANGE accent_color
#define WHITE RGB(0xFFFFFF)
#define BLACK RGB(0x000000)
#define MUTED RGB(0x9A9A9A)
#define LINE RGB(0x262626)

enum {
  READY_MS = 1500,
  PLAY_MS = 20000,
  BUGS = 5,
  SIZE = 20,
  REACH = 24,      // a finger isn't a pixel: from the bug's centre
  SPLAT_MS = 280,
  FIELD_TOP = 40,
  FIELD_BOTTOM = 312,
};

typedef struct {
  bool on, splat;
  int x0, y0, vx, vy;      // pixels and pixels per second
  int64_t born, dies, splat_at;
} bug_t;

static const char *const BUG_A[10] = {"..........", "..w....w..", "...w..w...", "..gggggg..", "w.gwggwg.w",
                                      ".wggggggw.", "..gggggg..", "w.gggggg.w", ".w..gg..w.", ".........."};
static const char *const BUG_B[10] = {"..........", "...w..w...", "...w..w...", "w.gggggg.w", ".wgwggwgw.",
                                      "..gggggg..", "w.gggggg.w", ".wgggggg.w", "....gg....", ".........."};
static const char *const SPLAT[10] = {"o...o....o", "..o...o...", ".o.ooo..o.", "...oooo...", "o.oooooo.o",
                                      "..ooooo...", ".o.ooo.o..", "...o...o..", "o.....o...", "...o.....o"};

static bug_t bugs[BUGS];
static int64_t began, next_spawn;
static int score;
static bool bot;

static uint32_t rnd(uint32_t n) { return esp_random() % n; }

int game_score(void) { return score; }

void game_begin(int64_t now, bool use_bot) {
  for (int i = 0; i < BUGS; i++) bugs[i].on = false;
  began = now;
  next_spawn = now + READY_MS;
  score = 0;
  bot = use_bot;
}

static int clamp(int v, int lo, int hi) { return v < lo ? lo : v > hi ? hi : v; }
static int bug_x(const bug_t *b, int64_t now) { return clamp(b->x0 + (int)(b->vx * (now - b->born) / 1000), 4, 240 - SIZE - 4); }
static int bug_y(const bug_t *b, int64_t now) {
  return clamp(b->y0 + (int)(b->vy * (now - b->born) / 1000), FIELD_TOP, FIELD_BOTTOM - SIZE);
}

static void spawn(int64_t now) {
  for (int i = 0; i < BUGS; i++) {
    if (bugs[i].on) continue;
    int played = (int)(now - began - READY_MS);
    bug_t *b = &bugs[i];
    b->on = true;
    b->splat = false;
    b->x0 = 4 + (int)rnd(240 - SIZE - 8);
    b->y0 = FIELD_TOP + (int)rnd(FIELD_BOTTOM - FIELD_TOP - SIZE);
    int speed = 12 + played / 500;  // they get quicker
    b->vx = (int)rnd((uint32_t)speed * 2 + 1) - speed;
    b->vy = (int)rnd((uint32_t)speed * 2 + 1) - speed;
    b->born = now;
    b->dies = now + 1800 - played / 25;
    return;
  }
}

void game_touch(int x, int y, int64_t now) {
  if (now - began < READY_MS) return;
  bug_t *hit = NULL;
  int best = 0x7FFFFFFF;
  for (int i = 0; i < BUGS; i++) {
    bug_t *b = &bugs[i];
    if (!b->on || b->splat) continue;
    int dx = bug_x(b, now) + SIZE / 2 - x, dy = bug_y(b, now) + SIZE / 2 - y;
    if (dx < -REACH || dx > REACH || dy < -REACH || dy > REACH) continue;
    int d = dx * dx + dy * dy;
    if (d < best) {
      best = d;
      hit = b;
    }
  }
  if (!hit) return;
  // it stops where it was squashed
  hit->x0 = bug_x(hit, now);
  hit->y0 = bug_y(hit, now);
  hit->vx = hit->vy = 0;
  hit->splat = true;
  hit->splat_at = now;
  score++;
}

bool game_draw(int64_t now) {
  int played = (int)(now - began - READY_MS);
  char text[16];
  snprintf(text, sizeof(text), "Bugs %d", score);
  gfx_caps(&sk11, 6, 6, WHITE, text, 1);
  if (played < 0) {
    gfx_center(&ps24, 0, SCR_W, 140, ORANGE, "READY", 0);
    gfx_center(&vt18, 0, SCR_W, 180, MUTED, "tap the bugs", 0);
    return false;
  }
  if (played >= PLAY_MS) return true;
  snprintf(text, sizeof(text), "%ds", (PLAY_MS - played + 999) / 1000);
  gfx_right(&vt18, 234, 2, ORANGE, text);
  int bar = 228 * (PLAY_MS - played) / PLAY_MS;
  gfx_fill(6, 26, 228, 4, LINE);
  gfx_fill(6, 26, bar, 4, played > PLAY_MS - 5000 ? WHITE : ORANGE);

  if (now >= next_spawn) {
    spawn(now);
    next_spawn = now + 650 - played / 50;
  }
  bool step = (now / 150) % 2;
  for (int i = 0; i < BUGS; i++) {
    bug_t *b = &bugs[i];
    if (!b->on) continue;
    if (b->splat ? now - b->splat_at > SPLAT_MS : now >= b->dies) {
      b->on = false;
      continue;
    }
    if (bot && !b->splat && now - b->born > 250) game_touch(bug_x(b, now) + SIZE / 2, bug_y(b, now) + SIZE / 2, now);
    gfx_sprite(b->splat ? SPLAT : step ? BUG_A : BUG_B, bug_x(b, now), bug_y(b, now), 2, 0, BLACK, ORANGE, WHITE, GREEN);
  }
  return false;
}
