# ttycat

A touch screen on the desk for your coding agents, with or without [herdr](https://herdr.dev): what every coding agent is doing, and Allow or Deny for the ones waiting on you. It runs on the Waveshare ESP32-C5-Touch-LCD-2.8 (240x320, capacitive touch), and other boards can be added.

This is its firmware. ttycat is three open-source repos:

| Repo | What |
|---|---|
| **ttycat-firmware** | this: the ESP-IDF firmware. `main/` draws the screens and talks to the Mac, `boards/` has one folder per board, `docs/PROTOCOL.md` is what the Mac and a device say |
| [ttycat-daemon](https://github.com/ttycat-sh/ttycat-daemon) | the Mac's side: finds the agents, carries answers back, and flashes the board. Here as the `daemon/` submodule |
| [ttycat-app](https://github.com/ttycat-sh/ttycat-app) | the menu bar app, which runs the daemon |

```sh
git clone --recurse-submodules https://github.com/ttycat-sh/ttycat-firmware
```

## Flash the firmware

**From the app:** Setup > Firmware > **Update board**. It takes about 10 seconds, and the board has to say it's running the new version before the update counts as done. Agents keep running meanwhile; answer prompts in the panel or the terminal until the board's back.

- The app carries the firmware that was built when ttycat-app's `build.sh` ran, so build the firmware first. The version comes from the binary, and updates are offered only for a board on an older one, so **bump `FW_VERSION` in `main/model.h` for every release**. A changed build with the same number won't be offered.
- **Only a release says it's ttycat's firmware, and only signed.** `tools/release_firmware.sh` builds it into `build-release`, and signs its image and the core's source with the key in `TTYCAT_SIGNING_KEY` (`daemon/tools/release_key.py` makes one). The daemon writes firmware that says it's ttycat's own only from an image signed by a key in its `release_keys.json`, whether it comes in the app or from a server. ttycat-app's `release.sh` won't go without all of it. Anything else built from source says something like `custom-0.9.1-a1b2c3d4` (set `FW_LABEL` for your own first word), where the end comes from the source, so every change has a new name.
- **A tag is a release.** `.github/workflows/release.yml` runs on `vX.Y.Z`, for prod, and on `vX.Y.Z-dev.N`, for dev. `FW_VERSION` must say `X.Y.Z`. A version goes to each environment once: a rebuild isn't byte-for-byte the same, and the bucket never replaces a file, so a second `-dev.N` of the same version stops at the upload. Bump `FW_VERSION` instead.
  1. It builds the official board's firmware in Espressif's ESP-IDF image, pinned by digest.
  2. It signs that firmware and the core's source with the environment's key.
  3. It uploads them to the releases bucket, never replacing a file.
  4. It offers them to Macs through the update server, with `daemon/tools/publish_release.py`. For prod, it also attaches the same files to a GitHub release.

  Its secrets are listed at the top of the workflow.
- **Your own firmware keeps its place.** The app never offers to update custom firmware, and Setup only replaces it if you ask to and confirm.
- It uses esptool from your ESP-IDF install (`~/.espressif/python_env`). Without it, Setup says so.
- Each file's hash is checked before anything's written, esptool refuses a board with a different chip, and firmware made for another board is refused.
- If an update fails partway, the board stops answering and Setup offers **Reinstall firmware**. That's asked twice and names the port, because a port that doesn't answer could be another device. The daemon tries each serial port once and stays with the first that says hello, so a silent one is only ever touched if you say so. If it can't connect, hold BOOT while plugging the board in.

**By hand**, which needs ESP-IDF 5.5:

```sh
. ~/esp/esp-idf-v5.5.6/export.sh
idf.py -p /dev/cu.usbmodem1101 flash
```

Stop the daemon first: it holds the serial port.

## Building on it

The firmware's open, and you don't have to write the code yourself. Open this repo with a coding agent and say what you'd like: `AGENTS.md` and the skills in `.claude/skills` tell it how, along with the rules that keep your agents answerable to you.

- **A new screen:** `tools/preview/preview.py` shows the real screens as images, with no board and no ESP-IDF, so you can see it before you own one.
- **Another board:** each board is a folder in `boards`, and everything else is shared. See `boards/README.md`.
- **A different device:** anything that speaks `docs/PROTOCOL.md` over USB works, such as a lamp.

Another board has been tried on a real one: an agent with only the skill ported it to `boards/waveshare-esp32-s3-touch-amoled-2-16`, and `docs/ports` has how it went. A different device has been tried without hardware, and not yet for real.

## Using it

| Where | What |
|---|---|
| **Queue** | Tap a tab or swipe left and right to filter by agent. Swipe up and down for more rows. The hero card is the most urgent session. Tap it, or a row, to open that session. A session on another machine shows that machine's name. |
| **Overview** | The grid icon, top left. One card per agent. **Next** goes to whatever needs you first. |
| **Approval** | Allow or Deny. Deny ends the turn, like No in the terminal. If the text doesn't fit, it shows `...`: swipe up to read all of it. |
| **Question** | When Claude asks a question: tap an option, or **Type an answer** for the keyboard, then **Send**. If it's several questions, **Next** moves through them. Multi-select allows several picks. Swipe up to read everything, including each option's description. **Later** steps away and keeps your picks. |
| **Needs you** | A prompt the board can't answer. **Open on Mac** focuses that pane in herdr and brings Ghostty forward. The button shows **Opening**, then a green **Look at Mac**. |
| **Detail** | Recent events for a session, and the chime's mute switch. Lines too long to fit scroll by themselves. Swipe right to go back. |
| **Home** | Bit and its level, the time, and how the agents are doing. While an agent works, Bit walks to the middle and types on a laptop, with a small Bit beside it for each other agent working (4 at most; the status line has the true count). Appears after 30 s untouched, unless an agent is waiting on you or there's an error: then the board stays on the queue. It dims 2 minutes after the last touch, and the first touch on a dim screen only wakes it. Tap **Agents**, the box at the bottom, or swipe sideways for the queue. |

## The pet

Bit lives on the home screen. There's nothing to look after: it's never hungry or sick, it can't die, and it's fine however long you leave it. What it has is a level, shown with how far it is to the next one and what that level brings. To go there straight away, tap the **All clear** tile on Overview. Rename it with `python3 daemon/ttycatd.py pet --name NAME` (11 characters), and see its stats with `ttycatd.py pet`.

It sleeps from 22:00 to 07:00, and when the screen dims, unless an agent is working: then it's at its laptop whatever the hour.

It grows with time and use, and you can't race it. Each day counts 1, whether or not the daemon was running. Your agents' tokens that day add up to 2 more, quickly at first and then less and less: 100k tokens add 0.79, 1M add 1.99, and past that almost nothing. Only your 5 biggest days of a week count, so working through the weekend gains nothing. That makes the crown 61 days away at best. Level 2 takes 3, level 3 takes 12, level 4 takes 27, and so on. It earns a pilot's headset at level 3, an antenna at 5 and a crown at 8.

- **It never beeps.** The chime only ever means an agent needs you.
- **Time brings keepsakes.** It wears a party hat on the first of every month, its birthday, and gets a scarf to keep at 100 days old. Nothing can speed these up, they don't affect growth, and missing a birthday costs nothing.
- **Your answers don't count.** It grows from time and tokens, and Allow and Deny make no difference, so nothing rewards saying yes.
- **Agents come first.** A new prompt or error leaves the home screen at once. Taps then don't count until they've stopped for 0.8 s, at least 1.5 s from the interruption, so nobody tapping away can hit Allow by accident.
- **It's glad you took a day off.** The first touch or panel opening after a whole day with no agents, it greets you rested and happy, with a bigger hello after 3 days or more. That's all a day off does: it earns no growth, and nothing counts them.
- **Tokens stay here.** Growth reads input and output tokens, never cache reads, from what Claude, Codex, OpenCode, Gemini and Pi record on this Mac. `~/.ttycat/token-days.json` keeps a number per day and where it got to in each log. An agent that doesn't record tokens adds nothing to growth.

**In the Mac app:** the **Bit** tab has the same Bit, its level and what's next. A click on it pats it, which gets a heart and nothing more. It never sends a notification.

The two stay in step because neither one decides anything. The daemon numbers each reaction (`ev`, `evk` in the state), and both show the reaction when they see the number change, whichever one it came from. Both draw Bit by the same rules: at its laptop if an agent is working, otherwise asleep at night or when the board's screen is dim. The board tells the daemon when its screen dims, because Bit dozes then. The panel checks four times a second while the Bit page is open, so a tap on the board shows there within about a quarter of a second. Where Bit wanders on the board's screen isn't shared: that's idle animation, and the panel has no room to wander in.

A new prompt or error leaves the Bit page for Agents. A prompt's buttons then stay off for at least 1.5 s, and until clicks have stopped for 0.8 s, so nobody clicking away hits Allow by accident. They always wait for clicks to stop, however you got there, and opening the panel with something waiting shows that first.

Its state is in `~/.ttycat/pet.json`, so it survives reflashing. `demo` mode uses a separate pet in memory.

## Fonts on the real panel

The screens were designed at twice the panel's size, and at 1x some of the font sizes break up into dots. Positions and line boxes stay as designed, and these are drawn at the nearest clean size instead, by `tools/gen_fonts.py`:

| Designed at | Drawn at |
|---|---|
| Silkscreen 9 | 8 |
| VT323 14 and 16 | 15, with `m w M W 4 9` redrawn by hand |
| VT323 18 | 20 with tighter spacing, `f` redrawn by hand |
| Pixelify Sans 13 | 15 |
| Press Start 2P 12 (LINK LOST) | 16 |

## Board notes

These are about the Waveshare board, in `boards/waveshare-esp32-c5-touch-lcd-2-8`.

- **Screen:** the UI redraws into an RGB565 framebuffer in internal RAM, 240x320 on this board. Only rows that changed go to the ST7789, over SPI at 80 MHz. On other boards the screens lay themselves out for any size from 170 to 480 pixels wide and 240 to 480 tall: see `boards`.
- **Reset and backlight:** both resets, the backlight and the speaker amp sit behind the CH32V003 at I2C 0x24. Waveshare's firmware on that chip stays as it is; flashing here only touches the ESP32-C5.
- **SD slot:** it shares the panel's SPI bus, so at boot any inserted card gets CMD0 to move it to SPI mode. A card left in SD mode can read pixel data as commands.
- **Panel gamma, touch and expander:** done as Waveshare's Arduino driver does them. With the ST7789's own voltages and gamma, the colours look washed out.

## Serial protocol

One JSON object per line, on the board's USB port. Other lines, such as boot and panic output, are logged by the daemon and otherwise ignored.

| Direction | Message |
|---|---|
| Daemon to board | `hello` back, `state` once a second (sessions, local time, history of the watched session, Bit), `ack` after each `act`, `art` for Bit's stage, `name` when the person names the board |
| Board to daemon | `hello`, `act` (allow, deny, answer, open, ask-mac, seen, and `pet-*`), `watch`, `dim`, `need`, `touch` (logged) |
| Testing, via `ttycatd.py` | `shot PATH` saves the real frame as a PNG; `tap X Y`, `swipe L\|R\|U\|D`, `goto SCREEN` (`queue`, `overview`, `tab:N`, `ask:ID`, `full`, `keys`, `detail:ID`, `pet`, `pet:heart`, `pet:reward`, `pet:level`, `pet:sleep`, `pet:birthday`); in demo, `scene NAME` (including `question`, `questions`, `long`, `many`) |

**Only ttycat's own firmware can approve without being asked about.** A device that gives any other name in `hello`, or none, can see everything, open a session and Deny, but its `allow` and `answer` are refused, and it's told so with `na`, so the firmware shows "On Mac" where Allow was and brings the prompt up here. That's because it may have no way to show the whole prompt. For one that does, Setup > Firmware has **It can approve prompts**, off until you confirm, for that name only (`~/.ttycat/devices.json`). This guards against accidents. Each new build of your own asks again, with one exception: an update from Setup, built from a folder that hasn't changed since the build you allowed, keeps it, because the only new code is ttycat's signed release. It can't stop a device built to lie about its name.

`tap` goes through the same code as a finger, so anything on this Mac running as you can answer prompts the board is showing. The same is true of anything that can type into your terminal. The hook socket, `~/.ttycat/hook.sock`, is only readable by you.

The full protocol is in `docs/PROTOCOL.md`.

## Tests

```sh
python3 tools/preview/preview.py out.png --scene asks --goto queue   # a screen, with no board and no ESP-IDF
python3 tools/preview/gallery.py out.png --size 170x320              # every screen at one size
python3 tools/preview/unchanged.py                                   # every screen on every board, as at the last commit
python3 -m unittest discover -s tools/tests                          # taps answer only the prompt on screen, and the colours are the daemon's
```

`unchanged.py` is for changes that shouldn't show: a fix for one board's sake, or tidying up. It renders every screen at every size and on every board from your change and from the last commit, and says which frames differ.

The daemon's and the app's tests are in their own repos. Fonts: Press Start 2P, Silkscreen, Pixelify Sans and VT323, all SIL Open Font License (`tools/fonts/OFL-*.txt`).

## Open source, and Pro

Everything in these three repos is free and open source: seeing your agents, answering their prompts, notifications, the board and its firmware, and Bit. It's complete without anything else.

The official download adds paid features to the app, kept in a separate private repository: usage and limits, a log of what agents did, other machines, and skins. They join through two small interfaces, `plugins.py` in the daemon and `Extensions.swift` in the app, and the open code never depends on them.

## License

Apache-2.0: see `LICENSE` and `NOTICE`. What the firmware builds on, and under which license, is in `THIRD_PARTY.md`. The license doesn't grant use of the product's name or logo.
