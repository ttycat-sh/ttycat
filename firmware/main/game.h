// Bug Hunt: squash bugs for 20 seconds. Played from the pet's care screen.
#pragma once
#include <stdbool.h>
#include <stdint.h>

// `bot` squashes by itself, so tools can test a whole game without a finger.
void game_begin(int64_t now, bool bot);
// One frame. True once time is up.
bool game_draw(int64_t now);
void game_touch(int x, int y, int64_t now);
int game_score(void);
