---
name: ttycat-flash
description: Put a firmware build on a real ttycat board and check that it works. Use when someone wants their change on the actual board. Never run without their yes.
---

# Put it on the board

Ask first. Say what you're about to do, and what will change:
- **This replaces what's on the board.** To undo it on the official board, Setup > Firmware > Replace with ttycat firmware puts back what the app carries. On any other board the app can't do that, so keep the last build that worked.
- **Approving moves to the Mac until they say otherwise.** Their build counts as custom, so it shows "On Mac" where Allow was, and Deny still works. To approve from the board, they turn on **It can approve prompts** in Setup, and every new build asks again. That's on purpose: don't work around it (rule 6).

Then:
1. Pack the build: `python3 tools/firmware_bundle.py firmware/build out` (or `build-NAME`).
2. With ttycat running, put it on the board: `python3 daemon/ttycatd.py flash out --replace`. `--replace` is there because this erases what's on it, so only use it with their yes. It finishes when the board itself says it's running the new build, and it refuses firmware made for a different board.
3. If nothing has ever said hello on that port, such as a new board, name it: `python3 daemon/ttycatd.py --port PORT flash out --replace`. Find it with `ls /dev/cu.*`. If there's more than one, ask which. Never guess: flashing the wrong port erases another device.
4. If it can't connect: hold BOOT on the board while plugging it in, and try again.
5. Setup > Firmware should now show the build's name as custom firmware.
6. Check the real screen: `python3 daemon/ttycatd.py shot out.png`, then look at it. `ttycatd.py goto pet` and `tap X Y` drive it. `tap` works like a finger and can answer a real prompt, so only use it when nothing's waiting (rule 5).

Don't change `FW_VERSION`, and don't set `FW_RELEASE`. Set `FW_LABEL` in `firmware/main/model.h` if they'd like their own name to show in Setup.
