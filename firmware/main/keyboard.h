// The on-screen keyboard: types into a caller's string. Keys act when the finger lifts,
// where it ended up, so a press can slide to the right key before it counts.
#pragma once
#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

typedef enum { KEYBOARD_TYPING, KEYBOARD_DONE, KEYBOARD_CANCELLED } keyboard_result_t;

// `text` is edited in place, and put back as it was on Cancel. `prompt` is copied.
void keyboard_open(char *text, size_t cap, const char *prompt);
void keyboard_draw(int64_t now, bool finger_down, int x, int y);
keyboard_result_t keyboard_release(int x, int y, int64_t now);
