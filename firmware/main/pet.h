// Bit: how it looks and moves. How far it's grown is decided by the daemon (petstate.py).
#pragma once
#include <stdbool.h>
#include <stdint.h>

typedef enum { PET_HEART, PET_RESTED, PET_WELCOME, PET_BIRTHDAY } pet_reaction_t;

typedef struct {
  bool asleep;
  bool birthday;    // a party hat, for the day
  bool scarf;       // what it keeps from its first 100 days
  int level;
  int working;      // agents at work: it works too, and any others get a small one each
} pet_look_t;

// From what the daemon says it has grown. Level 2 at 3, 3 at 12, 4 at 27, 5 at 48.
int pet_level(int32_t total);
// How far through this level, out of `of`.
int pet_progress(int32_t total, int of);

// Where it lives: a stage `width` wide, standing on the line at `ground`, drawn in sprite pixels
// `dot` screen pixels square. The official board's is 240, 112 and 5. Call once, before it's drawn.
void pet_stage(int width, int ground, int dot);
void pet_draw(int64_t now, const pet_look_t *look);
void pet_react(int64_t now, pet_reaction_t what);
// Agents finished `n` turns since it last looked, or it reached a new level.
void pet_reward(int n, bool level_up);
void pet_bounds(int *x, int *y, int *w, int *h);
// The mascot at its laptop, for wherever an agent is working: 16x14 dots of `dot` px.
// `seed` keeps several of them from typing in step.
void pet_worker(int64_t now, int x, int y, int dot, int seed);
