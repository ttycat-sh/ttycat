#include "sound.h"

#include <math.h>
#include <string.h>

#include "board.h"
#include "driver/i2s_std.h"
#include "es8311_codec.h"
#include "esp_codec_dev.h"
#include "esp_codec_dev_defaults.h"
#include "esp_log.h"
#include "freertos/FreeRTOS.h"
#include "freertos/semphr.h"
#include "freertos/task.h"
#include "nvs.h"
#include "nvs_flash.h"

static const char *TAG = "sound";
enum { RATE = 16000, PIN_BCLK = 24, PIN_WS = 25, PIN_DOUT = 26, PIN_DIN = 27 };

static esp_codec_dev_handle_t speaker;
static SemaphoreHandle_t wake;
static bool muted;

static int amp_setup(int16_t gpio, audio_gpio_dir_t dir, audio_gpio_mode_t mode) { return 0; }
static int amp_level(int16_t line, bool high) { return board_exio_set(line, high) ? 0 : -1; }
static bool amp_get(int16_t gpio) { return false; }
static const audio_codec_gpio_if_t amp_gpio = {amp_setup, amp_level, amp_get};

static void tone(int hz, int ms) {
  static int16_t buf[2 * 320];
  int total = RATE * ms / 1000, fade = RATE / 200;
  float phase = 0, step = 2 * (float)M_PI * hz / RATE;
  for (int done = 0; done < total;) {
    int n = total - done < 320 ? total - done : 320;
    for (int i = 0; i < n; i++) {
      int k = done + i;
      float env = k < fade ? (float)k / fade : total - k < fade ? (float)(total - k) / fade : 1.0f;
      int16_t v = hz ? (int16_t)(sinf(phase) * env * 22000) : 0;
      phase += step;
      if (phase > 2 * (float)M_PI) phase -= 2 * (float)M_PI;
      buf[2 * i] = buf[2 * i + 1] = v;
    }
    esp_codec_dev_write(speaker, buf, n * 4);
    done += n;
  }
}

static void sound_task(void *arg) {
  for (;;) {
    xSemaphoreTake(wake, portMAX_DELAY);
    esp_codec_dev_sample_info_t fs = {.bits_per_sample = 16, .channel = 2, .sample_rate = RATE};
    if (esp_codec_dev_open(speaker, &fs) != ESP_CODEC_DEV_OK) continue;
    esp_codec_dev_set_out_vol(speaker, 70);
    tone(784, 140);
    tone(0, 40);
    tone(1047, 260);
    tone(0, 60);
    esp_codec_dev_close(speaker);
  }
}

void sound_begin(void) {
  esp_err_t e = nvs_flash_init();
  if (e == ESP_ERR_NVS_NO_FREE_PAGES || e == ESP_ERR_NVS_NEW_VERSION_FOUND) {
    nvs_flash_erase();
    nvs_flash_init();
  }
  nvs_handle_t h;
  if (nvs_open("ttycat", NVS_READONLY, &h) == ESP_OK) {
    uint8_t m = 0;
    nvs_get_u8(h, "muted", &m);
    muted = m;
    nvs_close(h);
  }

  // esp_codec_dev disables both directions on close; only one is ever enabled here
  esp_log_level_set("i2s_common", ESP_LOG_NONE);
  i2s_chan_handle_t tx, rx;
  i2s_chan_config_t cc = I2S_CHANNEL_DEFAULT_CONFIG(I2S_NUM_0, I2S_ROLE_MASTER);
  cc.auto_clear = true;
  if (i2s_new_channel(&cc, &tx, &rx) != ESP_OK) return;
  i2s_std_config_t sc = {
      .clk_cfg = I2S_STD_CLK_DEFAULT_CONFIG(RATE),
      .slot_cfg = I2S_STD_PHILIPS_SLOT_DEFAULT_CONFIG(I2S_DATA_BIT_WIDTH_16BIT, I2S_SLOT_MODE_STEREO),
      .gpio_cfg = {.mclk = GPIO_NUM_NC, .bclk = PIN_BCLK, .ws = PIN_WS, .dout = PIN_DOUT, .din = PIN_DIN},
  };
  sc.clk_cfg.mclk_multiple = I2S_MCLK_MULTIPLE_256;
  i2s_channel_init_std_mode(tx, &sc);
  i2s_channel_init_std_mode(rx, &sc);

  audio_codec_i2s_cfg_t ic = {.port = I2S_NUM_0, .rx_handle = rx, .tx_handle = tx};
  const audio_codec_data_if_t *data = audio_codec_new_i2s_data(&ic);
  audio_codec_i2c_cfg_t i2c = {.port = I2C_NUM_0, .addr = ES8311_CODEC_DEFAULT_ADDR, .bus_handle = board_i2c()};
  es8311_codec_cfg_t ec = {
      .ctrl_if = audio_codec_new_i2c_ctrl(&i2c),
      .gpio_if = &amp_gpio,
      .codec_mode = ESP_CODEC_DEV_WORK_MODE_DAC,
      .pa_pin = EXIO_AMP,
      .use_mclk = false,
      .hw_gain = {.pa_voltage = 5.0f, .codec_dac_voltage = 3.3f},
  };
  const audio_codec_if_t *dac = ec.ctrl_if ? es8311_codec_new(&ec) : NULL;
  if (!data || !dac) {
    ESP_LOGE(TAG, "ES8311 not found");
    return;
  }
  esp_codec_dev_cfg_t oc = {.dev_type = ESP_CODEC_DEV_TYPE_OUT, .codec_if = dac, .data_if = data};
  speaker = esp_codec_dev_new(&oc);
  if (!speaker) return;
  wake = xSemaphoreCreateBinary();
  xTaskCreate(sound_task, "sound", 4096, NULL, 4, NULL);
}

void sound_chime(void) {
  if (speaker && !muted) xSemaphoreGive(wake);
}

bool sound_muted(void) { return muted; }

void sound_set_muted(bool m) {
  muted = m;
  nvs_handle_t h;
  if (nvs_open("ttycat", NVS_READWRITE, &h) == ESP_OK) {
    nvs_set_u8(h, "muted", m);
    nvs_commit(h);
    nvs_close(h);
  }
}
