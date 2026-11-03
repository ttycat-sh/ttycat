// The pet: how it looks and moves. What it needs is decided by the daemon (petstate.py).
#pragma once
#include <stdbool.h>
#include <stdint.h>

typedef enum { PET_NEED_NONE, PET_NEED_SICK, PET_NEED_FOOD, PET_NEED_MESS, PET_NEED_TIRED, PET_NEED_BORED } pet_need_t;
typedef enum { PET_HEART, PET_EAT, PET_SPARKLE, PET_HEAL } pet_reaction_t;

typedef struct {
  bool asleep, sick;
  int level, poops;
  int working;      // agents at work: it works too, and any others get a small one each
  pet_need_t need;  // shown in a bubble; anything but NONE also makes it sad
} pet_look_t;

// Level 2 at 3 finished turns, 3 at 12, 4 at 27, 5 at 48.
int pet_level(int32_t total);
// How far through this level, out of `of`.
int pet_progress(int32_t total, int of);

// Stands on the line at y = 112.
void pet_draw(int64_t now, const pet_look_t *look);
void pet_react(int64_t now, pet_reaction_t what);
// Agents finished `n` turns since it last looked.
void pet_reward(int n, bool level_up);
void pet_bounds(int *x, int *y, int *w, int *h);
// The mascot at its laptop, for wherever an agent is working: 16x14 dots of `dot` px.
// `seed` keeps several of them from typing in step.
void pet_worker(int64_t now, int x, int y, int dot, int seed);
