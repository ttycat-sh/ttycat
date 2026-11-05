#include "sound.h"

#include "board.h"
#include "nvs.h"
#include "nvs_flash.h"

static bool muted;

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
  board_sound_begin();
}

void sound_chime(void) {
  if (!muted) board_chime();
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
