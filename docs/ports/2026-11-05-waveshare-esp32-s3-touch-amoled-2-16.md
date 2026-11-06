# First port: Waveshare ESP32-S3-Touch-AMOLED-2.16

The first time a fresh agent took ttycat to a board nobody had ported it to, using only `.claude/skills/ttycat-new-board`. It's the baseline for improving the skill. The agent's own notes are in the `-agent-notes.md` file beside this one. This file is the review of its full transcript.

## The run

- **Board:** Waveshare ESP32-S3-Touch-AMOLED-2.16. ESP32-S3R8 (8 MB octal PSRAM, 16 MB flash), 480x480 AMOLED on a CO5300 over QSPI, CST9220 touch, ES8311 codec with an amp to a 2-pin speaker socket, AXP2101 power chip, QMI8658 motion sensor.
- **Brief:** a shop link, "it's plugged in over USB-C", the skill, and a yes to flash. The person was away: no questions could be asked.
- **Agent:** headless Claude Code, in a scratch copy of the repo, with permissions skipped. 87 turns, 19 minutes, $4.82.
- **Result:** `custom-0.10.1-370e7247` running, connected to the app, showing real sessions, dimming. The screens it showed match the 240x240 gallery. Nothing outside `firmware/boards/waveshare-esp32-s3-touch-amoled-2-16/` changed.
- **Not yet proven:** anything on the glass or under a finger. See "Still to check" below.

## What went right

- The requirements check gave the right answer straight away: a 240x240 picture with each pixel 2x2, in internal RAM.
- The board built the first time and flashed the first time. It said hello as its own board name, and the daemon took it.
- The agent kept to the rules: it changed nothing outside the board's folder, never used `tap`, and left approving on the Mac.
- It backed up the factory firmware before the first flash, without being told to.

## Failures and wrong turns, from the transcript

| # | What happened | Cost | Why | Fix |
|---|---|---|---|---|
| 1 | The shop page didn't name the board: 1 MB of scripts, no maker or model | 3 fetches | Shop pages often don't | Skill: if all they have is a shop link, read the chip with `esptool.py flash_id`, then search for chip + screen size + resolution |
| 2 | The wiki had pins, but not the panel's start-up commands, orientation or touch protocol. GitHub pages wouldn't fetch | 7 fetches and a sub-agent | Wikis are thin, and GitHub's web pages are scripts | Skill: look for the maker's BSP on components.espressif.com first, and clone repos rather than fetching pages |
| 3 | Step 4 says "adjust the path to ESP-IDF as in ttycat-flash", which says nothing about it | A search | **A bug in the skill** | Say how: `ls ~/esp/*/export.sh`, then `. ~/esp/esp-idf-vX/export.sh` |
| 4 | Two extra flashes trying to read the panel's registers back over QSPI, which returned zeros | 2 flashes, a few minutes | It wanted proof the glass lit up, and `shot` only shows the picture in RAM | Skill: say plainly that only a person can confirm the screen, and not to try reading the panel back |
| 5 | It reported the short screens' buttons losing their labels | A wrong conclusion | **A bug in the gallery:** a toast from one frame stayed on the next ones | Fixed: the gallery lets the toast go before moving on |
| 6 | `firmware_bundle.py` with no arguments crashed with a traceback | A try | No usage message | Print usage |
| 7 | `board_check.py` always says "without a speaker there's no chime" | Confusion | No `--speaker` flag | Add `--speaker` |
| 8 | MADCTL's swap and mirror may do nothing on a CO5300, so a quarter turn may need doing in software | Not hit yet, worked out from two Waveshare sources | Some AMOLED drivers ignore those bits | Skill: warn, and give the shared code a way to rotate while zooming in `board_flush` |
| 9 | A blocking `sleep 100` was refused | A retry | The agent harness, not ttycat | None needed |

## Learnings for the skill

1. **Identify the board from the chip**, not the shop page.
2. **The maker's BSP is the best source** for pins, the start-up sequence, orientation and the touch turn.
3. **Back up the factory firmware first**, and say how to restore it. On a board that's never run ttycat, there is no "last build that worked".
4. **List what an agent can check alone:** the daemon's status (`connected`, `fw`, `name`, `approves`, `dim`), `boot: N bytes free` and errors in `~/.ttycat/ttycatd.log`, and `shot` compared with the gallery. Then list what only a person can check.
5. **AMOLED boards are different:** `board_backlight` is the panel's brightness command (0 to 100 in Espressif's CO5300 driver), and a still picture can burn in over months. Worth deciding whether the home screen should shift a little now and then on such boards.
6. **A headless run is cheap and fast enough to repeat:** under 20 minutes and $5. Rerun it on the same board after changing the skill, to see whether the failures above go away.

## Still to check, on the board

1. The screen lights up the right way round, with the right colours: orange, not blue.
2. A tap lands where the finger is: all four corners, then Deny and "On Mac" on a real prompt.
3. Only after 2: turn on **It can approve prompts** in Setup, and check Allow.
4. The chime, if a speaker is plugged into the 2-pin socket, and mute.
5. Dimming after two minutes on Bit's screen, and a touch bringing it back.

## Second round: rounded corners

The person found the glass has rounded corners, which hid the edges of the screens. The same agent was resumed with that, and allowed to change shared code for it. 93 turns, 36 minutes, $15.30. The person checked the glass afterwards: nothing is cut off.

- **What changed:** a board with rounded corners passes their radius to `gfx_corner`. The screens then ask `gfx_inset` and `gfx_bottom` how far in to keep near the top and bottom edges, and borders bend with the glass. `CORNER_RADIUS` and `EDGE_INSET` are in the template, `board_check.py` takes `--corner` and `--inset`, and `gallery.py --board NAME` masks the corners as the glass does, with `--cut` marking anything hidden.
- **Only for rounded screens.** A board that doesn't call `gfx_corner`, or sets 0, gets exactly what it had before: all 26 screens at seven sizes are byte-identical before and after, and the official board's 83 frames still match the website's port. The person asked for this to stay so.
- **The radius came from the maker's drawing:** Waveshare's DXF in their repo, 96 panel pixels, rounded up. The agent had downloaded it in the first round without opening it.

**Why the first round missed it:** every check looked at the picture, which really is square. `shot` and the gallery show what's in RAM, never the glass. The skill said nothing about the glass's shape, and the board check had no question for it.

**Learnings for the skill:**
1. Ask about the glass, not just the panel: rounded corners, a bezel over the edges, a notch. Read the maker's mechanical drawing for it.
2. Show the gallery with the board's shape (`--board`) before flashing. It's the only way to see the glass on the Mac.
3. Shared-code changes like this one are fine when they're general and leave every other board byte-identical. The skill's "change nothing outside the board's folder" should say how to ask for one.

## Files

- `firmware/boards/waveshare-esp32-s3-touch-amoled-2-16/`: the board, as the agent left it.
- `~/ttycat-backups/`: the factory flash (16 MB), both builds, and both runs' transcripts. Not in the repo.
