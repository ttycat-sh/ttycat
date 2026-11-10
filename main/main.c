#include <stdio.h>

#include "board.h"
#include "esp_heap_caps.h"
#include "freertos/FreeRTOS.h"
#include "freertos/task.h"
#include "link.h"
#include "nvs_flash.h"
#include "sound.h"
#include "ui.h"

// Storage for what outlives a new build: the board's name (link.c) and the chime's mute (sound.c).
static void storage_begin(void) {
  esp_err_t e = nvs_flash_init();
  if (e == ESP_ERR_NVS_NO_FREE_PAGES || e == ESP_ERR_NVS_NEW_VERSION_FOUND) {
    nvs_flash_erase();
    nvs_flash_init();
  }
}

// In this order: storage and the UI are ready before the link's task starts handing them messages.
void app_main(void) {
  storage_begin();
  board_begin();
  ui_begin();
  sound_begin();
  link_begin();
  char mem[64];  // the daemon logs this: the framebuffer and link buffers use most of the RAM
  snprintf(mem, sizeof(mem), "boot: %u bytes free", (unsigned)heap_caps_get_free_size(MALLOC_CAP_INTERNAL));
  link_send_line(mem);
  for (;;) {
    ui_tick();
    vTaskDelay(pdMS_TO_TICKS(16));
  }
}
