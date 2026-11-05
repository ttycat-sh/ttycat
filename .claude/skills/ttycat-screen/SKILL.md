---
name: ttycat-screen
description: Change a screen on the ttycat board or add a new one, such as a bigger clock, a new home screen or a screen for one project. Use when someone wants the board to look or behave differently.
---

# Change or add a screen

1. Ask what they want to see, in their words. If it isn't in `firmware/main/model.h`, say so: the board only knows what the Mac sends it, and has no internet of its own.
2. See how it looks now: `python3 tools/preview/preview.py now.png --goto pet`. Open the image.
3. Make the change in `firmware/main/ui.c`. A new screen needs a value in `screen_t`, a `draw_...` function, a case in the `switch` in `ui_tick`, a way in and a way back. Tap areas are `hit(...)` calls inside the draw function, with an action in `action_t`. Add a name in `handle_goto` too, so it can be previewed.
4. Preview it and look at the image yourself. Fix clipped text, overlaps and anything off the edge. Check `--scene quiet`, `one`, `asks` and `lots`, and `--then one` for a prompt arriving while it's open.
5. Show them the picture and ask if it's right. Repeat.
6. Check it builds for the real chip: `. ~/esp/esp-idf-v5.5.6/export.sh && cd firmware && idf.py build`, adjusting the path to where ESP-IDF is. If it isn't installed, say it's a large download (about 5 GB with every chip's tools) and ask first.
7. Putting it on the board is `ttycat-flash`.

## How the board behaves
- **Home is `SCR_PET`** (`pet` in the preview). When something needs you it leaves by itself for the queue, so home is never on screen while anything's waiting. A screen about what's waiting needs a way in from the queue too.
- **What "waiting" means:** `state == ST_BLOCKED`. `need_total()` also counts `ST_ERROR`, so say which you're counting. An idle agent's text says "waiting for prompt", but it isn't waiting on the person.
- **A new screen stays up until told otherwise.** The end of `step_navigation` is what goes home after 30 seconds (the `between` list) and what dims (only `SCR_PET`). Choose, and tell the person what you chose.
- **A new prompt must never go unnoticed.** The chime is in `notice_new_asks` and always plays. After that, a screen either gives way to the queue (see `SCR_PET` and `SCR_GAME` there), or stays up and shows clearly that something's waiting, with one tap to reach it.
- **Prompt screens stay as they are** unless that's what was asked for: rules 2 and 3 in `AGENTS.md`.

## Drawing
- Draw with `gfx.h`, on whole pixels, on a 240x320 screen. Reuse the fonts in `fonts.h` and the colours at the top of `ui.c`.
- The biggest font is `ps40`, 40 px tall. For anything bigger, draw its dots as blocks yourself. Letters can have a blank row in their box, so line things up by looking at the picture.
- **Bit:** `pet_draw` walks across the whole screen at a fixed height, so it only suits a full-width stage. `pet_worker(now, x, y, dot, seed)` draws Bit at its laptop anywhere, at any size. For Bit standing still, write a small function in `pet.c` from the sprites there.
- Bit's mood mustn't follow how anyone answered, or how fast: rule 4.
