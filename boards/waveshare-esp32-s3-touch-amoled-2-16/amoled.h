// What this board's own files share: the I2C bus, which the touch chip and the speaker's codec are both on.
#pragma once

#include "driver/i2c_master.h"

i2c_master_bus_handle_t board_i2c(void);
