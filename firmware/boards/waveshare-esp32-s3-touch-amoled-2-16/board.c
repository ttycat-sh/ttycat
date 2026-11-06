// The Waveshare ESP32-S3-Touch-AMOLED-2.16: a 480x480 CO5300 AMOLED on QSPI, CST9220 touch on I2C.
// Pins, the panel's start-up commands and the way round it stands are from Waveshare's own board
// support package (waveshare/esp32_s3_touch_amoled_2_16 2.0.1) and the board's schematic.
#include <stdlib.h>

#include "amoled.h"
#include "board.h"
#include "driver/gpio.h"
#include "driver/i2c_master.h"
#include "driver/spi_master.h"
#include "esp_attr.h"
#include "esp_err.h"
#include "esp_heap_caps.h"
#include "esp_lcd_co5300.h"
#include "esp_lcd_panel_io.h"
#include "esp_lcd_panel_ops.h"
#include "esp_lcd_touch_cst9217.h"
#include "esp_log.h"
#include "freertos/FreeRTOS.h"
#include "freertos/semphr.h"
#include "freertos/task.h"
#include "gfx.h"

static const char *TAG = "board";

enum {
  PIN_LCD_DATA0 = 4,
  PIN_LCD_DATA1 = 5,
  PIN_LCD_DATA2 = 6,
  PIN_LCD_DATA3 = 7,
  PIN_TOUCH_INT = 11,
  PIN_LCD_CS = 12,
  PIN_SCL = 14,
  PIN_SDA = 15,
  PIN_LCD_SCLK = 38,
  PIN_LCD_RST = 39,
  PIN_TOUCH_RST = 40,
};

// 480x480 at 2.16 inches: board_check.py picks a 240x240 picture, each of its pixels 2x2.
#define PANEL_W 480
#define PANEL_H 480
#define ZOOM 2

// The glass's rounded corners, in the panel's pixels. Waveshare's drawing of this board
// (dimensions/ESP32-S3-Touch-AMOLED-2.16-2D-20260209.dxf) has the 38.99 mm active area's corners as a
// smooth curve, not a circle, starting 7.749 mm (95 px) from each corner. 96 is the smallest circle
// that hides at least as much as that curve everywhere, rounded up to a whole picture pixel.
#define CORNER_RADIUS 96

// The picture goes to the screen a band at a time, and only the bands that changed. Two buffers, so
// one band is zoomed while the one before is still on its way to the panel.
#define ROWS_AT_ONCE 8
#define BUFS 2
static uint16_t *rows_out[BUFS];
static uint32_t *band_hash;
static int bands;
static bool bands_valid;

static i2c_master_bus_handle_t bus;
static esp_lcd_panel_io_handle_t lcd_io;
static esp_lcd_panel_handle_t panel;
static esp_lcd_touch_handle_t touch;
static SemaphoreHandle_t lcd_done;
static int in_flight;

// Waveshare's start-up for this panel, less the turn (done below with swap_xy and mirror), with the
// brightness at 0 and the display left off until the first frame is on it.
static const co5300_lcd_init_cmd_t lcd_init_cmds[] = {
    {0x11, NULL, 0, 600},  // sleep out
    {0xFE, (uint8_t[]){0x20}, 1, 0},
    {0x19, (uint8_t[]){0x10}, 1, 0},
    {0x1C, (uint8_t[]){0xA0}, 1, 0},
    {0xFE, (uint8_t[]){0x00}, 1, 0},
    {0xC4, (uint8_t[]){0x80}, 1, 0},
    {0x35, (uint8_t[]){0x00}, 1, 0},
    {0x53, (uint8_t[]){0x20}, 1, 0},
    {0x51, (uint8_t[]){0x00}, 1, 0},  // brightness 0 until there's something to see
    {0x63, (uint8_t[]){0xFF}, 1, 0},
    {0x2A, (uint8_t[]){0x00, 0x00, 0x01, 0xDF}, 4, 0},
    {0x2B, (uint8_t[]){0x00, 0x00, 0x01, 0xDF}, 4, 0},
};

i2c_master_bus_handle_t board_i2c(void) { return bus; }

