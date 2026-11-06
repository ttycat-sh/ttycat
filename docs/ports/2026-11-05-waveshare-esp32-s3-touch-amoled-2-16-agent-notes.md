# Port notes: Waveshare ESP32-S3-Touch-AMOLED-2.16

Porting ttycat to the board at a shop link, following `.claude/skills/ttycat-new-board`, 2026-11-05.
The person was away, so questions the skill says to ask are written down here, and I carried on with my best judgement.

(The summary at the end is where things stand.)

## 1. Which board is it?

- **The shop page didn't say.** Fetching it gave about 1 MB of mostly scripts. The only product details I got were a summary: "ESP32-S3 … 2.16 Zoll AMOLED Touchscreen 480 × 480 … two microphones, 6-axis IMU, RTC", seller "Bolin Electronic". There was no brand, model name or wiki link.
- **What worked was asking the board itself, then searching.** `esptool.py flash_id` (read-only) said ESP32-S3 (QFN56) rev v0.2, embedded 8 MB PSRAM, 16 MB flash, USB-Serial/JTAG, and USB showed Espressif VID 0x303A / PID 0x1001. A web search for "ESP32-S3 2.16 inch AMOLED 480x480 IMU RTC" found the **Waveshare ESP32-S3-Touch-AMOLED-2.16** (wiki: https://docs.waveshare.com/ESP32-S3-Touch-AMOLED-2.16). The chip, memory, screen and extras all match. It's still an inference from the specs: no marking on the board was checked.
  - *Question for the person:* does the board's silkscreen say "ESP32-S3-Touch-AMOLED-2.16"? (Waveshare also sells an ESP32-C6 board with the same 2.16" panel. Ours is definitely an S3, because esptool read the chip.)
- *Skill:* "Get the exact board name" assumes the person knows it. A store link often doesn't say. Suggest: "If they only have a shop link, read the chip with `esptool.py flash_id` (it only reads), then search for the chip plus the screen size and resolution."

## 2. Pins and parts

- The wiki's pin tables give the pins, but not the panel's start-up commands, its orientation or the touch protocol. A fetch agent couldn't reach the GitHub source pages either.
- **What worked:** downloading Waveshare's board support package straight from the component registry (`waveshare/esp32_s3_touch_amoled_2_16` 2.0.1, a zip from `components.espressif.com/api/components/...`) and cloning `github.com/waveshareteam/ESP32-S3-Touch-AMOLED-2.16` (which has the schematic PDF), each into its own folder under /tmp, read only and never built. The BSP's `esp32_s3_touch_amoled_2_16.c` had everything:
  - Panel: CO5300 over QSPI. CS 12, SCLK 38, D0–D3 4/5/6/7, RESET 39. Waveshare's init sequence, MADCTL 0xA0, RGB565, brightness by command 0x51, no backlight pin. CO5300 areas must start on an even pixel and end on an odd one (the BSP has a rounder for this).
  - Touch: CST9220, driven by `waveshare/esp_lcd_touch_cst9217` at 0x5A. I2C SDA 15, SCL 14. INT 11, RST 40. Waveshare turns it with swap_xy=1, mirror_y=1.
  - Audio: ES8311 codec, I2S MCLK 42, BCLK 9, WS 45, DOUT 8, DIN 10. NS4150B amp enabled by GPIO46.
- The schematic (rendered with `pdftoppm`, then cropped) showed:
  - The AMOLED runs on VCC3V3 directly, so the AXP2101 power chip doesn't need setting up.
  - The amp goes to **P10, a 2-pin speaker connector**. Whether a speaker comes in the box is unknown.
  - There's an LCD_TE line, but I didn't trace which GPIO it reaches, and I don't use it.
- *Skill:* "Find … pins from the maker's own wiki or schematic." For this board (and probably most Waveshare and Espressif boards) the quickest complete source was the maker's **BSP in the component registry**: the pins, the panel's start-up sequence, its orientation and the touch transform, all in one C file. Suggest adding: "Look for the maker's BSP on components.espressif.com and download it to read. It's often the only place the panel's init sequence and orientation are written down."

## 3. The check

    python3 tools/board_check.py --chip esp32s3 --screen 480x480 --inches 2.16 --touch --psram 8

This says yes to everything: a 240x240 picture, each pixel 2x2, the "short form" layouts, and the picture fits in internal RAM. Its note says "without [a speaker] there's no chime", but the check has no `--speaker` flag, so that note shows whether or not the board has one. That's slightly confusing.

- *Question for the person (skill: "Ask how they'll stand it"):* the screen is square, so the skill doesn't require this question. Which edge will the USB-C cable come out of? I used Waveshare's own orientation (the one their demos use). If it's upside down or sideways on your desk, it's a two-line change in `board.c`.

## 4. The gallery at 240x240

`python3 tools/preview/gallery.py out.png --size 240x240` works. Everything fits. Compared with 240x320:
- On "home-toast", the toast at the bottom ("no reply from the Mac") covers most of the "5 turns today" pill.
- On the queue screens, the two buttons show only "–" and ">" (240x320 labels them "mute chime" and "open on mac").
- The date line under the clock is dropped.
These are in shared code (`ui.c`), so I left them alone, as the skill says. Worth a look by whoever owns the short layouts.

## 5. Backup before flashing

The skill and ttycat-flash say "keep the last build that worked", but **neither says to back up what's on a new board first**. On a non-ttycat board, that factory firmware is the only way back. I read the whole 16 MB flash before writing anything:

    esptool.py --port /dev/cu.usbmodem1101 -b 921600 read_flash 0 0x1000000 ~/ttycat-backups/waveshare-amoled-2.16-factory-20261105.bin

(sha256 6510b1c3…acba4, about 2 minutes.) To put it back: `esptool.py --port PORT write_flash 0 ~/ttycat-backups/waveshare-amoled-2.16-factory-20261105.bin`. Waveshare also publishes the factory image in their repo (`firmware/ESP32-S3-Touch-AMOLED-2.16-FactoryOnly-260318.bin`).
- *Skill:* suggest adding "Before the first flash on a board that isn't running ttycat, save what's on it with `esptool.py read_flash`" to ttycat-flash, with the restore command.

## 6. Writing the board folder

`firmware/boards/waveshare-esp32-s3-touch-amoled-2-16/`: `board.c`, `speaker.c`, `amoled.h`, `CMakeLists.txt`, `sdkconfig.defaults`, `idf_component.yml` (`espressif/esp_lcd_co5300 ^2`, `waveshare/esp_lcd_touch_cst9217 ^2`, `espressif/esp_codec_dev ~1.4.0`), and `dependencies.lock` (made by the build). Nothing outside the folder changed.

Decisions:
- **PSRAM** is octal (`CONFIG_SPIRAM_MODE_OCT`), as Waveshare's examples set it. esptool printed "Embedded PSRAM 8MB (AP_3v3)", which doesn't say octal or quad. The S3R8 is octal.
- **Orientation:** `esp_lcd_panel_swap_xy(true)` + `esp_lcd_panel_mirror(false, true)` gives the same MADCTL 0xA0 that Waveshare's init sends, as the skill asks, rather than putting 0x36 in the init list. Touch is turned in `board_touch` the same way `esp_lcd_touch` would with Waveshare's flags (mirror y, then swap): `x = 479 - raw_y`, `y = raw_x`, then ÷2.
- **Flush:** only changed 8-row bands, zoomed into two 15 KB DMA buffers in turn, so one band is zoomed while the last is sent. With ZOOM 2, every area starts on an even pixel and ends on an odd one, which the CO5300 needs.
- **Brightness:** 0 until the first frame is drawn, then `esp_lcd_panel_co5300_set_brightness`. An AMOLED has no backlight, so "dims" means the panel itself gets darker.
- **Touch:** polled every frame, no interrupt. On a read error or a bad ACK, it reports "no finger", so a stale point can't count as a press. The driver keeps old points when the ACK is wrong.
- **Speaker:** copied from the C5 board's `speaker.c`, with this board's pins, MCLK on, and the amp on a real GPIO through `audio_codec_new_gpio()`.

The template and the C5 example were clear and easy to follow. One thing in the skill was wrong: **step 4 says "Adjust the path to ESP-IDF as in `ttycat-flash`", but ttycat-flash says nothing about ESP-IDF's path.** I found ESP-IDF 5.5.6 at `~/esp/esp-idf-v5.5.6` and ran `source ~/esp/esp-idf-v5.5.6/export.sh` first.

The build passed the first time (`idf.py -B build-waveshare-esp32-s3-touch-amoled-2-16 -D BOARD=waveshare-esp32-s3-touch-amoled-2-16 build`). The image is 0x70960 bytes, with 70% of the app partition free.

## 7. Flashing

`python3 tools/firmware_bundle.py firmware/build-NAME OUT` then `python3 daemon/ttycatd.py --port /dev/cu.usbmodem1101 flash OUT --replace`, through the app's running daemon, as ttycat-flash says. That worked the first time. The daemon already had the port marked as silent (the factory firmware never says hello), so `--port` was accepted. Flashing took about 6 seconds, and the board said hello as `custom-0.10.1-…` with board `waveshare-esp32-s3-touch-amoled-2-16`.

- *Skill:* `firmware_bundle.py` with no arguments crashes with an IndexError instead of printing usage. That's minor, but a person trying it by hand sees a traceback.
- `--replace` is needed for every later flash too, because the board then runs custom firmware. ttycat-flash says this, but only in the bullet about what replacing means.

## 8. Checks I could do without anyone at the board

What's proven:
- **It runs and talks to the Mac.** The daemon shows `connected: true`, with the new build's name and the right board name. `boot: 224715 bytes free` of internal RAM. No errors at start-up: the touch chip answered its config read, and the ES8311 codec was found.
- **Sessions appear.** `ttycatd.py shot` shows the queue with the person's 16 real sessions. `goto pet` and `goto overview` match the 240x240 gallery exactly. (Nothing was waiting for an answer, and I only used `goto`, never `tap`.)
- **It dims.** After 100–140 s untouched on Bit's screen, the daemon's status went `dim: true`. On an AMOLED that means `board_backlight(8)` reached the panel's brightness command. Whether it *looks* dimmer needs a person.
- **Approving stays on the Mac.** The status says `approves: false`. I didn't touch Setup, `devices.json` or `FW_RELEASE` (rule 6).
- **Speed** (from a temporary diagnostic build, since removed): a full-screen redraw takes 27 ms, a frame with nothing changed 1.9 ms, and a touch read 2 ms.
- **Touch with no finger**: 20 of 20 reads came back without the chip's 0xAB acknowledgement, which the driver reports as `ESP_ERR_INVALID_RESPONSE`, and none failed on the bus. So with no finger, the chip answers but sends no report. `board_touch` treats that as "no finger", which is right. I had guessed this when writing it, and now it's measured.

What I tried and couldn't prove:
- **That the panel lights up.** I tried reading the panel's ID, power mode and MADCTL back over QSPI (opcode 0x03): first with the normal 4-line handle, then with a 3-wire (`sio_mode`) handle on the same CS. Both returned only zeros, so this panel's read-back doesn't work on this wiring (or needs a sequence I don't know). `shot` only shows ttycat's own picture in RAM, not what's on the glass. **Only a person looking can confirm the screen.** That cost two extra flashes, and I'd skip it next time.

