// Whether the chime plays. What makes the sound is the board's: board_chime.
#pragma once
#include <stdbool.h>

void sound_begin(void);
void sound_chime(void);
bool sound_muted(void);
void sound_set_muted(bool muted);