static bool IRAM_ATTR lcd_flushed(esp_lcd_panel_io_handle_t io, esp_lcd_panel_io_event_data_t *e, void *arg) {
  BaseType_t woken = pdFALSE;
  xSemaphoreGiveFromISR(lcd_done, &woken);
  return woken == pdTRUE;
}

static void i2c_begin(void) {
  i2c_master_bus_config_t bc = {
      .i2c_port = I2C_NUM_0,
      .sda_io_num = PIN_SDA,
      .scl_io_num = PIN_SCL,
      .clk_source = I2C_CLK_SRC_DEFAULT,
      .glitch_ignore_cnt = 7,
      .flags.enable_internal_pullup = true,
  };
  ESP_ERROR_CHECK(i2c_new_master_bus(&bc, &bus));
}

static void lcd_begin(void) {
  lcd_done = xSemaphoreCreateCounting(BUFS, 0);
  const spi_bus_config_t bc = CO5300_PANEL_BUS_QSPI_CONFIG(PIN_LCD_SCLK, PIN_LCD_DATA0, PIN_LCD_DATA1, PIN_LCD_DATA2,
                                                           PIN_LCD_DATA3, PANEL_W * ROWS_AT_ONCE * ZOOM * 2);
  ESP_ERROR_CHECK(spi_bus_initialize(SPI2_HOST, &bc, SPI_DMA_CH_AUTO));
  esp_lcd_panel_io_spi_config_t ioc = CO5300_PANEL_IO_QSPI_CONFIG(PIN_LCD_CS, lcd_flushed, NULL);
  ioc.trans_queue_depth = 4;
  ESP_ERROR_CHECK(esp_lcd_new_panel_io_spi((esp_lcd_spi_bus_handle_t)SPI2_HOST, &ioc, &lcd_io));
  co5300_vendor_config_t vc = {
      .init_cmds = lcd_init_cmds,
      .init_cmds_size = sizeof(lcd_init_cmds) / sizeof(lcd_init_cmds[0]),
      .flags.use_qspi_interface = 1,
  };
  esp_lcd_panel_dev_config_t pc = {
      .reset_gpio_num = PIN_LCD_RST,
      .rgb_ele_order = LCD_RGB_ELEMENT_ORDER_RGB,
      .bits_per_pixel = 16,
      .vendor_config = &vc,
  };
  ESP_ERROR_CHECK(esp_lcd_new_panel_co5300(lcd_io, &pc, &panel));
  ESP_ERROR_CHECK(esp_lcd_panel_reset(panel));
  ESP_ERROR_CHECK(esp_lcd_panel_init(panel));
  // MADCTL 0xA0, as Waveshare's board support package sends it, with the touch turn it pairs with in
  // board_touch. Their Arduino demo leaves MADCTL at 0 with the same touch turn, so the CO5300 may well
  // ignore these bits (its own flips are 0x02 and 0x05 in Arduino_GFX): to turn the picture a quarter,
  // check on the board, and expect to do it in board_flush rather than here.
  ESP_ERROR_CHECK(esp_lcd_panel_swap_xy(panel, true));
  ESP_ERROR_CHECK(esp_lcd_panel_mirror(panel, false, true));
}

static void touch_begin(void) {
  esp_lcd_panel_io_handle_t tio;
  esp_lcd_panel_io_i2c_config_t tc = ESP_LCD_TOUCH_IO_I2C_CST9217_CONFIG();
  tc.scl_speed_hz = 400000;
  ESP_ERROR_CHECK(esp_lcd_new_panel_io_i2c(bus, &tc, &tio));
  // No turning here: board_touch turns the chip's positions the same way as the panel.
  const esp_lcd_touch_config_t cfg = {
      .x_max = PANEL_W,
      .y_max = PANEL_H,
      .rst_gpio_num = PIN_TOUCH_RST,
      .int_gpio_num = PIN_TOUCH_INT,
  };
  if (esp_lcd_touch_new_i2c_cst9217(tio, &cfg, &touch) != ESP_OK) {
    ESP_LOGE(TAG, "CST9220 touch not answering");
    touch = NULL;
  }
}

