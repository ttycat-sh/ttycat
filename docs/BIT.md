# Bit

Bit lives on the board's home screen and in the Mac app's **Bit** tab. There's nothing to look after: it's never hungry or sick, it can't die, and it's fine however long you leave it. What it has is a level, shown with how far it is to the next one and what that level brings. To go to Bit straight away, tap the **All clear** tile on Overview.

Rename it with `python3 daemon/ttycatd.py pet --name NAME` (11 characters), and see its stats with `ttycatd.py pet`.

It sleeps from 22:00 to 07:00, and when the screen dims, unless an agent is working: then it's at its laptop whatever the hour.

## How it grows

It grows with time and use, and you can't race it. Each day counts 1, whether or not the daemon was running. Your agents' tokens that day add up to 2 more, quickly at first and then less and less: 100k tokens add 0.79, 1M add 1.99, and past that almost nothing. Only your 5 biggest days of a week count, so working through the weekend gains nothing. That makes the crown 61 days away at best.

Level n starts at 3(n-1)²: level 2 takes 3, level 3 takes 12, level 4 takes 27, and so on. It earns a pilot's headset at level 3, an antenna at 5 and a crown at 8.

## What it never does

- **It never beeps.** The chime only ever means an agent needs you.
- **Your answers don't count.** It grows from time and tokens, and Allow and Deny make no difference, so nothing rewards saying yes.
- **Agents come first.** A new prompt or error leaves the home screen at once. Taps then don't count until they've stopped for 0.8 s, at least 1.5 s from the interruption, so nobody tapping away can hit Allow by accident.

## What time brings

- **Keepsakes.** It wears a party hat on the first of every month, its birthday, and gets a scarf to keep at 100 days old. Nothing can speed these up, they don't affect growth, and missing a birthday costs nothing.
- **A welcome after a day off.** The first touch or panel opening after a whole day with no agents, it greets you rested and happy, with a bigger hello after 3 days or more. That's all a day off does: it earns no growth, and nothing counts them.

## Where its numbers come from

Growth reads input and output tokens, never cache reads, from what Claude, Codex, OpenCode, Gemini and Pi record on this Mac. `~/.ttycat/token-days.json` keeps a number per day and where it got to in each log. An agent that doesn't record tokens adds nothing to growth. Tokens never leave the Mac.

Its state is in `~/.ttycat/pet.json`, so it survives reflashing. `demo` mode uses a separate Bit in memory.

## On the board and in the app

In the Mac app, the **Bit** tab has the same Bit, its level and what's next. A click on it pats it, which gets a heart and nothing more. It never sends a notification.

The two stay in step because neither one decides anything. The daemon numbers each reaction (`ev`, `evk` in the state), and both show the reaction when they see the number change, whichever one it came from. Both draw Bit by the same rules: at its laptop if an agent is working, otherwise asleep at night or when the board's screen is dim. The board tells the daemon when its screen dims, because Bit dozes then. The panel checks four times a second while the Bit page is open, so a tap on the board shows there within about a quarter of a second. Where Bit wanders on the board's screen isn't shared: that's idle animation, and the panel has no room to wander in.

A new prompt or error leaves the Bit page for Agents. A prompt's buttons then stay off for at least 1.5 s, and until clicks have stopped for 0.8 s, so nobody clicking away hits Allow by accident. They always wait for clicks to stop, however you got there, and opening the panel with something waiting shows that first.
