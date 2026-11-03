# Third-party software

What ttycat carries or builds on, and under which license. Check this list before each release.

| What | Used for | License | Where |
|---|---|---|---|
| CPython, from [python-build-standalone](https://github.com/astral-sh/python-build-standalone) | Runs the daemon, in the app | PSF-2.0, plus the licenses of what it statically links (OpenSSL and others): see its `LICENSE` files in `Resources/python` | Bundled by `app/vendor.sh` |
| [esptool](https://github.com/espressif/esptool) 4.12 | Writes firmware to the board | **GPL-2.0-or-later**. It runs as a separate program and isn't linked. Its source must stay available: <https://github.com/espressif/esptool/tree/v4.12.0> | Bundled by `app/vendor.sh` |
| [pyserial](https://github.com/pyserial/pyserial) 3.5 | Used by esptool | BSD-3-Clause | Bundled by `app/vendor.sh` |
| [IntelHex](https://github.com/python-intelhex/intelhex) 2.3 | Used by esptool | BSD-3-Clause | Bundled by `app/vendor.sh` |
| [herdr](https://github.com/herdrdev/herdr)'s agent detection rules, and a port of its engine | What an agent's screen means | Apache-2.0: `daemon/agent_rules.LICENSE` | `daemon/agent_rules.json`, `daemon/screen_rules.py` |
| Press Start 2P, VT323, Silkscreen, Pixelify Sans | The look of the app and board | SIL OFL 1.1: `tools/fonts/OFL-*.txt` | App resources; firmware fonts generated from them |
| [ESP-IDF](https://github.com/espressif/esp-idf), esp_codec_dev | Firmware | Apache-2.0; see each component | Firmware image |

ttycat doesn't include or modify Claude Code, Codex or herdr. It reads what they record and uses their documented hooks. "Claude", "Codex" and "herdr" are their owners' names, and none of them endorses this.
