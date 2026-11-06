# The protocol between the Mac and a device

One JSON object per line, both ways, over USB serial. Lines that aren't JSON are ignored, so boot messages are harmless.

The daemon looks at `/dev/cu.usbmodem*`, then `usbserial*`, `wchusbserial*` and `SLAB_USBtoUART*`, and stays with the first that says hello. Each port gets one try of 6 seconds, because opening a port can restart what's on it. One that says nothing is left alone until it's unplugged, and it's sent nothing at all. When run by hand, `--port PATH` picks one.

A USB-to-serial chip runs at 230400 baud. Over USB straight to the chip, the speed doesn't matter. Some boards have two USB ports, and either can work, as long as the firmware is set up for the one you use.

## Device to Mac
| Message | Means |
|---|---|
| `{"t":"hello","fw":"my-lamp-1.0","b":"my-board","p":1,"art":1,"id":"a1b2c3d4e5f6","nm":"desk cat"}` | Who it is. `fw` is its build, `b` the board's folder, if it has one, `p` the protocol version it speaks, and `art` the art format it draws, if it draws any. `id` is its chip's own ID, 12 lowercase hex digits, such as its MAC address: a device that says one keeps the name the person gave it, and says it in `nm` once it has one (see "Your device's name"). Send it at the start, and again whenever you've heard nothing for 2 seconds, because a restarted daemon has forgotten you. The daemon answers `{"t":"hello","p":1}`, and sends nothing else until it's heard one |
| `{"t":"act","a":ACTION,"id":ID,"rev":REV}` | Do something: see below |
| `{"t":"watch","id":ID}` | Put this session's recent history in `state` |
| `{"t":"dim","on":true}` | Its screen has gone dim, and Bit dozes on the Mac too |
| `{"t":"touch","x":0,"y":0}` | Logged, and tells Bit you're here |
| `{"t":"need","what":"art"}` | `state` names art it hasn't got, because its line was lost: send it again. Ask at most once every 10 seconds |

### Actions
The Mac answers each `act` with `{"t":"ack","ok":true,"msg":""}`. An `ack` doesn't say which `act` it's for, so send one at a time.

| `a` | Means | Who can |
|---|---|---|
| `ask-mac` | Brings that prompt up in the Mac's panel, to be answered there. It's what a board shows instead of Allow when `na` is set | Any device |
| `open` | Brings that session up in its terminal on the Mac. It answers nothing. It can hold the daemon up for several seconds, so expect a gap in `state` | Any device |
| `deny` | Says no to the prompt with this `rev`. Only when `ask` is `approve`, and only with the hook on (Setup > Answer prompts). Otherwise it's refused and the prompt stays in the terminal | Any device |
| `seen`, `pet-pat`, `pet-here` | Marks a finished session as seen, gives Bit a heart, or says someone's here for its greeting | Any device |
| `allow` | Says yes. Rule 2 in `AGENTS.md` applies | Release builds, or a build the person has allowed in Setup. Otherwise `state` has `na` |
| `answer` | Answers a question, with `"ans":[{"o":[0],"t":"typed"}]`, one entry for each question | The same |

## The protocol version
`p` goes up only when a change would break a device that's already built. A new field doesn't count, so ignore fields you don't know. If `p` doesn't match, the daemon answers `hello` and sends nothing else, and Setup says the firmware needs rebuilding.

## Your device's name
`fw` decides what it can do. Only a plain version number, like `0.9.1`, counts as ttycat's own, and only release builds say that. Any other name is someone's own device: it can do everything above except approve, the app never offers to update it, and Setup can let that exact name approve if the person confirms.

Firmware built from this repo works this out for itself. It says `custom-0.9.1-a1b2c3d4`, where the end comes from the source, so every change gets a new name and has to be allowed again. Set `FW_LABEL` in `model.h` to put your own name first.

The person can also name the device itself in Setup, such as "desk cat". That's only what the app calls it: approving still goes by `fw`, never by this name. The Mac sends `{"t":"name","name":"desk cat"}`, or `""` to take it away. A device that says `id` keeps it somewhere a new build doesn't erase, such as NVS, and says it in its hello's `nm` from then on. A name is up to 32 bytes of UTF-8, with no control characters, `"` or `\`, so it needs no escaping. Refuse anything else, and say `name: not kept`. The Mac keeps a copy, and sends it again to a device that says `id` but no `nm`, such as one whose storage was erased. A device that doesn't say `id` is named on the Mac only, and two of the same board share its name.

## Mac to device
`{"t":"state", ...}` about once a second, replacing the last one. Treat no `state` for a few seconds as "the Mac has gone", and show that differently from "nothing's happening".

A line can be up to 24 KB. Read it into a big enough buffer. If a line is too long to read, you don't know what it said, so show that too: don't let it look like all's quiet.

| Field | Means |
|---|---|
| `now` | Local time, seconds since 1970 as if UTC |
| `s` | The sessions: see below |
| `pet` | Bit: `total today grown asleep birthday age ev evk name`. `grown` is what its level comes from: level n starts at 3(n-1)² |
| `hist` | `{"id":ID,"items":[{"age":"2m","text":"...","tone":0}]}` for the watched session |
| `look` | `[skin, accent]`, numbers into the tables in `gfx.c`, or `["#rrggbb","#rrggbb","#rrggbb"]`: body, shade and accent. Left out when it's the default |
| `art` | The id of the art Bit's stage shows. Show only that: drop art it doesn't name, and ask with `need` for art you haven't got |
| `na` | True if this device can't approve yet. Offer `ask-mac` instead of Allow |

