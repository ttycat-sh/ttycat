# Boards

One folder per board. A board has to:

- Provide the functions in `../main/board.h`: start up, show a 240x320 picture, read touch, and optionally chime.
- Say which chip it is and how it's set up, in its `sdkconfig.defaults`.
- List its files, and the parts of ESP-IDF they need, in its `CMakeLists.txt`.
- Say how it reaches the Mac, in the same file: USB straight to the chip, or through a USB-to-serial chip.
- Have the memory for the picture: 154 KB in one piece. The original ESP32 doesn't.

Everything else, the screens, Bit and talking to the Mac, is shared, so a board gets those and their updates for free.

To add one, copy `template` to a folder named after your board, using letters, numbers and dashes. Build it with:

    idf.py -B build-NAME -D BOARD=NAME build

The template builds, but shows nothing until it's filled in. The Waveshare folder is a complete example.
