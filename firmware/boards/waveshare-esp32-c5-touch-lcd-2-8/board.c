#include "board.h"

#include <string.h>

#include "driver/gpio.h"
#include "driver/spi_master.h"
#include "esp_attr.h"
#include "esp_heap_caps.h"
#include "esp_lcd_panel_io.h"
#include "esp_lcd_panel_ops.h"
#include "esp_lcd_panel_st7789.h"
#include "esp_log.h"
#include "freertos/FreeRTOS.h"
#include "freertos/semphr.h"
#include "freertos/task.h"
#include "gfx.h"
#include "waveshare.h"

static const char *TAG = "board";

enum {
  PIN_SDA = 0,
  PIN_SCL = 1,
  PIN_TOUCH_INT = 5,
  PIN_SCK = 6,
  PIN_MOSI = 7,
  PIN_MISO = 8,
  PIN_DC = 9,
  PIN_LCD_CS = 10,
  PIN_SD_CS = 23,
};
enum { REG_DIR = 0x02, REG_OUT = 0x03, REG_PWM = 0x05 };

// The panel: an ST7789, 240x320 portrait, the picture's size exactly, so no zoom.
#define PANEL_W 240
#define PANEL_H 320
#define BAND_ROWS 8
#define BANDS (PANEL_H / BAND_ROWS)

static i2c_master_bus_handle_t bus;
static i2c_master_dev_handle_t expander, touch;
static SemaphoreHandle_t exio_lock;
static uint8_t exio_out;
static esp_lcd_panel_io_handle_t lcd_io;
static esp_lcd_panel_handle_t panel;
static SemaphoreHandle_t lcd_done;
static uint32_t band_hash[BANDS];
static bool bands_valid;
static volatile bool touch_pending = true;
static bool touching;

static bool exio_write(uint8_t reg, uint8_t v) {
  uint8_t d[2] = {reg, v};
  return i2c_master_transmit(expander, d, 2, 50) == ESP_OK;
}

bool board_exio_set(int line, bool high) {
  xSemaphoreTake(exio_lock, portMAX_DELAY);
  uint8_t v = high ? exio_out | (1 << line) : exio_out & ~(1 << line);
  bool ok = exio_write(REG_OUT, v);
  if (ok) exio_out = v;
  xSemaphoreGive(exio_lock);
  return ok;
}

void board_backlight(int percent) {
  xSemaphoreTake(exio_lock, portMAX_DELAY);
  exio_write(REG_PWM, (uint8_t)(percent * 255 / 100));
  xSemaphoreGive(exio_lock);
}

i2c_master_bus_handle_t board_i2c(void) { return bus; }

static void IRAM_ATTR touch_isr(void *arg) { touch_pending = true; }

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
  i2c_device_config_t dc = {.dev_addr_length = I2C_ADDR_BIT_LEN_7, .scl_speed_hz = 400000};
  dc.device_address = 0x24;
  ESP_ERROR_CHECK(i2c_master_bus_add_device(bus, &dc, &expander));
  dc.device_address = 0x58;
  ESP_ERROR_CHECK(i2c_master_bus_add_device(bus, &dc, &touch));

  // Everything in reset, the amp off and the light out until the first frame.
  exio_lock = xSemaphoreCreateMutex();
  if (!(exio_write(REG_OUT, 0) &&
        exio_write(REG_DIR, 1 << EXIO_TOUCH_RST | 1 << EXIO_LCD_RST | 1 << EXIO_AMP) &&
        exio_write(REG_PWM, 0)))
    ESP_LOGE(TAG, "CH32V003 expander not answering");
  vTaskDelay(pdMS_TO_TICKS(10));
  board_exio_set(EXIO_TOUCH_RST, true);

  gpio_config_t in = {
      .pin_bit_mask = 1ULL << PIN_TOUCH_INT,
      .mode = GPIO_MODE_INPUT,
      .pull_up_en = GPIO_PULLUP_ENABLE,
      .intr_type = GPIO_INTR_NEGEDGE,
  };
  gpio_config(&in);
  gpio_install_isr_service(0);
  gpio_isr_handler_add(PIN_TOUCH_INT, touch_isr, NULL);
}

