# The Waveshare ESP32-C5-Touch-LCD-2.8: ST7789 panel, CST3530 touch, ES8311 speaker.
set(BOARD_API 1)  # the board interface this folder was made for: see BOARD_API in main/board.h
idf_build_get_property(ttycat PROJECT_DIR)  # the core's own files, wherever this folder is
idf_component_register(
    SRCS "board.c" "speaker.c"
    PRIV_INCLUDE_DIRS "${ttycat}/main"
    REQUIRES esp_lcd esp_driver_gpio esp_driver_i2c esp_driver_i2s esp_driver_spi esp_hw_support)
