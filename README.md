# ttycat

A touch screen on the desk for your coding agents, with or without [herdr](https://herdr.dev): what every coding agent is doing, and Allow or Deny for the ones waiting on you. It runs on the Waveshare ESP32-C5-Touch-LCD-2.8 (240x320, capacitive touch) and implements the "ttycat UI" design.

```
firmware/    ESP-IDF firmware: main/ draws the screens and talks to the Mac, boards/ has one folder per board
daemon/      Mac daemon, Python standard library only: herdr and Claude Code <-> USB serial
app/         menu bar app (Swift): runs the daemon and shows what it knows
tools/       font generator and the design's fonts (OFL licensed)
```

## Run it

With the board on USB and herdr running:

```sh
python3 daemon/ttycatd.py run
```

The board leaves its "waiting for Mac" screen within a second or two. The daemon has to stay running; if it stops, the board goes back to that screen.

For Allow and Deny, add the permission hook to `~/.claude/settings.json` once. Running sessions pick it up without a restart. It adds one entry, and saves the previous file as `settings.json.ttycat-backup`:

```sh
python3 daemon/ttycatd.py hook install    # or: remove, status
```

Run this way, the hook runs from this folder, so install it again if the project moves. The app's own hook doesn't have that problem.

To see every screen without touching real sessions, use the design's sample data. Nothing is answered in this mode:

```sh
python3 daemon/ttycatd.py demo
```

## The menu bar app

`app/` is a SwiftUI menu bar app in the board's look. It keeps the daemon running, restarts it if it dies, and shows every agent, the board's link and Bit's stats. You can answer prompts in it, and click a row to see what that agent has been doing. It needs macOS 14 and the command line tools, not Xcode:

```sh
app/build.sh            # builds app/build/ttycat.app
app/build.sh install    # also copies it to /Applications and starts it
```

**Setup** in the panel has start at login (off until you tick it; use the copy in /Applications), the permission hook, notifications, other machines and the daemon's log.

- **Notifications** say when an agent needs you, and when one finishes after 30 s or more of work. Clicking one opens the panel on that prompt, or the terminal if there's nothing to answer there.
  - A prompt waits 3 s, so one you answer straight away never shows a banner. Nothing is posted for the agent whose pane is focused in your terminal while that terminal is in front and you've touched the Mac in the last 2 minutes, nor while the panel is open. A prompt is posted when you move away; a finished turn isn't.
  - Allow is never on a notification. A prompt's notification offers Deny, and a click opens the panel to read and answer it. A single question with one answer gets its options and "Type an answer" as buttons. Several questions, or pick-any, open the panel.
  - Buttons don't work from a locked screen, and a click within 600 ms of a notification appearing doesn't count. A notification goes away once its prompt is settled anywhere, and when the app quits.
  - Commands, questions and the agent's last words appear in Notification Center, so they can be seen by anyone looking at the screen. macOS's "Show previews" setting hides them.
  - The app asks macOS for permission only when you click **Turn on notifications** in Setup. If it was refused, it's System Settings > Notifications > ttycat.
  - macOS holds notifications back during a Focus, without any error, unless you allow this app in that Focus. Setup always says so, because this build can't tell whether a Focus is on. Time Sensitive wouldn't get through either: it needs an entitlement this build doesn't have, and macOS ignores it without one.
- **Answers work as they do on the board.** Allow, Deny and questions (typed answers here can be up to 1000 characters and aren't limited to ASCII) go only to the hook process that asked, and only for the exact prompt on screen. Buttons wait 600 ms after a prompt appears, and a new prompt waits its turn instead of replacing the one on the card.
- **Anything running as you can reach the daemon's socket,** so a program you run could answer a prompt. That was already true of `ttycatd.py tap` and `herdr agent send-keys`.
- **The app carries what it needs:** the daemon, Python and esptool, so a Mac needs nothing installed. The hook points into the app, and repairs itself at launch if the app has moved. `app/vendor.sh` prepares Python and esptool (pinned, from GitHub and PyPI), once. Without it the app still builds and uses the system's Python, for working on it. `TTYCAT_DAEMON_DIR=daemon` runs a build from this checkout instead. Apple silicon only, for now.
- **The board is optional.** Nothing mentions it until one has been connected.
- **A release** is `app/release.sh`: signed with your Developer ID, in a disk image, notarized by Apple. See the script for the one-time setup. Licenses of what it carries are in `THIRD_PARTY.md`.
- **The panel is its own window, not SwiftUI's `MenuBarExtra`,** which grows its window but never shrinks it (`StatusPanel.swift`). Its top stays under the icon, its height follows the page, and a page too tall for the screen scrolls under the tabs. It takes the keyboard without making this the active app, like Spotlight, so what you were in stays in front. A click elsewhere, Esc, or switching app closes it. Its content is built new on each open, so a prompt's buttons always get their full delay.
- **One daemon at a time.** A second one exits with status 3. If one's already running, from a terminal say, the app uses it, and leaves it running when it quits. One the app started stops with it.
- Plain `@State` doesn't build here: in current SDKs it's a macro, and its plugin comes only with Xcode. Panel.swift has a small stand-in.
- To check the look without opening the menu: `"app/build/ttycat.app/Contents/MacOS/ttycat" --preview out.png needs` (`busy`, `needs`, `diff`, `long`, `question`, `questions`, `terminal`, `detail`, `done`, `idle`, `setup`, `setup-new`, `setup-denied`, `setup-short`, `welcome`, `noboard`, `pet`, `pet-asleep`, `pet-needs`, `pet-level`, `pet-hello`, `pet-birthday`, `fw-update`, `fw-write`, `fw-back`, `fw-fail`, `fw-unknown`, `fw-custom`, `fw-custom-on`, `stopped`, `unplugged`).

## Where agents come from

| Where | Which agents | Its state | Answer from the board or app |
|---|---|---|---|
| **In herdr** | All the agents it supports | Read from each agent's screen by herdr | Claude Code, through the hook |
| **Claude Code in any other terminal** | Claude Code | Claude's own record in `~/.claude/sessions/<pid>.json` | Through the same hook |
| **Any other agent in tmux** | Those herdr has rules for: Codex, OpenCode, Pi, Gemini and others | Read from its screen, by herdr's rules | No: its prompt is shown, and answered in its terminal |
| **The Codex app** | Its threads, active in the last 30 minutes | Codex's own records in `~/.codex` | No |
| **Codex in any other terminal** | Codex | The same records, if it's the only Codex in its folder | No |
| **Any other agent in any other terminal** | OpenCode, Gemini and others, by process name | None: it shows as running, "state unknown" | No |

herdr isn't required, on this Mac or on other machines. A session outside it just shows up, with nothing to install; the hook (Setup > Answer prompts on the board) is what lets you answer Claude from here. Anything inside herdr is left to herdr, so nothing appears twice. tmux inside a herdr pane counts as outside it, since herdr can't see in.

**What a screen means** comes from [herdr](https://github.com/herdrdev/herdr)'s detection rules (`daemon/agent_rules.json`, Apache-2.0, `daemon/agent_rules.LICENSE`) and a port of its engine (`daemon/screen_rules.py`), checked rule by rule against herdr's own `agent explain`. Update them with `tools/import_agent_rules.py HERDR_REPO`. Unlike herdr, they don't update themselves, so a new version of an agent can show the wrong state until they're refreshed. Unknown screens read as idle, as in herdr, so an unusual prompt can look idle. No keys are ever sent to these agents.

- **Which process is the agent** is worked out as herdr does: the terminal's foreground job, its leader first, by name, seeing through runtimes such as `node`, and never from an argument that only mentions one. Background services don't count.
- **An agent showing "state unknown" may be waiting on you.** Nothing can read another terminal's screen, so this can't tell. For its real state and prompts, run it in tmux or herdr.
- **Codex's log can't tell waiting for approval from a long command.** A thread that's able to ask says "may be waiting for approval" after 20 quiet seconds with a tool call open. In tmux, its screen tells them apart.
- **Claude's record isn't a documented interface.** It's read loosely (`daemon/discovery.py`): anything unfamiliar means fewer rows, never a wrong answer. If it changes in a Claude update, a Claude session outside herdr drops to "state unknown" and its prompts stay in the terminal. herdr sessions aren't affected. Nor is Codex's database or log documented (`daemon/codex_threads.py`), and they're read the same way, read-only.
- **Open in terminal** brings the session's terminal app forward, and the right pane under tmux. It can't pick the tab in other terminals. On another machine, only a herdr pane can be opened from here. A Codex app thread opens in the app, through its `codex://threads/` link.
- **Notifications can't tell which tab you're on** outside herdr, so a banner can appear for the session you're already looking at.

## Flash the firmware

**From the app:** Setup > Firmware > **Update board**. It takes about 10 seconds, and the board has to say it's running the new version before the update counts as done. Agents keep running meanwhile; answer prompts in the panel or the terminal until the board's back.

- The app carries the firmware that was built when `app/build.sh` ran, so build the firmware first. The version comes from the binary, and updates are offered only for a board on an older one, so **bump `FW_VERSION` in `firmware/main/model.h` for every release**. A changed build with the same number won't be offered.
- **Only a release says it's ttycat's firmware, and only signed.** `tools/release_firmware.sh` builds it into `firmware/build-release`, and signs its image and the core's source with the key in `TTYCAT_SIGNING_KEY` (`tools/release_key.py` makes one). The daemon writes firmware that says it's ttycat's own only from an image signed by a key in `daemon/release_keys.json`, whether it comes in the app or from a server. `app/release.sh` won't go without all of it. Anything else built from source says something like `custom-0.9.1-a1b2c3d4` (set `FW_LABEL` for your own first word), where the end comes from the source, so every change has a new name.
- **Your own firmware keeps its place.** The app never offers to update custom firmware, and Setup only replaces it if you ask to and confirm.
- It uses esptool from your ESP-IDF install (`~/.espressif/python_env`). Without it, Setup says so.
- Each file's hash is checked before anything's written, esptool refuses a board with a different chip, and firmware made for another board is refused.
- If an update fails partway, the board stops answering and Setup offers **Reinstall firmware**. That's asked twice and names the port, because a port that doesn't answer could be another device. The daemon tries each serial port once and stays with the first that says hello, so a silent one is only ever touched if you say so. If it can't connect, hold BOOT while plugging the board in.

**By hand**, which needs ESP-IDF 5.5:

```sh
. ~/esp/esp-idf-v5.5.6/export.sh
cd firmware
idf.py -p /dev/cu.usbmodem1101 flash
```

Stop the daemon first: it holds the serial port.

## Building on it

The firmware's open, and you don't have to write the code yourself. Open this repo with a coding agent and say what you'd like: `AGENTS.md` and the skills in `.claude/skills` tell it how, along with the rules that keep your agents answerable to you.

- **A new screen:** `tools/preview/preview.py` shows the real screens as images, with no board and no ESP-IDF, so you can see it before you own one.
- **Another board:** each board is a folder in `firmware/boards`, and everything else is shared. See `firmware/boards/README.md`.
- **A different device:** anything that speaks `docs/PROTOCOL.md` over USB works, such as a lamp.

These have been tried without hardware, and not yet on a real board.

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

## Answering prompts safely

Allow, Deny and answers to questions go through Claude Code's `PermissionRequest` hook (`daemon/hook.py`, `daemon/approvals.py`). Nothing is typed into a terminal. The terminal prompt stays up as usual, and whichever answers first wins.

- **An answer can only reach the request it was shown for.** Each request is a hook process waiting on its own socket connection. The board echoes that request's id, and a decision goes only to that process.
- **Failure leaves the prompt in the terminal.** With no daemon, no board, a crash or a timeout, the hook exits without a decision, and the prompt stays open. Nothing is approved.
- **Allow is the plain Yes.** It never changes the command and never adds a permission rule. Rules in your settings that deny or ask still apply.
- **Deny is the plain No.** It ends the turn, and the agent waits for you, as with No in the terminal. No answer here lets it carry on.
- **Nothing is approved unseen.** The board shows the real command or diff, not Claude's description of it. A clipped one is marked and can be read in full by swiping up. Anything over 1000 characters is terminal-only, and so is an ask that doesn't fit the board's 6 KB of shared text.
- **Stray taps don't count.** A tap within 600 ms of an ask appearing is ignored, and so is a press that began on another screen.
- **A question can only be answered, and an answer can only go to a question.** The board sends option numbers and typed text. The daemon turns numbers back into the original labels and refuses anything incomplete, and `hook.py` fills in answers for `AskUserQuestion` and nothing else.
- **Choosing takes two taps.** A tap only selects; **Send** answers. Both ignore a tap within 600 ms of the screen appearing.
- **Plans are terminal-only.** `ExitPlanMode` also fires the hook, but Allow would dismiss it without your answer. A question the board can't show in full is terminal-only too.
- **Other prompts are terminal-only.** Folder trust and other agents don't use this hook. Their text comes from the terminal and is only displayed.
- **Nothing counts down.** Take as long as you need to read a prompt. After 2 minutes without a touch the screen goes back to the queue, so Allow isn't left live on the desk. The prompt stays open and can be reopened from the board.

Tested against real Claude Code 2.1.316. These behaviours aren't all documented, so check them again after a major update:

| Situation | What Claude Code does |
|---|---|
| Hook still waiting | The terminal prompt is up and usable |
| Hook crashes, times out, or says nothing | The prompt stays open and nothing runs |
| Allow arrives after No was pressed in the terminal | Ignored |
| Yes pressed in the terminal | The hook is left running, so the daemon drops it once herdr says the pane moved on |
| No pressed in the terminal | The hook is stopped |
| Several tool calls at once | They ask one at a time, so a new request in a pane replaces the last |
| Allow with `answers` for a question | Claude gets them as your answers, including typed text and several questions at once |

## How it maps to herdr

| herdr | Board |
|---|---|
| `blocked` | needs you |
| `working` | working |
| `done` | done, until tapped ("seen"; kept in the daemon, so herdr's own state and focus are untouched) |
| `idle`, `unknown` | idle |

Tabs are `claude` CC, `codex` CX, `opencode` OC and `pi` PI. Other kinds show under ALL only.

## Known limits

- **Claude Code is the only agent with Allow and Deny.** Codex is terminal-only, as designed. OpenCode is terminal-only too, unlike the design: no real OpenCode prompt could be captured (its provider returned errors).
- **The keyboard types ASCII.** A label with an accent shows as `?` on the board, but Claude still gets the original. Typed answers on the board are limited to 200 characters.
- **The Error state never appears with live data.** herdr has no such state, so only `demo` shows it.
- **"Recent" reads Claude Code's session log (`daemon/activity.py`), here and over SSH.** It lists your prompts, tool calls, failures and what Claude said, and it changes nothing. Claude's docs call the log format internal, so a release could break it: the list then falls back to status changes. Codex, OpenCode and Pi only have status changes for now. Prompts and file names now show on the board, so anyone at your desk can read them.
- **Only sessions in herdr panes reach the board.** The hook does nothing elsewhere, so those prompts stay in their terminal.
- **Attach is untested on a pane that's on screen on the other machine.** herdr's docs say one direct attach owns a terminal's input and size, so that machine's view may resize until the window closes.
- **The board holds 24 sessions across all machines.** Past that, the ones that need you are kept.

## Design changes for the real panel

The design previews at 2x; the panel shows it at 1x, where some of the specified font sizes break up. Positions and line boxes follow the design. These are drawn at the nearest clean size (`tools/gen_fonts.py`):

| Design | Drawn at |
|---|---|
| Silkscreen 9 | 8 |
| VT323 14 and 16 | 15, with `m w M W 4 9` redrawn by hand |
| VT323 18 | 20 with tighter spacing, `f` redrawn by hand |
| Pixelify Sans 13 | 15 |
| Press Start 2P 12 (LINK LOST) | 16 |

The design's Idle board is now Bit's home screen, with its level above the clock. It appears after 30 s untouched, not after 60 s with every agent idle.

Added beyond the design: the swipe-up full view, row scrolling on the queue, machine names, the question screen and keyboard, the pet and its home screen, the "All clear" tile on Overview, and "runs herdr focus" in place of "runs focusCommand".

## Board notes

These are about the Waveshare board, in `firmware/boards/waveshare-esp32-c5-touch-lcd-2-8`.

- **Screen:** the UI redraws into an RGB565 framebuffer in internal RAM, 240x320 on this board. Only rows that changed go to the ST7789, over SPI at 80 MHz. On other boards the screens lay themselves out for any size from 170 to 480 pixels wide and 240 to 480 tall: see `firmware/boards`.
- **Reset and backlight:** both resets, the backlight and the speaker amp sit behind the CH32V003 at I2C 0x24. Waveshare's firmware on that chip stays as it is; flashing here only touches the ESP32-C5.
- **SD slot:** it shares the panel's SPI bus, so at boot any inserted card gets CMD0 to move it to SPI mode. A card left in SD mode can read pixel data as commands.
- **Panel gamma:** taken from the `touchreader` project (`rlcd/ereader/touchreader`), as are the touch and expander protocols.

## Serial protocol

One JSON object per line, on the board's USB port. Other lines, such as boot and panic output, are logged by the daemon and otherwise ignored.

| Direction | Message |
|---|---|
| Daemon to board | `state` once a second (sessions, local time, history of the watched session, pet counts), `ack` after an answer |
| Board to daemon | `hello`, `act` (allow, deny, answer, open, ask-mac, seen, and `pet-*`), `watch`, `touch` (logged) |
| Testing, via `ttycatd.py` | `shot PATH` saves the real frame as a PNG; `tap X Y`, `swipe L\|R\|U\|D`, `goto SCREEN` (`queue`, `overview`, `tab:N`, `ask:ID`, `detail:ID`, `pet`, `pet:heart`, `pet:reward`, `pet:level`, `pet:sleep`); in demo, `scene NAME` (including `question`, `questions`, `pet-asleep`, `pet-old`, `pet-birthday`, `pet-lv5`) |

**Only ttycat's own firmware can approve without being asked about.** A device that gives any other name in `hello`, or none, can see everything, open a session and Deny, but its `allow` and `answer` are refused, and it's told so with `na`, so the firmware shows "On Mac" where Allow was and brings the prompt up here. That's because it may have no way to show the whole prompt. For one that does, Setup > Firmware has **It can approve prompts**, off until you confirm, for that name only (`~/.ttycat/devices.json`). This guards against accidents. Each new build of your own asks again. It can't stop a device built to lie about its name.

`tap` goes through the same code as a finger, so anything on this Mac running as you can answer prompts the board is showing. The same is true of anything that can type into your terminal. The hook socket, `~/.ttycat/hook.sock`, is only readable by you.

The full protocol is in `docs/PROTOCOL.md`.

## Tests

```sh
python3 -m unittest discover -s daemon/tests
```

The hook tests run the real `hook.py` over a real socket, with payloads shaped like those captured from Claude Code.

The app's notification rules have their own tests. They run without Xcode, but need to be told where the command line tools keep the test macros:

```sh
cd app && swift test -Xswiftc -plugin-path -Xswiftc /Library/Developer/CommandLineTools/usr/lib/swift/host/plugins/testing
```

Fonts: Press Start 2P, Silkscreen, Pixelify Sans and VT323, all SIL Open Font License (`tools/fonts/OFL-*.txt`).

## Open source, and Pro

Everything in this repository is free and open source: seeing your agents, answering their prompts, notifications, the board and its firmware, and Bit. It's complete without anything else.

The official download adds paid features on top, kept in a separate private repository: usage and limits, a log of what agents did, other machines, and skins. They join through two small interfaces, `daemon/plugins.py` and `app/Sources/TTYCat/Extensions.swift`, and this code never depends on them.

## License

Apache-2.0: see `LICENSE` and `NOTICE`. What the app carries from others, and under which license, is in `THIRD_PARTY.md`. The license doesn't grant use of the product's name or logo.
