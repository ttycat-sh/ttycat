# Boards

One folder per board. A board has to:

- Provide the functions in `../main/board.h`: start up, show the picture, read touch, and optionally chime. The picture can be 170 to 480 pixels wide and 240 to 480 tall, and every screen lays itself out to fit. A screen with more pixels shows it zoomed.
- Say which chip it is and how it's set up, in its `sdkconfig.defaults`.
- List its files, and the parts of ESP-IDF they need, in its `CMakeLists.txt`.
- Say how it reaches the Mac, in the same file: USB straight to the chip, or through a USB-to-serial chip.
- Say how its glass is shaped, if it isn't a plain rectangle, with `CORNER_RADIUS` and `EDGE_INSET` in its `board.c` (see the template). Rounded corners hide whatever's drawn in them, so the board passes their radius to `gfx_corner`, and every screen keeps clear of them. Find the radius in the maker's drawing or datasheet, or measure it on the glass, and round up: too small and things get cut off. The Waveshare AMOLED 2.16 folder is an example.
- Have the memory for the picture: width x height x 2 bytes in one piece, 150 KB at 240x320. Unzoomed it has to be internal RAM, which the original ESP32 doesn't have enough of. Zoomed, it can be PSRAM.

Everything else, the screens, Bit and talking to the Mac, is shared, so a board gets those and their updates for free.

To see whether a board can run it, and how to set it up, run `python3 ../../tools/board_check.py` with its chip and screen (and `--corner` if its corners are rounded). To see every screen at that size, run `python3 ../../tools/preview/gallery.py out.png --size WxH`, adding `--corner R` for rounded corners. Once the board's folder exists, `gallery.py out.png --board NAME` takes the size and corners from its `board.c` and shows each screen as its glass will, and `--cut` paints anything the corners would hide in red.

The folders here are ttycat's own: the official board, a reference board, and the template. A board of your own lives in a folder of your own, outside this repo, so updating ttycat never touches it, and it's never merged in. Copy `template` to a folder named after your board, using lowercase letters, numbers and dashes, and build it from `firmware` with:

    idf.py -B build-NAME -D BOARD_DIR=/path/to/NAME build

Keep the `set(BOARD_API ...)` line at the top of its `CMakeLists.txt`. It says which version of `../main/board.h` the folder was made for, and a release made for another won't build with it. Flash it with `daemon/ttycatd.py flash`, and the board is registered for updates: the Mac app then builds each new release for it with your folder (see the `ttycat-new-board` skill). `ttycatd.py register-board` does the same for a board flashed some other way.

A folder here builds with `-D BOARD=NAME` instead.

The template builds, but shows nothing until it's filled in. The Waveshare folder is a complete example.