// The panel shares its bus with the microSD slot. A card in SD mode reads MOSI as
// commands whatever its select line says, so pixel data could reach it. CMD0 with
// select low moves any inserted card to SPI mode, where it then ignores the bus.
static void sd_card_quiet(void) {
  spi_device_interface_config_t dc = {.clock_speed_hz = 400000, .spics_io_num = -1, .queue_size = 1};
  spi_device_handle_t sd;
  if (spi_bus_add_device(SPI2_HOST, &dc, &sd) != ESP_OK) return;
  uint8_t idle[10];
  memset(idle, 0xFF, sizeof(idle));
  spi_transaction_t t = {.length = 80, .tx_buffer = idle};
  spi_device_polling_transmit(sd, &t);  // 80 clocks with select high
  const uint8_t cmd0[] = {0x40, 0, 0, 0, 0, 0x95, 0xFF, 0xFF};
  spi_transaction_t c = {.length = sizeof(cmd0) * 8, .tx_buffer = cmd0};
  gpio_set_level(PIN_SD_CS, 0);
  spi_device_polling_transmit(sd, &c);
  gpio_set_level(PIN_SD_CS, 1);
  spi_bus_remove_device(sd);
}

static void spi_begin(void) {
  gpio_config_t cs = {.pin_bit_mask = 1ULL << PIN_LCD_CS | 1ULL << PIN_SD_CS, .mode = GPIO_MODE_OUTPUT};
  gpio_config(&cs);
  gpio_set_level(PIN_LCD_CS, 1);
  gpio_set_level(PIN_SD_CS, 1);
  spi_bus_config_t cfg = {
      .mosi_io_num = PIN_MOSI,
      .miso_io_num = PIN_MISO,
      .sclk_io_num = PIN_SCK,
      .quadwp_io_num = -1,
      .quadhd_io_num = -1,
      .max_transfer_sz = PANEL_W * PANEL_H * 2,
  };
  ESP_ERROR_CHECK(spi_bus_initialize(SPI2_HOST, &cfg, SPI_DMA_CH_AUTO));
  sd_card_quiet();
}

static bool IRAM_ATTR lcd_flushed(esp_lcd_panel_io_handle_t io, esp_lcd_panel_io_event_data_t *e, void *arg) {
  BaseType_t woken = pdFALSE;
  xSemaphoreGiveFromISR(lcd_done, &woken);
  return woken == pdTRUE;
}

// Voltages and gamma from Waveshare's Arduino driver. The ST7789's defaults show
// this design's colours paler (found on this board in the touchreader project).
static void panel_tuning(void) {
  static const struct {
    uint8_t c, n, d[14];
  } cmds[] = {
      {0xB2, 5, {0x0C, 0x0C, 0x00, 0x33, 0x33}},
      {0xB7, 1, {0x75}},
      {0xBB, 1, {0x1A}},
      {0xC0, 1, {0x2C}},
      {0xC2, 2, {0x01, 0xFF}},
      {0xC3, 1, {0x13}},
      {0xC4, 1, {0x20}},
      {0xC6, 1, {0x0F}},
      {0xD0, 2, {0xA4, 0xA1}},
      {0xD6, 1, {0xA1}},
      {0xE0, 14, {0xD0, 0x0D, 0x14, 0x0D, 0x0D, 0x09, 0x38, 0x44, 0x4E, 0x3A, 0x17, 0x18, 0x2F, 0x30}},
      {0xE1, 14, {0xD0, 0x09, 0x0F, 0x08, 0x07, 0x14, 0x37, 0x44, 0x4D, 0x38, 0x15, 0x16, 0x2C, 0x2E}},
  };
  for (size_t i = 0; i < sizeof(cmds) / sizeof(cmds[0]); i++)
    esp_lcd_panel_io_tx_param(lcd_io, cmds[i].c, cmds[i].d, cmds[i].n);
}

