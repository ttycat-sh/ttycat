# Third-party software

What the firmware builds on, and under which license. Check this list before each release. What the Mac app carries is listed in [ttycat-app](https://github.com/ttycat-sh/ttycat-app/blob/main/THIRD_PARTY.md).

| What | Used for | License | Where |
|---|---|---|---|
| [ESP-IDF](https://github.com/espressif/esp-idf), esp_codec_dev | The firmware | Apache-2.0; see each component | Firmware image |
| Press Start 2P, VT323, Silkscreen, Pixelify Sans | The look of the board | SIL OFL 1.1: `tools/fonts/OFL-*.txt` | `main/fonts.c`, generated from them by `tools/gen_fonts.py` |
