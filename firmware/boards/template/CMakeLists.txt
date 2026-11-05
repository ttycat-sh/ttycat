# List your board's .c files, and the parts of ESP-IDF they use after REQUIRES (see the Waveshare board's).
idf_component_register(
    SRCS "board.c"
    PRIV_INCLUDE_DIRS "../../main")
