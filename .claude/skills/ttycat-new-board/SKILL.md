---
name: ttycat-new-board
description: Run the ttycat firmware on a different ESP32 board with a screen. Use when someone has another display board and wants ttycat on it.
---

# Run it on another board

Everything specific to the hardware is in `firmware/main/board.c`, `board.h` and `sound.c`, and the chip is set in `firmware/sdkconfig.defaults`.

1. Get the exact board name. Find its pins, screen driver and touch chip from the maker's own wiki or schematic. Don't guess pins.
2. Say what will and won't work before starting:
   - A 240x320 screen should need only `board.c`. Other sizes mean redoing the layouts in `ui.c`, which uses fixed positions, so it's a much bigger job.
   - It needs a chip with native USB (ESP32-S3, C3, C5 or C6), because `link.c` uses USB Serial/JTAG and the app looks for `/dev/cu.usbmodem*`. A board with a USB-to-serial chip such as a CH340 needs changes to both, and doesn't work with the app as it stands.
   - No speaker: make `sound.c` do nothing.
   - The app can't update it or put back its old firmware, because its flasher only knows the ESP32-C5. Keep a copy of what works.
3. Replace `board.c` behind the same functions in `board.h`.
4. Set the chip, flash size and speed in `sdkconfig.defaults`, then `idf.py set-target CHIP build`. A build only shows that it compiles: nothing's proven until the screen and touch work on the real board.
5. Flash it, following `ttycat-flash`.
