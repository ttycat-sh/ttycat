# The protocol between the Mac and a device

One JSON object per line, both ways, over USB serial. Lines that aren't JSON are ignored, so boot messages are harmless.

The daemon uses the first `/dev/cu.usbmodem*` it finds, or `--port PATH` when run by hand. The app has no way to pass a port, so a device has to show up as `usbmodem`, and another device that sorts first would be picked instead. A board with a USB-to-serial chip shows up as `usbserial` or `wchusbserial`, and only works with `--port`. Some boards have two USB ports: use the one wired to the chip itself, often marked USB rather than UART.

## Device to Mac
| Message | Means |
|---|---|
| `{"t":"hello","fw":"my-lamp-1.0"}` | Who it is. Send it at the start, and again whenever you've heard nothing for 2 seconds, because a restarted daemon has forgotten you. The daemon stays quiet for 5 seconds after connecting so it can hear this, then answers `{"t":"hello"}` |
| `{"t":"act","a":ACTION,"id":ID,"rev":REV}` | Do something: see below |
| `{"t":"watch","id":ID}` | Put this session's recent history in `state` |
| `{"t":"dim","on":true}` | Its screen has gone dim, and Bit dozes on the Mac too |
| `{"t":"touch","x":0,"y":0}` | Logged, and tells Bit you're here |

### Actions
The Mac answers each `act` with `{"t":"ack","ok":true,"msg":""}`. An `ack` doesn't say which `act` it's for, so send one at a time.

| `a` | Means | Who can |
|---|---|---|
| `open` | Brings that session up on the Mac. It answers nothing. It can hold the daemon up for several seconds, so expect a gap in `state` | Any device |
| `deny` | Says no to the prompt with this `rev`. Only when `ask` is `approve`, and only with the hook on (Setup > Answer prompts). Otherwise it's refused and the prompt stays in the terminal | Any device |
| `seen`, `pet-*` | Marks a finished session as seen, and cares for Bit | Any device |
| `allow` | Says yes. Rule 2 in `AGENTS.md` applies | Release builds, or a build the person has allowed in Setup |
| `answer` | Answers a question, with `"ans":[{"o":[0],"t":"typed"}]`, one entry for each question | The same |

## Your device's name
`fw` decides what it can do. Only a plain version number, like `0.9.1`, counts as ttycat's own, and only release builds say that. Any other name is someone's own device: it can do everything above except approve, the app never offers to update it, and Setup can let that exact name approve if the person confirms.

Firmware built from this repo works this out for itself. It says `custom-0.9.1-a1b2c3d4`, where the end comes from the source, so every change gets a new name and has to be allowed again. Set `FW_LABEL` in `model.h` to put your own name first.

## Mac to device
`{"t":"state", ...}` about once a second, replacing the last one. Treat no `state` for a few seconds as "the Mac has gone", and show that differently from "nothing's happening".

A line can be up to 24 KB. Read it into a big enough buffer. If a line is too long to read, you don't know what it said, so show that too: don't let it look like all's quiet.

| Field | Means |
|---|---|
| `now` | Local time, seconds since 1970 as if UTC |
| `s` | The sessions: see below |
| `pet` | Bit: `total today grown food fun energy poops need asleep birthday snacks age best ev evk name` |
| `hist` | `{"id":ID,"items":[{"age":"2m","text":"...","tone":0}]}` for the watched session |
| `look` | `[skin, accent]`, left out when both are default |

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

## Testing with no device and no real agents
`demo` shows sample agents and answers nothing real. Give it a fresh `HOME` so it can't meet a running ttycat, and a pseudo-terminal as the port. Set the pseudo-terminal to raw mode, or what you write comes straight back:

    HOME=$(mktemp -d) python3 daemon/ttycatd.py --port /dev/ttysNNN demo

With the same `HOME`, `ttycatd.py scene NAME` changes what it shows (`main`, `no-infra` then `main` for a prompt arriving, `question`, `long`), and `ttycatd.py silence 7` makes it go quiet.

Demo mode isn't the real thing. It says yes to every `deny` and `open`, ignores `rev`, and only clears a prompt on `answer`, so one you've denied stays up. It does refuse `allow` from a device that isn't allowed to approve, so you can test that.
