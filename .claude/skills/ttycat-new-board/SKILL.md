---
name: ttycat-new-board
description: Run the ttycat firmware on a different ESP32 board with a screen, so it works like the official board. Use when someone has another display board and wants ttycat on it.
---

# Run it on another board

Each board is a folder in `firmware/boards`. It provides the few functions in `firmware/main/board.h`, and gets every screen, Bit and the link to the Mac from the shared code, along with their updates. **Change nothing outside the board's folder.** If it seems you have to, stop and say why.

## First, say whether it'll work
Get the exact board name. Find its chip, screen driver, touch chip and pins from the maker's own wiki or schematic. Don't guess pins. Then tell them plainly:

| Board has | What happens |
|---|---|
| A 240x320 touch screen | The same as the official board |
| A larger or differently turned touch screen | It works if the 240x320 picture fits: rotate it, scale it by whole numbers or centre it in `board_flush`, and do the opposite to touch in `board_touch`. On a 320x240 screen, rotate it |
| A screen narrower or shorter than 240x320, or round | Not supported: the screens are laid out for 240x320 |
| No touch | Not supported: the whole interface is tapping and swiping |
| No speaker | Works, with no chime. Leave `board_sound_begin` and `board_chime` empty |
| A chip without native USB, or a USB-to-serial chip such as a CH340 | Doesn't work yet: `link.c` uses USB Serial/JTAG, and the app looks for `/dev/cu.usbmodem*` |
| Too little internal RAM | The 240x320 picture alone takes 154 KB, and the link's buffers take more. Check the `boot: N bytes free` line in the daemon's log |

Also say that the app can't install or update firmware on it, because its flasher only knows the ESP32-C5, so they'll flash it from here, and rebuild to get updates. Keep the last build that worked.

## Then
1. Copy `firmware/boards/template` to a folder named after the board, in letters, numbers and dashes. Its `README` is in `firmware/boards`, and the Waveshare folder is a complete example.
2. Set the chip, flash size and speed in the folder's `sdkconfig.defaults`. List its files and the parts of ESP-IDF they need in its `CMakeLists.txt`. If it needs a driver from the component registry, add an `idf_component.yml` to the folder.
3. Fill in `board.c`. Allocate `gfx_fb` in `board_begin`, as the template does. The picture is RGB565 with its bytes swapped for panels that take the high byte first.
4. Build: `idf.py -B build-NAME -D BOARD=NAME build`. Adjust the path to ESP-IDF as in `ttycat-flash`.
5. Flash it, following `ttycat-flash`, then check on the real board, step by step, and ask them what they see:
   - The screen shows up, the right way round, with the right colours. Wrong colours usually mean the colour order, inversion or byte order is off.
   - A tap lands where the finger is. Check all four corners, and the Allow and Deny buttons especially: a tap that lands in the wrong place could answer the wrong way.
   - It connects to the Mac, and sessions appear.
   - The chime plays and mute works, if it has a speaker. The backlight dims.
6. Once it works, offer to save it as a pull request, so others with that board can use it.

A build only proves that it compiles. Nothing's proven until you've done these checks on the real board, so don't say it works before then.
