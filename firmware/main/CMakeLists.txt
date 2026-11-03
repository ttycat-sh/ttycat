idf_component_register(
    SRCS "main.c" "board.c" "gfx.c" "fonts.c" "ui.c" "link.c" "sound.c" "pet.c" "game.c" "keyboard.c"
    INCLUDE_DIRS "."
    REQUIRES esp_lcd esp_driver_gpio esp_driver_i2c esp_driver_i2s esp_driver_spi
             esp_driver_usb_serial_jtag esp_timer esp_hw_support json mbedtls nvs_flash)
target_compile_options(${COMPONENT_LIB} PRIVATE -Wno-format-truncation)
