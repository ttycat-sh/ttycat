# Waveshare ESP32-S3-Touch-AMOLED-2.16

A 2.16" 480x480 AMOLED with rounded corners. ttycat draws a 240x240 picture on it, each pixel 2x2.

## The board

| Part | What it is | Where it came from |
|---|---|---|
| Chip | ESP32-S3R8: 8 MB octal PSRAM, 16 MB flash, USB straight to the chip | `esptool.py flash_id` on the board |
| Screen | CO5300 over QSPI: CS 12, SCLK 38, D0 to D3 on 4 to 7, reset 39. No backlight: brightness is the panel's own command | Waveshare's BSP, `waveshare/esp32_s3_touch_amoled_2_16` on components.espressif.com |
| Glass | Rounded corners, a smooth curve 95 panel pixels along each edge: `CORNER_RADIUS 96` | Waveshare's dimension drawing (DXF) in github.com/waveshareteam/ESP32-S3-Touch-AMOLED-2.16 |
| Touch | CST9220 at 0x5A on I2C (SDA 15, SCL 14), interrupt 11, reset 40. Turned as the panel is: x = 479 - raw y, y = raw x | The BSP, and Waveshare's Arduino demo |
| Sound | ES8311 codec (I2S: MCLK 42, BCLK 9, WS 45, DOUT 8) and an NS4150B amp on GPIO 46, to a 2-pin speaker socket. No speaker comes on the board | The BSP, and the schematic |
| Power | An AXP2101, but the screen runs straight from 3.3 V, so it needs no setting up | The schematic |

The CO5300 needs every area it's sent to start on an even pixel and end on an odd one, which a 2x zoom always does. It may ignore the usual quarter-turn setting, so a sideways stand would need turning in software.

## Checked on the real board

On 2026-11-05 and 06, by the first ported build and its corner fix:
- It starts cleanly, connects to the Mac, shows the sessions, and dims after two minutes.
- The screens match the gallery at 240x240.
- Nothing is cut off by the corners, as seen on the glass.

Not checked yet: taps in all four corners, Deny, "On Mac" and Allow on a real prompt, and the chime with a speaker plugged in.

## Its first port

`docs/ports/2026-11-05-waveshare-esp32-s3-touch-amoled-2-16.md` tells the whole story, with everything that went wrong.
