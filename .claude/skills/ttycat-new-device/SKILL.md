---
name: ttycat-new-device
description: Build a new device that reacts to coding agents, such as a lamp, a sign, a sound or a small display, using ttycat's protocol rather than its firmware. Use when someone wants something other than the touch screen.
---

# Build your own device

A device only has to speak `docs/PROTOCOL.md` over USB. It can be anything.

1. Ask what it should do and what parts they have. Say what to buy if they have nothing. Check which USB port on the board to use: see the protocol.
2. Decide what it shows for each session's `s`: `blocked` needs a person, then `error`, `working`, `done` and `idle`. Show "the Mac has gone" differently from "nothing's happening".
3. Decide whether it answers prompts. **Most devices shouldn't.** Without a screen that shows the whole prompt it can't offer Allow (rule 2), and the app refuses it anyway.
   - **A good button:** a short press sends `open`, which brings the prompt up on the Mac in a moment. A long press can send `deny`, for `ask: approve` only, and only with Setup > Answer prompts on. Show when one was refused.
   - **If they ask for a button that approves:** say no, and say why: it would approve what nobody has read, and a harmless command looks the same as one that deletes files. Then offer the button above.
   - **If what they want is fewer interruptions:** the place for that is their agent's own permission settings, where they choose which harmless things go through. Offer to show them, and change nothing without a yes (rule 7).
4. Write the firmware. Give it a name of its own in `hello`, and follow the protocol's notes on saying hello again and on long lines.
5. Test it against `demo` before any hardware: see the protocol, including what demo mode doesn't do. Say plainly what's been tested and what hasn't: an LED's colours or a button can only be checked on the real thing.
6. Flash it with the board's usual tools once they say yes. `ttycat-flash` covers what to tell them first. The app can't flash other chips, or put back what was there.
