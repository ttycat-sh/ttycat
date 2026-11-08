# List your board's .c files, and the parts of ESP-IDF they use after REQUIRES (see the Waveshare board's).
set(BOARD_API 1)  # the board interface this folder was made for: see BOARD_API in main/board.h
idf_build_get_property(ttycat PROJECT_DIR)  # the core's own files, wherever this folder is
idf_component_register(
    SRCS "board.c"
    PRIV_INCLUDE_DIRS "${ttycat}/main")
