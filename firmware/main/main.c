#include <stdio.h>

#include "board.h"
#include "esp_heap_caps.h"
#include "esp_log.h"
#include "freertos/FreeRTOS.h"
#include "freertos/task.h"
#include "link.h"
#include "sound.h"
#include "ui.h"

void app_main(void) {
  board_begin();
  link_begin();
  ui_begin();
  sound_begin();
  char mem[64];  // the daemon logs this: the framebuffer and link buffers use most of the RAM
  snprintf(mem, sizeof(mem), "boot: %u bytes free", (unsigned)heap_caps_get_free_size(MALLOC_CAP_INTERNAL));
  link_send_line(mem);
  for (;;) {
    ui_tick();
    vTaskDelay(pdMS_TO_TICKS(16));
  }
}
