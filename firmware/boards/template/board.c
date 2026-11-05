// A board that does nothing yet: it builds, and shows nothing. Copy this folder and fill it in.
// boards/waveshare-esp32-c5-touch-lcd-2-8 is a complete one to compare with.
#include <stdlib.h>

#include "board.h"
#include "esp_err.h"
#include "esp_heap_caps.h"
#include "gfx.h"

void board_begin(void) {
  // TODO: power up, start the screen and touch.
  // Internal RAM a screen driver can send from directly. The picture is always 240x320.
  gfx_fb = heap_caps_malloc(SCR_W * SCR_H * 2, MALLOC_CAP_DMA | MALLOC_CAP_INTERNAL);
  ESP_ERROR_CHECK(gfx_fb ? ESP_OK : ESP_ERR_NO_MEM);
}

void board_backlight(int percent) {
  // TODO: 0 to 100. Or just on, if it can't dim.
}

void board_flush(void) {
  // TODO: send gfx_fb to the screen. It's RGB565, with the bytes already swapped for panels that take
  // the high byte first. On a screen that isn't 240x320 portrait, this is where to rotate or centre it.
}

bool board_touch(int *x, int *y) {
  // TODO: true while a finger is down, with its position in the 240x320 picture.
  return false;
}

// With no speaker, leave these empty. Otherwise see the Waveshare board's speaker.c.
void board_sound_begin(void) {}
void board_chime(void) {}
