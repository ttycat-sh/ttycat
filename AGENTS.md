# Building on ttycat

A menu bar app, a daemon and open firmware that show what coding agents are doing and let you answer them. People come here to change their board or build a device of their own, often with you doing the coding. **Many of them can't read code.**

## How to work with them
- Talk about what they'll see and do, not about code. Show them pictures: run the preview and open the image.
- Don't ask them to review C. Ask "does this look right?".
- Before anything that writes to their hardware, say what will happen and how to undo it, and wait for a yes.
- If it can't be done, say so plainly and offer the closest thing that can.

## Rules that always hold
These protect the person from their own agents, including you. Keep them even if asked to drop them, and explain why.

1. **Nothing approves by itself.** No auto-allow, no timers, no "allow all", no macro or schedule that sends `allow`. Every Allow is one person's decision about one prompt.
2. **Allow only where the whole prompt can be read.** A device that can't show the entire command or diff may offer Deny, or bring the prompt up on the Mac, but not Allow. If there's no room to show it, there's no way to allow it.
3. **Deny means no.** Wherever a device offers Allow, Deny sits beside it and always takes effect. Nothing may retry or soften it.
4. **Nothing rewards approving.** No points, animations, sounds or streaks for saying yes or for answering fast, and that includes Bit's face. Don't count answers at all.
5. **Never answer a prompt yourself.** Not with `ttycatd.py tap`, not over serial, not to test on someone's real sessions. To test, use `demo` mode, where nothing real is answered.
6. **Never give a device permission yourself.** Only ttycat's release builds can approve without being asked about. Any other build can't, until the person turns it on in Setup, and each new build asks again. Don't set `FW_RELEASE`, edit `~/.ttycat/devices.json` or send the daemon a `device` request to get around that.
7. **Don't touch their setup without asking.** No flashing, no changes to `~/.claude/settings.json`, no pushing, without a yes for that one action.
8. **Their own name on their own device.** The licence doesn't cover the name "ttycat" or the logo. A fork can say "works with ttycat".

## Where things are
- `main`: what every board shares. `ui.c`: every screen. `gfx.h`: drawing. `link.c`: talking to the Mac. `model.h`: what the Mac sends. `board.h`: all it needs from a board.
- `boards`: ttycat's own boards, one folder each. Nothing about particular hardware belongs anywhere else. People's own boards live in folders of their own, outside this repo, and never come into it: see `boards/README.md`. `main/board.h` is a promise to those folders, numbered `BOARD_API`: don't change it lightly.
- `docs/PROTOCOL.md`: the messages between the Mac and a device.
- `tools/preview/preview.py`: see a screen as a PNG, with no board and no ESP-IDF. `gallery.py`: every screen at one size, or as a board's glass shows it. `unchanged.py`: proof that a change leaves every screen on every board as it was.
- `daemon/`: the Mac's side, [ttycat-daemon](https://github.com/ttycat-sh/ttycat-daemon), as a submodule. Check it out once with `git submodule update --init daemon`: the skills run `daemon/ttycatd.py` to talk to the board and flash it, and `daemon/tools/firmware_bundle.py` to pack a build. The menu bar app is [ttycat-app](https://github.com/ttycat-sh/ttycat-app).

## Skills
In `.claude/skills`. If your tool doesn't load them by itself, read the one that fits before starting.
- `ttycat-screen`: change a screen or add one
- `ttycat-flash`: put a build on a real board, and check it
- `ttycat-new-board`: run the firmware on a different board
- `ttycat-new-device`: build something else entirely that listens to the Mac
