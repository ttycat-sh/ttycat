// All the firmware needs from a board. Each board implements this in its own folder under boards/,
// and nothing outside that folder knows which board it's running on. See boards/README.md.
#pragma once
#include <stdbool.h>

// Powers everything up, starts the screen and touch, sets the picture's size with gfx_size, and
// allocates gfx_fb for it. Called once, first.
void board_begin(void);
void board_backlight(int percent);
// Puts gfx_fb on the screen, as cheaply as it can: this runs about 60 times a second.
void board_flush(void);
// True while a finger is down, with its position in the picture (SCR_W x SCR_H).
bool board_touch(int *x, int *y);

// The chime when an agent needs you. A board with no speaker leaves both of these empty.
void board_sound_begin(void);
void board_chime(void);  // returns at once, without waiting for the sound to finish