Each session in `s`:
| Field | Means |
|---|---|
| `id` | Identifies the session |
| `a`, `n` | Agent code (`CC`, `CX`, `OC`, `PI`) and name |
| `p`, `host` | Project, and the machine if it isn't this Mac |
| `s` | `blocked` (needs you), `error`, `done`, `working` or `idle` |
| `age` | Seconds in this state |
| `d` | One line about what it's doing. An idle agent says "waiting for prompt", which doesn't mean it's waiting on you: only `s` tells you that |
| `ask` | `approve`: Allow and Deny work. `choice`: a question, in `qs`. `terminal`: can only be answered at the Mac. Absent: nothing to answer |
| `tool`, `verb`, `body`, `file`, `add`, `del` | The prompt: `BASH`, "wants to run", the whole command or diff (up to 1000 characters: a longer one isn't offered) |
| `rev` | Identifies this exact prompt. Send it back with an answer, so an answer can't land on a different prompt |
| `note` | Why this can't be answered here |

`error` can also mean a machine it can't reach (`p` is "not reachable"), so its agents could be waiting on you. Don't treat `error` as nothing going on.

## Art

Art for Bit's stage, such as a season's, sent only to a device whose hello says `art`, and only in a format it said it draws. It comes after each hello, before the `state` that names it, and whenever it changes. Keep it in RAM: it's sent again after every reconnect.

```jsonc
{"t":"art", "id":"test-snow", "f":1,
 "pal": ["#f2f6ff", "#e0484f"],                     // colours 1 to 15
 "sp": [{"w":14, "h":2, "px":["22222222222222", ".........22..."]},
        {"w":1, "h":1, "px":["1"]},
        {"w":8, "h":3, "ms":500, "px":["...11...", ".222222.", "22222222",
                                       "....11..", ".222222.", "22222222"]}],
 "wear": [{"sp":0, "on":"neck", "x":1, "y":0, "not":["work"]}, {"sp":2, "on":"head", "x":4, "y":-3}],
 "set":  [{"sp":2, "on":"right", "x":2, "y":0}],
 "fall": {"sp":1, "n":18, "vy":6, "vx":-1, "sway":2},
 "say":  "First snow"}
```

Everything is in Bit's dots, never the screen's pixels, so it's the same size on Bit on any screen.

| Field | Means |
|---|---|
| `id` | 1 to 11 letters, digits and dashes |
| `f` | The art format it uses. Format 1 is everything here |
| `pal` | Up to 15 colours. In a sprite's rows they're `1` to `9` and `a` to `f`, and `.` is clear |
| `sp` | Up to 8 sprites, each up to 32 by 32 dots. More rows than `h` are frames, up to 4, shown `ms` apart: 0 is still. Every sprite's dots together, frames included, up to 8192 |
| `wear` | On Bit, at a row of its body: `head` (row 1), `face` (5), `body` (8) or `neck` (10), one each. `x` is from its left edge, `y` from the top of the row. `not` hides it while Bit's in any of `nap`, `work`, `walk`, `hop`. A `head` replaces the antenna or crown it's earned, and a `neck` its scarf. Its birthday hat beats a `head` |
| `set` | Up to 4 on the stage, behind Bit: `on` is `left`, `centre` or `right` on the ground, `x` in from there and `y` up, or `sky`, `y` down from under the header. A piece that doesn't fit the stage isn't drawn |
| `fall` | Up to 24 of one sprite drifting past, behind Bit, at `vy` and `vx` dots a second (-40 to 40: a negative `vy` rises), each swinging `sway` dots (up to 8) |
| `say` | Up to 24 printable ASCII characters in the banner, for 4 seconds: when Bit's screen opens, at most once an hour, after a greeting, and when new art comes. Never on its birthday |

**A device must keep these rules,** whatever it's sent:
- Draw it only on Bit's stage: never on a prompt, a question, a diff, the keyboard or the queue.
- Nothing in it reacts to an answer, and nothing may be made to: the format has no such field.
- Anything outside the limits, or that isn't as above, and the whole message is dropped. Never show part of one.
- Ignore fields you don't know.

A new kind of drawing is a new format. The protocol's `p` stays the same, because devices built before it still work: they just get less. The daemon checks only the basics (`daemon/art.py`), and the device checks everything (`firmware/main/art.c`). To try some art, `ttycatd.py art FILE` shows it until the daemon stops, and `ttycatd.py art off` takes it away. To see it at any size before flashing, `tools/preview/gallery.py out.png --art FILE`.

## Testing with no device and no real agents
`demo` shows sample agents and answers nothing real, and it needs a hello with the right `p` like anything else. Give it a fresh `HOME` so it can't meet a running ttycat, and a pseudo-terminal as the port. Set the pseudo-terminal to raw mode, or what you write comes straight back:

    HOME=$(mktemp -d) python3 daemon/ttycatd.py --port /dev/ttysNNN demo

With the same `HOME`, `ttycatd.py scene NAME` changes what it shows (`main`, `no-infra` then `main` for a prompt arriving, `question`, `long`), and `ttycatd.py silence 7` makes it go quiet.

Demo mode isn't the real thing. It says yes to every `deny` and `open`, ignores `rev`, and only clears a prompt on `answer`, so one you've denied stays up. It does refuse `allow` from a device that isn't allowed to approve, so you can test that.
