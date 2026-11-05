// What this board's own files share: both resets, the backlight and the speaker's amp sit behind
// a CH32V003 expander on the I2C bus.
#pragma once
#include <stdbool.h>

#include "driver/i2c_master.h"

i2c_master_bus_handle_t board_i2c(void);
bool board_exio_set(int line, bool high);

enum { EXIO_TOUCH_RST = 0, EXIO_LCD_RST = 1, EXIO_AMP = 3 };
