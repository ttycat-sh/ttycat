---
name: ttycat-new-board
description: Run the ttycat firmware on a different ESP32 board with a touch screen, so it works like the official board. Use when someone has another display board, even with only a shop link, and wants ttycat on it.
---

# Run it on another board

Each board is a folder in `firmware/boards`. It provides the few functions in `firmware/main/board.h`, and gets every screen, Bit and the link to the Mac from the shared code, along with their updates. The person may not be a programmer: tell them what you're doing in plain words, and ask them only what you can't find out yourself.

**Change nothing outside the board's folder.** If it seems you have to, because the shared screens don't handle something about this board, stop and ask. Say what and where. A fix there has to be general: it works for any board with the same trait, nothing in the shared code checks which board it is, and every other board stays exactly the same. Prove that with `npm run verify-board` in the website repo (`TTYCAT_CORE=path/to/ttycat` if it's elsewhere): every frame must match.

`docs/ports/` has the full story of an earlier port, with what went wrong. Read it if something here isn't enough.

## 1. Find out exactly what the board is

Get the exact board name. Shop pages often don't give it, or the maker. If all they have is a link, plug the board in and ask it:
- **Its boot messages.** With ttycat running, a board's own firmware usually prints its name and parts as it starts, and the daemon logs what it hears: `grep "board:" ~/.ttycat/ttycatd.log | tail -80`. That's often the quickest answer.
- **Its chip.** `esptool.py --port PORT flash_id` only reads: the chip, its flash and PSRAM. Then search for the chip with the screen's size and resolution.

Then find the details, from these, best first. Don't guess pins.
1. **The maker's board support package (BSP)** on components.espressif.com. One C file usually holds the pins, the panel's start-up commands, its orientation and how touch is turned. Download it to read: it's never built.
2. **The maker's repository.** Clone it rather than fetching its pages: examples, the schematic, and the mechanical drawing (DXF or PDF) for the glass's shape.
3. **The maker's wiki.** Usually just the pins.

Note down: the chip, flash size, PSRAM and its mode (octal or quad), the panel's driver and how it's wired, its resolution and diagonal, the glass's shape, the touch chip and how it's turned, how brightness is set, any power chip that has to switch the screen on, any speaker and its amp, and whether USB goes straight to the chip.

**The glass's shape matters as much as the panel.** Many small screens, AMOLEDs especially, have rounded corners, and whatever's drawn in them is lost. Find the radius in the mechanical drawing, the panel's datasheet or the maker's example code. Measure it in the panel's pixels: millimetres times pixels per millimetre of the active area. If the corner is a smooth curve rather than a circle, use the circle that reaches as far along the edges, and round up: too small and things still get cut off. If you can't find it, ask them to hold a ruler to the glass, and say it's a measurement. Do the same if a bezel hides part of the panel along its edges.

## 2. Say whether it'll work

Ask how they'll stand it on the desk, if the screen isn't square. Then run the check and tell them plainly what it says:

    python3 tools/board_check.py --chip esp32s3 --screen 480x480 --inches 2.16 --touch --psram 8 --corner 96 --speaker

It checks everything ttycat needs, and picks how to fit the screen:

- **A touch screen.** The whole interface is tapping and swiping, so a board without one can't run it.
- **A picture 170 to 480 pixels wide and 240 to 480 tall.** The screens lay themselves out to fit, from narrow sticks to square and landscape screens, and Bit gets bigger or smaller with them. A screen with more pixels shows a smaller picture with each pixel 2x2 or more, so Bit and the text are as easy to read as on the official board. A screen can also turn a quarter. Round screens aren't supported yet.
- **Memory for the picture.** Unzoomed, it has to fit in internal RAM, so the original ESP32 (most "Cheap Yellow Display" boards) can't run it. Zoomed, it can go in PSRAM.
- **USB to the Mac.** Most newer chips have it built in. Through a USB-to-serial chip such as a CH340 should work too, but nobody has tried it on a real board yet, so say so.
- **A speaker isn't needed.** Without one there's no chime, and everything else works.

If it says no, stop and say why. Don't work around it.

Then show them every screen as their glass will show it, before anything's built. With rounded corners, give the picture's corner radius from the check, and `--cut` marks in red anything the corners would hide. It should say "hidden by the corners: nothing":

    python3 tools/preview/gallery.py out.png --size 240x240 --corner 48 --cut

Also tell them: the app won't update this board, because the firmware it carries is for the official board. They'll get updates by rebuilding from the latest source here. If the app ever says the firmware doesn't match, rebuilding fixes it.

## 3. Save what's on the board

Before the first flash, save the board's own firmware. Nothing else can put it back: the app can only restore the official board.

    mkdir -p ~/ttycat-backups
    esptool.py --port PORT read_flash 0 FLASH_SIZE ~/ttycat-backups/NAME-factory.bin

`FLASH_SIZE` is what `flash_id` said, such as `0x1000000` for 16 MB. It takes a minute or two. Tell them it's there, and how to put it back: `esptool.py --port PORT write_flash 0 ~/ttycat-backups/NAME-factory.bin`. Keep each ttycat build that works next to it.

## 4. Make the board's folder

ESP-IDF has to be in the shell for `idf.py` and `esptool.py`. Look for it with `ls ~/esp/*/export.sh`, then run `. ~/esp/esp-idf-vX/export.sh` in the same command as whatever needs it. If it isn't installed, say so: it's Espressif's free toolkit, and the install takes a while.

1. Copy `firmware/boards/template` to a folder named after the board, in letters, numbers and dashes. The boards `README` is in `firmware/boards`. The two Waveshare folders are complete examples: an LCD with square corners, and an AMOLED with rounded corners and zoom.
2. Set the chip, flash size, PSRAM mode and speed in the folder's `sdkconfig.defaults`. List its files and the parts of ESP-IDF they need in its `CMakeLists.txt`. If it needs drivers from the component registry, list them in an `idf_component.yml` in the folder.
3. Fill in `board.c`:
   - **Size and shape.** Set `PANEL_W`, `PANEL_H`, `ZOOM`, `CORNER_RADIUS` and `EDGE_INSET` to what the check said, with a comment saying where the radius came from. The template sets the picture's size from them, allocates it, and tells every screen to keep clear of the corners.
   - **Drawing.** The picture is RGB565 with its bytes swapped for panels that take the high byte first. Zoomed, send it with `gfx_zoomed`, as the template shows. Only send the rows that changed, as the official board does: it keeps the board quick.
   - **Turning.** Turn the panel with `esp_lcd_panel_swap_xy` and `esp_lcd_panel_mirror`, and turn touch the same way. Some AMOLED drivers, such as the CO5300, may ignore those, so check on the glass before relying on a quarter turn.
   - **Touch.** Positions are in the picture: turn them as the panel is turned, then divide by `ZOOM`. If the touch chip's read fails, report no finger: a stale position must never count as a tap.
   - **Brightness.** `board_backlight` gets 0 to 100. An AMOLED has no backlight: set the panel's own brightness command instead, and keep the screen dark until the first picture is on it.
   - **Sound.** With no speaker, leave `board_sound_begin` and `board_chime` empty.

   Then `python3 tools/preview/gallery.py out.png --board NAME --cut` shows every screen with the folder's own size and corners. If something is still cut off, that's for the shared screens, not something to move for one board: see the top.
4. Leave a `README.md` in the folder: the board's name and maker, where each detail came from, and what's been checked on the real board. The next person with this board starts there.
5. Build: `idf.py -B build-NAME -D BOARD=NAME build`.

## 5. Put it on the board

Follow `ttycat-flash`, with the board's port named, as it says for a board that's never run ttycat.

## 6. Check it

**What you can check yourself**, without anyone at the board:
- `python3 daemon/ttycatd.py status` shows `connected`, the build's name in `fw`, the board's folder name, and `approves: false`. That last one is right: a new build has to be allowed in Setup before it can approve.
- `~/.ttycat/ttycatd.log` has the board's start-up: `boot: N bytes free`, and any errors from its drivers.
- `python3 daemon/ttycatd.py shot out.png` saves the picture the board is drawing. Compare it with the gallery: `goto pet`, `goto overview` and `goto queue` move between screens. Never use `tap` while something's waiting for an answer (rule 5).
- After two minutes untouched on Bit's screen, the status says `dim`.

**What only a person can check.** `shot` is the picture in memory, never the glass, and reading a panel back almost never works, so don't try. Ask them, one at a time:
- Does the screen light up, the right way round, with the right colours? Orange, not blue: wrong colours usually mean the colour order, inversion or byte order is off.
- Is anything cut off, corner by corner? The ends of the header at the top, the footer, and the bottom buttons. A cut-off corner means `CORNER_RADIUS` is too small.
- Does a tap land where the finger is? All four corners, then Deny and "On Mac" on a real prompt. A tap that lands in the wrong place could answer the wrong way.
- Then, if they want to approve from the board, have them turn on **It can approve prompts** in Setup, and check that Allow appears and works.
- Does the chime play, and mute stop it, if it has a speaker? Does the screen look dimmer after two minutes on Bit's screen, and does a touch bring it back?

A build only proves that it compiles. Don't say it works until they've seen it.

On an AMOLED, tell them a picture that stays put for months can burn in, and Bit's home screen is mostly still.

## 7. Share it

Once it works, offer to save it as a pull request, so others with that board can use it. Only the board's folder should be in it, unless a shared fix was agreed.
