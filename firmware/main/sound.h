// The attention chime on the board's speaker (ES8311, NS4150B amp on EXIO3).
#pragma once
#include <stdbool.h>

void sound_begin(void);
void sound_chime(void);
bool sound_muted(void);
void sound_set_muted(bool muted);