## 9. Orientation: two Waveshare sources that look like they disagree

- Waveshare's BSP sends MADCTL 0xA0 (standard meaning: swap rows and columns, then flip) and turns touch with mirror_y-then-swap.
- Their Arduino widgets demo leaves MADCTL at 0 and turns touch with swap-then-mirror_x (SensorLib's order).
- Worked out, **both give the same touch transform**: picture x = 479 − raw y, picture y = raw x. Two different display settings can't both match the same touch turn, unless the CO5300 ignores 0xA0's bits. Arduino_GFX's CO5300 driver suggests it does: its flips are `0x02` (horizontal) and `0x05` (vertical), not the usual 0x40/0x80/0x20. So the most likely reading is that the screen shows in its own orientation, whatever MADCTL says, and touch matches it. I kept exactly the BSP's pairing, which is Waveshare's tested LVGL setup.
- *Skill:* step 3 says "Turned, turn the panel with `esp_lcd_panel_swap_xy` and `esp_lcd_panel_mirror`". On a CO5300 that probably does nothing. A quarter turn here would have to be done in software, while zooming in `board_flush`. Suggest adding: "Some AMOLED drivers (CO5300) don't support MADCTL's row/column swap, so check on the board before relying on it."

## 10. Questions for the person (written down instead of asked)

1. Does the board say "ESP32-S3-Touch-AMOLED-2.16" on it? (Identified from the specs, not the label.)
2. Which edge will face down on your desk, the one with the USB-C port or another? I used Waveshare's own "up". 180° is likely an easy change, but 90° needs work in software.
3. Is there a speaker plugged into the small 2-pin connector? If not, there's no chime, which is fine, and everything else works.
4. Do you want to turn on **It can approve prompts** in Setup? Only after you've checked that taps land in the right place (see below).
5. Would you like this saved as a pull request so others with this board can use it? I haven't pushed or opened anything.

## 11. What I'd change in the skill

- **Identifying the board:** add "read the chip with `esptool.py flash_id`, which only reads" for people who only have a shop link.
- **Finding the pins:** point to the maker's **BSP in the ESP component registry** as the first place to look. It held the pins, the panel's start-up sequence, its orientation and the touch transform. The wiki only had the pins.
- **Back up first:** before the first flash on a board that's never run ttycat, `esptool.py read_flash 0 <size> backup.bin`, and tell the person how to restore it. The skill only says to keep the last working *ttycat* build, which doesn't exist yet on the first flash.
- **Step 4** refers to ttycat-flash for the ESP-IDF path, but ttycat-flash doesn't mention it. Say how to find or source ESP-IDF (`. ~/esp/esp-idf-vX/export.sh`).
- **board_check:** it has no `--speaker` flag, so it always says "without one there's no chime", even for a board with an amp and speaker connector.
- **Step 3, turning the panel:** warn that some panel drivers ignore MADCTL's swap bit.
- **Step 5's checks** are nearly all "ask them what they see". For an agent working alone, it would help to list what *can* be checked without a person: `connected`/`fw`/`name` in the daemon status, `boot: N bytes free` and errors in `~/.ttycat/ttycatd.log`, `shot` compared with the gallery, `approves: false`, and `dim` after two minutes on the home screen.
- **AMOLED boards:** the template and skill talk about a "backlight" throughout. For an AMOLED, `board_backlight` is the panel's brightness command. Worth a line, plus a note on burn-in: the home screen's clock and Bit stay in one place for hours.

## 12. Where it stands

(Updated in section 13: the board now runs `custom-0.10.1-a756d798`, which keeps clear of the rounded corners.)

**ttycat is running on the board** as `custom-0.10.1-370e7247`, built from `firmware/boards/waveshare-esp32-s3-touch-amoled-2-16/` as it is now. It's connected to the app, drawing the person's real sessions, and dims itself. Nothing outside the board folder changed. (Two earlier builds, `4da7740b` and `187cc3a9`, differed only by an unused init command and a comment. The diagnostic builds are gone from the board.)

Saved in `~/ttycat-backups/`:
- `waveshare-amoled-2.16-factory-20261105.bin`: the whole factory flash. To restore: `esptool.py --port /dev/cu.usbmodem1101 write_flash 0 <file>`.
- `ttycat-custom-0.10.1-370e7247/`: this build, ready for `ttycatd.py flash <folder> --replace`.

**Not proven, because a person has to look or touch:**
1. The screen lights up, the right way round, with the right colours (orange accents, not blue). Compare it with `ttycatd.py shot` and the gallery.
2. A tap lands where the finger is: all four corners, then Deny and Allow on a real prompt. The touch turn comes from Waveshare's code and hasn't been tested by a finger.
3. On a prompt, "On Mac" brings it up on the Mac, and Deny works.
4. Only after 2 and 3: turning on **It can approve prompts** in Setup, if wanted, then checking that Allow appears and works.
5. The chime, if a speaker is plugged into P10, and that mute silences it.
6. The screen looks dimmer after two minutes on Bit's screen, and a touch brings it back.

## 13. Second attempt: rounded corners (2026-11-06)

The person looked at the glass and found what I couldn't: **the screen has rounded corners, and things at the edges were cut off by the curve.**

### What went wrong the first time
- I treated the panel as a 480x480 rectangle, because that's all the skill, `board_check.py` and the gallery ask about. Every check I ran was on the *picture* (`ttycatd.py shot`, the gallery), and the picture really is square. Only the glass is rounded.
- The answer was already on my disk. Waveshare's repo, which I had cloned for the schematic, has `dimensions/ESP32-S3-Touch-AMOLED-2.16-2D-20260209.rar`, a DXF and PDF of the board. Its front view shows the active area with big rounded corners. I never opened it, because I was only looking for pins.
- In my first summary I listed "the screen lights up, the right way round" as the person's check, but never "nothing is cut off at the edges". I didn't know to ask.

### Why the skill didn't catch it
- Its model of a screen is resolution, inches and orientation. Nothing in the skill, the template, `board_check.py` or the gallery mentioned the glass's shape, so a rounded panel passed every check.
- Its only check for "does it look right" is `shot` and the gallery, which can't show the corners. The step 5 list on the real board didn't mention edges either.
- "Round screens aren't supported" was the only shape it knew. Rounded *corners* on a rectangle fell between that and "fine".

### The corner radius, and where it came from
- From the DXF (parsed with a small script, since no CAD tool was installed): the active area ("VA 38.99 ± 0.10 mm") is a square with straight edges 23.49 mm long. Each corner is a cubic spline, not a circle, running 7.749 mm along each edge. At 480 px / 38.99 mm = 12.31 px/mm, that's **95.4 panel pixels**.
- Being a smooth curve, it cuts in only 1.78 mm (22 px) on the diagonal, where a 95 px circle would cut 28 px. I chose **the smallest circle that hides at least as much as the curve on every row: 95 px**, rounded up to **96** so it's a whole 48 px in the 240x240 picture. That's slightly conservative: about 3 picture pixels too cautious on the diagonal, and exact along the edges, where it matters. The other radii in the drawing ("4xR5.80" and "4xR4.70") are the case and cover glass, not the pixels.
- In the picture this hides up to 38 px of the top and bottom rows at each side, 23 px six rows in, and nothing from row 48 down to row 192.

### What I changed
The board says how its glass is shaped, and the shared screens make room in one general way:
- **Board** (`waveshare-esp32-s3-touch-amoled-2-16/board.c`): `#define CORNER_RADIUS 96` (panel pixels), with a comment saying where it came from, and `gfx_corner(CORNER_RADIUS / ZOOM)` in `board_begin`.
- **gfx** (`gfx.h`, `gfx.c`): `gfx_corner(radius)` builds a small table of how many columns the corners hide on each row. `gfx_inset(y, h, margin)` says how far in something in rows y..y+h has to start: the margin, or more where a corner reaches. `gfx_bottom(x)` says how far down something x px from the sides can go. `gfx_border` also redraws any part of a border the glass hides just inside the curve, so boxes in the corners stay closed (the alert's orange frame now follows the glass all the way round). With no `gfx_corner` call, the radius is 0, `gfx_inset` returns the margin, and the border code never runs.
- **Screens** (`ui.c`, `keyboard.c`, `pet.c`): anything placed against the top or bottom edge asks `gfx_inset` instead of using a fixed 6 (or 14, 16, 20):
  - every header's ends (`HL`/`HR`) and their tap areas
  - the queue's footer
  - the boxes along the bottom: Bit's "turns today", the overview's bar, the detail, choice, ask and link-lost buttons (`button_pair`)
  - the keyboard's rows, the boot screen's footer and sleeping-Bit box
  - the first line inside cards just under the header: card labels, the detail's agent badge, the overview's top card names and badges, the alert banner, the full command's first line and the keyboard's prompt
  - Bit's "Level n" banner
  - the queue's rows on very round screens

  When the overview's bar is narrowed and its text doesn't fit, it drops the word "NEXT" and keeps the arrow. Nothing checks which board it is, and on a square screen every one of these comes to the old number.
- **Preview**:
  - `harness.c` takes a corner radius.
  - `gallery.py` takes `--corner R`, or `--board NAME`, which reads `PANEL_W/H`, `ZOOM`, `CORNER_RADIUS` and `EDGE_INSET` from the board's `board.c`. It masks the corners with the sheet's grey, as the glass will, and always prints "hidden by the corners: …".
  - `--cut` paints red anything lost. It ignores a box's fill or border carrying on behind the glass, and counts black only when it's lettering on a coloured box.
- **Template**: `CORNER_RADIUS` and `EDGE_INSET`, with how to find them. A straight inset (a bezel hiding part of the panel along every edge) is the board drawing a smaller, centred picture: the template works out `PICTURE_W/H` and shows the offset in `board_flush` and touch. It still builds.
- **`board_check.py`**: `--corner` and `--inset`, in panel pixels.
  - Without them it says to look at the glass.
  - With them it gives the picture's corner and the gallery command to check, and warns on very round corners.
  - It refuses corners more round than square (that's a round screen).
  - It prints `CORNER_RADIUS` and `EDGE_INSET` with the other `#define`s.
- **Docs**: the boards README, the ttycat-new-board skill (find the glass's shape before the check, measure it and round up, mask the gallery, and check the edges corner by corner on the real board), and the ttycat-screen skill (`gfx_inset`, and checking with `--corner`). The latter named a `HALF` macro I'd removed.

### Checks
- **Official board, pixel for pixel:** the website's `npm run verify-board` against this copy says **83 of 83 frames match the firmware exactly** (it said the same before the change). I also built every gallery frame from the old and new code at 240x320, 240x240, 170x320, 480x480 and 320x240 on a square screen: **0 of 130 differ**. The official board's firmware and the template both build for their chips.
- **This board:** `gallery.py --board waveshare-esp32-s3-touch-amoled-2-16 --cut` gives "hidden by the corners" only for 8 px on the alert screen, which is a false alarm (see below). I looked at all 26 screens at 2x.
- **Other rounded screens:** 240x320 r40, 172x320 r30, 320x240 r30 and 240x240 r24 say "nothing". 240x280 r60, 320x480 r80 and 480x480 r96 and r120 flag only the alert frame's gap.
- **On the board:**
  - Built (70% of the app partition free) and flashed as **`custom-0.10.1-a756d798`**: `boot: 224467 bytes free`, connected, `approves: false`, nothing waiting.
  - `shot` of the queue, Bit's screen and the overview, masked with the glass's corners: 0 px hidden.
  - `tap` on the moved header buttons (‹ Agents, the grid, the overview's ×) goes where it should. I only tapped with nothing waiting (rule 5).
  - It dimmed after two minutes on Bit's screen, as before.

### My wrong turns this time
- **A uniform safe margin first.** I first thought of laying every screen out in a smaller rectangle inside the corners. That would have made the picture about 218 px tall, below the 240 px the layouts are made for, so I dropped it.
- **Rounding boxes to follow the glass.** I considered rounding boxes with corners concentric to the glass. That would have put black lettering (on the orange bar, say) over black, so content has to move anyway. I kept only the border redraw.
- **Narrowing the overview's bar.** The first fix cut "3 approvals · 1 error" short behind "NEXT". It's fixed by dropping the word, and only when the bar was narrowed.
- **My first `--cut` detector was wrong several ways:**
  - It counted fill behind the curve as lost.
  - It missed black lettering on orange.
  - It greyed out pixels while it was still checking them, so stepped corners looked lost.

  Each version gave a different count, and I fixed each one by locating the exact pixels, not by assuming. It still flags the black gap between the alert's hidden outer frame and its redrawn curve (8 px here). That's background, not content.
- **Only one shape at first.** I first fixed what this board's shape showed: headers, footers and the bottom row. Trying a much rounder 480x480 screen found card contents just under the header that this board doesn't hit yet. I fixed those too, so the next rounded board isn't the one to find them.

### What I'd change in the skill (done, except where noted)
- Ask about the glass's shape before the check, not after, and say where to find it: the maker's 2D drawing (DXF/PDF), the datasheet's active-area outline, product photos. If the corner is a curve, measure the circle that reaches as far along the edges, and round up. **Done.**
- Say that `shot` and the gallery show the picture, not the glass, and give the gallery a way to show the glass (`--corner`, `--board`, `--cut`). **Done.**
- Add "nothing cut off at the edges, corner by corner" to the checks on the real board. **Done.**
- The skill says to change nothing outside the board's folder. It now says what to do when that can't hold: stop, say what's cut off and where, and ask before changing shared code. **Done.**
- Not done: the remaining notes from section 11 (back up first, the ESP-IDF path in step 4, `esptool flash_id` for identifying a board, checks an agent can do alone, AMOLED wording).

### What the person should check on the glass, corner by corner
Listed in the final message of this session. The build on the board is `custom-0.10.1-a756d798`. The one before it, `370e7247`, is still in `~/ttycat-backups/` if this one is worse in some way I can't see.
