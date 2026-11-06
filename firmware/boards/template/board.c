// A board that does nothing yet: it builds, and shows nothing. Copy this folder and fill it in.
// boards/waveshare-esp32-c5-touch-lcd-2-8 is a complete one to compare with.
#include <stdlib.h>

#include "board.h"
#include "esp_err.h"
#include "esp_heap_caps.h"
#include "esp_log.h"
#include "gfx.h"

// The screen as it stands on the desk, after any rotation, and how many of its pixels make one of the
// picture's. Run tools/board_check.py for these: it picks the zoom from the screen's size in inches.
// The picture, PICTURE_W by PICTURE_H below, has to be within SCR_MIN_W, SCR_MIN_H and SCR_MAX in gfx.h.
#define PANEL_W 240
#define PANEL_H 320
#define ZOOM 1

// How the glass is shaped, in the panel's pixels. Look at it, and at the maker's drawing or datasheet.
// CORNER_RADIUS: if its corners are rounded, how round: the radius of a circle that hides at least as much
//   as the glass does (a corner that's a smooth curve rather than a circle needs the circle that reaches
//   as far along the edges as it does). The screens keep everything clear of them. 0 if square.
// EDGE_INSET: if the glass or a bezel hides some of the panel along every edge, how much. The picture is
//   then that much smaller each side, and centred. 0 if all of it shows.
// tools/preview/gallery.py --board NAME shows every screen as the glass will, before anything's built.
#define CORNER_RADIUS 0
#define EDGE_INSET 0
#define PICTURE_W ((PANEL_W - 2 * EDGE_INSET) / ZOOM)
#define PICTURE_H ((PANEL_H - 2 * EDGE_INSET) / ZOOM)

// Zoomed, the picture goes to the screen a few rows at a time, from this buffer the driver can send from.
#define ROWS_AT_ONCE 8
static uint16_t *rows_out;

void board_begin(void) {
  // TODO: power up, and start the screen and touch. If the screen stands the other way round from how
  // its driver starts, turn it there: esp_lcd_panel_swap_xy and esp_lcd_panel_mirror do it for free.
  if (!gfx_size(PICTURE_W, PICTURE_H)) {
    ESP_LOGE("board", "a %dx%d picture is outside what the screens are laid out for", PICTURE_W, PICTURE_H);
    abort();
  }
  gfx_corner((CORNER_RADIUS > EDGE_INSET ? CORNER_RADIUS - EDGE_INSET : 0) / ZOOM);
  // Unzoomed, the driver sends straight from the picture, so it needs internal RAM it can send from.
  // Zoomed, it sends from rows_out, so the picture can go in PSRAM if the board has some.
  uint32_t caps = ZOOM == 1 ? MALLOC_CAP_DMA | MALLOC_CAP_INTERNAL : MALLOC_CAP_DEFAULT;
  gfx_fb = heap_caps_malloc(SCR_W * SCR_H * 2, caps);
  if (!gfx_fb) {
    ESP_LOGE("board", "no room for the %d KB picture", SCR_W * SCR_H * 2 / 1024);
    abort();
  }
  if (ZOOM > 1) {
    rows_out = heap_caps_malloc(PANEL_W * ROWS_AT_ONCE * ZOOM * 2, MALLOC_CAP_DMA | MALLOC_CAP_INTERNAL);
    ESP_ERROR_CHECK(rows_out ? ESP_OK : ESP_ERR_NO_MEM);
  }
}

void board_backlight(int percent) {
  // TODO: 0 to 100. Or just on, if it can't dim.
}

void board_flush(void) {
  // TODO: send gfx_fb to the screen. It's RGB565, with the bytes already swapped for panels that take
  // the high byte first. Unzoomed, send it as it is. Zoomed, a few rows at a time, like this:
  //
  //   for (int y = 0; y < SCR_H; y += ROWS_AT_ONCE) {
  //     int rows = SCR_H - y < ROWS_AT_ONCE ? SCR_H - y : ROWS_AT_ONCE;
  //     gfx_zoomed(ZOOM, y, rows, rows_out);
  //     esp_lcd_panel_draw_bitmap(panel, EDGE_INSET, EDGE_INSET + y * ZOOM, EDGE_INSET + SCR_W * ZOOM,
  //                               EDGE_INSET + (y + rows) * ZOOM, rows_out);
  //     // and wait for the driver to finish with rows_out before filling it again
  //   }
  //
  // With an EDGE_INSET, the picture starts that far in, as above. If the screen is a little bigger than
  // PANEL_W x PANEL_H, centre it by adding the difference to x and y.
}

bool board_touch(int *x, int *y) {
  // TODO: true while a finger is down, with its position in the picture: the touch chip's position,
  // turned the way the screen was, less EDGE_INSET, then divided by ZOOM, and kept inside the picture.
  return false;
}

// With no speaker, leave these empty. Otherwise see the Waveshare board's speaker.c.
void board_sound_begin(void) {}
void board_chime(void) {}
