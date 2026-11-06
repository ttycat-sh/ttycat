# The Waveshare ESP32-S3-Touch-AMOLED-2.16: CO5300 AMOLED on QSPI, CST9220 touch, ES8311 speaker output.
idf_component_register(
    SRCS "board.c" "speaker.c"
    PRIV_INCLUDE_DIRS "../../main"
    REQUIRES esp_lcd esp_driver_gpio esp_driver_i2c esp_driver_i2s esp_driver_spi esp_hw_support)
