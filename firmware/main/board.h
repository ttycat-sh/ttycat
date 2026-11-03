// The Waveshare ESP32-C5-Touch-LCD-2.8: ST7789 panel, CST3530 touch, and the
// CH32V003 expander that owns both resets, the backlight and the speaker's amp.
#pragma once
#include <stdbool.h>
#include <stdint.h>

#include "driver/i2c_master.h"

void board_begin(void);
i2c_master_bus_handle_t board_i2c(void);
bool board_exio_set(int line, bool high);
void board_backlight(int percent);
// Sends only the rows that changed since the last flush.
void board_flush(void);
// True while a finger is down, with its position.
bool board_touch(int *x, int *y);

enum { EXIO_TOUCH_RST = 0, EXIO_LCD_RST = 1, EXIO_AMP = 3 };