static void lcd_begin(void) {
  board_exio_set(EXIO_LCD_RST, false);
  vTaskDelay(pdMS_TO_TICKS(20));
  board_exio_set(EXIO_LCD_RST, true);
  vTaskDelay(pdMS_TO_TICKS(120));

  lcd_done = xSemaphoreCreateBinary();
  esp_lcd_panel_io_spi_config_t iocfg = {
      .dc_gpio_num = PIN_DC,
      .cs_gpio_num = PIN_LCD_CS,
      .pclk_hz = 80 * 1000 * 1000,
      .lcd_cmd_bits = 8,
      .lcd_param_bits = 8,
      .spi_mode = 0,
      .trans_queue_depth = 4,
      .on_color_trans_done = lcd_flushed,
  };
  ESP_ERROR_CHECK(esp_lcd_new_panel_io_spi((esp_lcd_spi_bus_handle_t)SPI2_HOST, &iocfg, &lcd_io));
  esp_lcd_panel_dev_config_t pc = {
      .reset_gpio_num = -1,
      .rgb_ele_order = LCD_RGB_ELEMENT_ORDER_RGB,
      .bits_per_pixel = 16,
  };
  ESP_ERROR_CHECK(esp_lcd_new_panel_st7789(lcd_io, &pc, &panel));
  ESP_ERROR_CHECK(esp_lcd_panel_init(panel));
  ESP_ERROR_CHECK(esp_lcd_panel_invert_color(panel, true));
  panel_tuning();

  gfx_size(PANEL_W, PANEL_H);
  gfx_fb = heap_caps_malloc(SCR_W * SCR_H * 2, MALLOC_CAP_DMA | MALLOC_CAP_INTERNAL);
  ESP_ERROR_CHECK(gfx_fb ? ESP_OK : ESP_ERR_NO_MEM);
  gfx_clear(0);
  board_flush();
  ESP_ERROR_CHECK(esp_lcd_panel_disp_on_off(panel, true));
}

void board_begin(void) {
  i2c_begin();
  spi_begin();
  lcd_begin();
}

static uint32_t band_sum(int band) {
  const uint32_t *p = (const uint32_t *)(gfx_fb + band * BAND_ROWS * SCR_W);
  uint32_t h = 2166136261u;
  for (int i = 0; i < BAND_ROWS * SCR_W / 2; i++) h = (h ^ p[i]) * 16777619u;
  return h;
}

static void push_rows(int y0, int y1) {
  esp_lcd_panel_draw_bitmap(panel, 0, y0, SCR_W, y1, gfx_fb + y0 * SCR_W);
  xSemaphoreTake(lcd_done, portMAX_DELAY);
}

void board_flush(void) {
  int start = -1;
  for (int b = 0; b <= BANDS; b++) {
    bool changed = false;
    if (b < BANDS) {
      uint32_t h = band_sum(b);
      changed = !bands_valid || h != band_hash[b];
      band_hash[b] = h;
    }
    if (changed && start < 0) start = b;
    if (!changed && start >= 0) {
      push_rows(start * BAND_ROWS, b * BAND_ROWS);
      start = -1;
    }
  }
  bands_valid = true;
}

// The CST3530: as Waveshare's Arduino driver, with the interrupt saying when to read.
bool board_touch(int *nx, int *ny) {
  if (!touch_pending && !touching) return false;
  touch_pending = false;
  static const uint8_t data_reg[4] = {0xD0, 0x07, 0x00, 0x00}, end_reg[4] = {0xD0, 0x00, 0x02, 0xAB};
  uint8_t d[9];
  if (i2c_master_transmit_receive(touch, data_reg, 4, d, sizeof(d), 20) != ESP_OK) {
    touching = false;
    return false;
  }
  i2c_master_transmit(touch, end_reg, 4, 20);
  touching = (d[3] & 0x0F) && (d[8] & 0xF0);
  if (!touching) return false;
  int x = d[4] | (d[7] & 0x0F) << 8, y = d[5] | (d[7] & 0xF0) << 4;
  *nx = x < SCR_W ? x : SCR_W - 1;
  *ny = y < SCR_H ? y : SCR_H - 1;
  return true;
}