void board_begin(void) {
  i2c_begin();
  lcd_begin();
  touch_begin();

  if (!gfx_size(PANEL_W / ZOOM, PANEL_H / ZOOM)) {
    ESP_LOGE(TAG, "a %dx%d picture is outside what the screens are laid out for", PANEL_W / ZOOM, PANEL_H / ZOOM);
    abort();
  }
  gfx_corner(CORNER_RADIUS / ZOOM);  // so every screen keeps clear of the rounded corners
  // Zoomed, the panel is sent rows_out, so the picture itself can be anywhere, PSRAM included.
  gfx_fb = heap_caps_malloc(SCR_W * SCR_H * 2, MALLOC_CAP_DEFAULT);
  if (!gfx_fb) {
    ESP_LOGE(TAG, "no room for the %d KB picture", SCR_W * SCR_H * 2 / 1024);
    abort();
  }
  for (int i = 0; i < BUFS; i++) {
    rows_out[i] = heap_caps_malloc(PANEL_W * ROWS_AT_ONCE * ZOOM * 2, MALLOC_CAP_DMA | MALLOC_CAP_INTERNAL);
    ESP_ERROR_CHECK(rows_out[i] ? ESP_OK : ESP_ERR_NO_MEM);
  }
  bands = (SCR_H + ROWS_AT_ONCE - 1) / ROWS_AT_ONCE;
  band_hash = calloc(bands, sizeof(uint32_t));
  ESP_ERROR_CHECK(band_hash ? ESP_OK : ESP_ERR_NO_MEM);

  gfx_clear(0);
  board_flush();
  ESP_ERROR_CHECK(esp_lcd_panel_disp_on_off(panel, true));
}

// An AMOLED has no backlight: this sets the panel's own brightness, and 0 is dark.
void board_backlight(int percent) {
  if (percent < 0) percent = 0;
  if (percent > 100) percent = 100;
  esp_lcd_panel_co5300_set_brightness(panel, (uint8_t)percent);
}

static uint32_t band_sum(int band, int rows) {
  const uint32_t *p = (const uint32_t *)(gfx_fb + band * ROWS_AT_ONCE * SCR_W);
  uint32_t h = 2166136261u;
  for (int i = 0; i < rows * SCR_W / 2; i++) h = (h ^ p[i]) * 16777619u;
  return h;
}

void board_flush(void) {
  static int next;
  for (int b = 0; b < bands; b++) {
    int y = b * ROWS_AT_ONCE;
    int rows = SCR_H - y < ROWS_AT_ONCE ? SCR_H - y : ROWS_AT_ONCE;
    uint32_t h = band_sum(b, rows);
    if (bands_valid && h == band_hash[b]) continue;
    band_hash[b] = h;
    // Both buffers on their way: wait for the older one, which is the one about to be refilled.
    if (in_flight == BUFS) {
      xSemaphoreTake(lcd_done, portMAX_DELAY);
      in_flight--;
    }
    gfx_zoomed(ZOOM, y, rows, rows_out[next]);
    // Every area starts and ends on an even pixel, which the CO5300 needs: ZOOM is 2.
    esp_lcd_panel_draw_bitmap(panel, 0, y * ZOOM, PANEL_W, (y + rows) * ZOOM, rows_out[next]);
    in_flight++;
    next = (next + 1) % BUFS;
  }
  while (in_flight) {
    xSemaphoreTake(lcd_done, portMAX_DELAY);
    in_flight--;
  }
  bands_valid = true;
}

// The CST9220's position, turned the way the panel is (Waveshare's swap_xy and mirror_y for touch),
// then divided by ZOOM to land in the picture.
bool board_touch(int *x, int *y) {
  if (!touch) return false;
  if (esp_lcd_touch_read_data(touch) != ESP_OK) return false;
  esp_lcd_touch_point_data_t p[1];
  uint8_t n = 0;
  if (esp_lcd_touch_get_data(touch, p, &n, 1) != ESP_OK || n == 0) return false;
  int px = PANEL_H - 1 - p[0].y, py = p[0].x;
  if (px < 0) px = 0;
  if (px >= PANEL_W) px = PANEL_W - 1;
  if (py >= PANEL_H) py = PANEL_H - 1;
  *x = px / ZOOM;
  *y = py / ZOOM;
  return true;
}
