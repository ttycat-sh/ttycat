#include "sound.h"

#include "board.h"
#include "nvs.h"

static bool muted;

// Storage is ready: app_main starts it first.
void sound_begin(void) {
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
