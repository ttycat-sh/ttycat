# Waveshare ESP32-C5-Touch-LCD-2.8

ttycat's official board: a 2.8" 240x320 LCD with capacitive touch. ttycat draws its picture at the panel's own size, with no zoom. Signed releases are built for this board only.

## The board

| Part | What it is |
|---|---|
| Chip | ESP32-C5, USB straight to the chip |
| Screen | ST7789 over SPI at 80 MHz. The UI draws into an RGB565 framebuffer in internal RAM, and only the rows that changed are sent |
| Touch | CST3530 on I2C, read when its interrupt says so |
| Reset, backlight and speaker amp | Behind a CH32V003 at I2C 0x24. Waveshare's firmware on that chip stays as it is: flashing ttycat only touches the ESP32-C5 |
| microSD slot | On the panel's SPI bus. At boot, any card in the slot gets CMD0, which moves it to SPI mode. A card left in SD mode could read pixel data as commands |

## Where the details came from

The panel's voltages and gamma, the touch controller and the expander are set up as in Waveshare's Arduino driver. With the ST7789's own voltages and gamma, the colours look washed out.

## Fonts on this panel

The screens were designed at twice this panel's size, and at 1x some font sizes break up into dots. Positions and line boxes stay as designed, and these are drawn at the nearest clean size instead, by `tools/gen_fonts.py`:

| Designed at | Drawn at |
|---|---|
| Silkscreen 9 | 8 |
| VT323 14 and 16 | 15, with `m w M W 4 9` redrawn by hand |
| VT323 18 | 20 with tighter spacing, `f` redrawn by hand |
| Pixelify Sans 13 | 15 |
| Press Start 2P 12 (LINK LOST) | 16 |

Every board gets these fonts, so a board at another size is drawn with them too.
