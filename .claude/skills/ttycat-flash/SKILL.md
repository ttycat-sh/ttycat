---
name: ttycat-flash
description: Put a firmware build on a real ttycat board and check that it works. Use when someone wants their change on the actual board. Never run without their yes.
---

# Put it on the board

Ask first. Say what you're about to do, and what will change:
- **This replaces what's on the board.** To undo it on the official board, Setup > Firmware > Replace with ttycat firmware puts back what the app carries. On any other board the app can't do that, so keep the last build that worked.
- **ttycat has to let go of the port for a moment**, so quit it first.
- **Answering stops until they say otherwise.** Their build counts as custom, so it can Deny but not approve. To approve from it, they turn on **It can approve prompts** in Setup, and every new build asks again. That's on purpose: don't work around it (rule 6).

Then:
1. Find the port: `ls /dev/cu.usbmodem*`. If there's more than one, ask which. Never guess: flashing the wrong port erases another device.
2. Have them quit ttycat from its menu.
3. `. ~/esp/esp-idf-v5.5.6/export.sh && cd firmware && idf.py -p PORT flash`, adjusting the path to where ESP-IDF is. For a board other than the Waveshare: `idf.py -B build-NAME -D BOARD=NAME -p PORT flash`.
4. If it can't connect: hold BOOT on the board while plugging it in, and try again.
5. Have them open ttycat again. Setup > Firmware should show the build's name as custom firmware.
6. Check the real screen: `python3 daemon/ttycatd.py shot out.png`, then look at it. `ttycatd.py goto pet` and `tap X Y` drive it. `tap` works like a finger and can answer a real prompt, so only use it when nothing's waiting (rule 5).

Don't change `FW_VERSION`, and don't set `FW_RELEASE`. Set `FW_LABEL` in `firmware/main/model.h` if they'd like their own name to show in Setup.
