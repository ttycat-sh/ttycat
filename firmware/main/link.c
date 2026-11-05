#include "link.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "board.h"
#include "cJSON.h"
#include "sdkconfig.h"
#if CONFIG_ESP_CONSOLE_USB_SERIAL_JTAG
#include "driver/usb_serial_jtag.h"
#else
#include "driver/uart.h"
#endif
#include "freertos/FreeRTOS.h"
#include "freertos/semphr.h"
#include "freertos/task.h"
#include "gfx.h"
#include "mbedtls/base64.h"
#include "model.h"
#include "pet.h"
#include "ui.h"

#define RX_LINE_MAX 24576

// The chip's own USB port, or a USB-to-serial chip on its first UART: a board's sdkconfig.defaults says which.
#if CONFIG_ESP_CONSOLE_USB_SERIAL_JTAG
static void port_begin(void) {
  usb_serial_jtag_driver_config_t cfg = {.tx_buffer_size = 4096, .rx_buffer_size = 4096};
  ESP_ERROR_CHECK(usb_serial_jtag_driver_install(&cfg));
}
static int port_read(void *buf, size_t n, TickType_t wait) { return usb_serial_jtag_read_bytes(buf, n, wait); }
static int port_write(const char *s, size_t n, TickType_t wait) { return usb_serial_jtag_write_bytes(s, n, wait); }
bool link_usb_connected(void) { return usb_serial_jtag_is_connected(); }
#else
enum { LINK_UART = UART_NUM_0, LINK_BAUD = 230400 };  // the daemon's speed: Board.open in ttycatd.py
static void port_begin(void) {
  uart_config_t cfg = {
      .baud_rate = LINK_BAUD,
      .data_bits = UART_DATA_8_BITS,
      .parity = UART_PARITY_DISABLE,
      .stop_bits = UART_STOP_BITS_1,
      .flow_ctrl = UART_HW_FLOWCTRL_DISABLE,
      .source_clk = UART_SCLK_DEFAULT,
  };
  ESP_ERROR_CHECK(uart_driver_install(LINK_UART, 4096, 4096, 0, NULL, 0));
  ESP_ERROR_CHECK(uart_param_config(LINK_UART, &cfg));
}
static int port_read(void *buf, size_t n, TickType_t wait) { return uart_read_bytes(LINK_UART, buf, n, wait); }
static int port_write(const char *s, size_t n, TickType_t wait) {
  (void)wait;
  return uart_write_bytes(LINK_UART, s, n);
}
bool link_usb_connected(void) { return true; }  // a UART can't tell
#endif

static SemaphoreHandle_t tx_lock;
static char line[RX_LINE_MAX];
static model_t next;

static void write_all(const char *s, size_t n) {
  while (n) {
    int w = port_write(s, n, pdMS_TO_TICKS(200));
    if (w <= 0) return;  // nobody is reading: drop it
    s += w;
    n -= (size_t)w;
  }
}

void link_send_line(const char *json) {
  xSemaphoreTake(tx_lock, portMAX_DELAY);
  write_all(json, strlen(json));
  write_all("\n", 1);
  xSemaphoreGive(tx_lock);
}

static void copy_str(char *dst, size_t cap, const cJSON *o, const char *key) {
  const cJSON *v = cJSON_GetObjectItemCaseSensitive(o, key);
  dst[0] = 0;
  if (cJSON_IsString(v) && v->valuestring) {
    strncpy(dst, v->valuestring, cap - 1);
    dst[cap - 1] = 0;
  }
}

static int get_int(const cJSON *o, const char *key, int def) {
  const cJSON *v = cJSON_GetObjectItemCaseSensitive(o, key);
  return cJSON_IsNumber(v) ? v->valueint : def;
}

static uint8_t parse_state(const char *s) {
  if (!strcmp(s, "blocked")) return ST_BLOCKED;
  if (!strcmp(s, "error")) return ST_ERROR;
  if (!strcmp(s, "done")) return ST_DONE;
  if (!strcmp(s, "working")) return ST_WORKING;
  return ST_IDLE;
}

// Offset in next.text, or -1 if there's no room. 0 is the empty string.
static int pool_add(const cJSON *o, const char *key) {
  const cJSON *v = cJSON_GetObjectItemCaseSensitive(o, key);
  if (!cJSON_IsString(v) || !v->valuestring[0]) return 0;
  size_t len = strlen(v->valuestring);
  if (len >= BODY_MAX || next.text_used + (int)len + 1 >= BODY_POOL) return -1;
  int at = next.text_used + 1;
  memcpy(&next.text[at], v->valuestring, len + 1);
  next.text_used += (int)len + 1;
  return at;
}

// True if the whole ask fits. A choice that's only partly here can't be offered.
static bool parse_questions(session_t *s, const cJSON *o) {
  const cJSON *list = cJSON_GetObjectItemCaseSensitive(o, "qs"), *q;
  s->q_first = (uint8_t)next.q_used;
  s->q_n = 0;
  cJSON_ArrayForEach(q, list) {
    if (s->q_n >= QUESTION_MAX || next.q_used >= MAX_QUESTIONS) return false;
    question_t *t = &next.q[next.q_used++];
    s->q_n++;
    int text = pool_add(q, "q");
    if (text < 0) return false;
    t->text = (uint16_t)text;
    t->multi = cJSON_IsTrue(cJSON_GetObjectItemCaseSensitive(q, "m"));
    const cJSON *opts = cJSON_GetObjectItemCaseSensitive(q, "o"), *opt;
    cJSON_ArrayForEach(opt, opts) {
      if (t->options >= OPTION_MAX) return false;
      int label = pool_add(opt, "l"), desc = pool_add(opt, "d");
      if (label <= 0 || desc < 0) return false;
      t->label[t->options] = (uint16_t)label;
      t->desc[t->options] = (uint16_t)desc;
      t->options++;
    }
    if (!t->options) return false;
  }
  return s->q_n > 0;
}

static void parse_state_msg(const cJSON *j) {
  memset(&next, 0, sizeof(next));
  const cJSON *now = cJSON_GetObjectItemCaseSensitive(j, "now");
  next.now = cJSON_IsNumber(now) ? (int64_t)now->valuedouble : 0;
  next.no_approve = cJSON_IsTrue(cJSON_GetObjectItemCaseSensitive(j, "na"));
  const cJSON *list = cJSON_GetObjectItemCaseSensitive(j, "s"), *o;
  cJSON_ArrayForEach(o, list) {
    if (next.n >= MAX_SESSIONS) break;
    session_t *s = &next.s[next.n++];
    char st[12];
    copy_str(s->id, sizeof(s->id), o, "id");
    copy_str(s->agent, sizeof(s->agent), o, "a");
    copy_str(s->name, sizeof(s->name), o, "n");
    copy_str(s->host, sizeof(s->host), o, "host");
    copy_str(s->project, sizeof(s->project), o, "p");
    copy_str(s->detail, sizeof(s->detail), o, "d");
    copy_str(s->tool, sizeof(s->tool), o, "tool");
    copy_str(s->verb, sizeof(s->verb), o, "verb");
    copy_str(s->file, sizeof(s->file), o, "file");
    copy_str(s->note, sizeof(s->note), o, "note");
    copy_str(s->rev, sizeof(s->rev), o, "rev");
    copy_str(st, sizeof(st), o, "s");
    s->state = parse_state(st);
    s->age = (uint32_t)get_int(o, "age", 0);
    s->add = (int16_t)get_int(o, "add", 0);
    s->del = (int16_t)get_int(o, "del", 0);
    char ask[12];
    copy_str(ask, sizeof(ask), o, "ask");
    s->ask = !strcmp(ask, "approve") ? ASK_APPROVE : !strcmp(ask, "choice") ? ASK_CHOICE
           : !strcmp(ask, "terminal") ? ASK_TERMINAL : ASK_NONE;
    if (next.no_approve && s->ask == ASK_CHOICE) {  // an answer can be permission too
      s->ask = ASK_TERMINAL;
      strlcpy(s->note, "Answer it on the Mac, or allow this board in Setup", sizeof(s->note));
    }
    int body = pool_add(o, "body");
    bool fits = body >= 0;
    s->body = fits ? (uint16_t)body : 0;
    if (s->ask == ASK_CHOICE && fits) fits = parse_questions(s, o);
    if (!fits && (s->ask == ASK_APPROVE || s->ask == ASK_CHOICE)) {  // no room to show it means no way to answer it
      s->ask = ASK_TERMINAL;
      strlcpy(s->note, "Too many asks at once. Answer it in the terminal", sizeof(s->note));
    }
  }
  const cJSON *h = cJSON_GetObjectItemCaseSensitive(j, "hist");
  if (h) {
    copy_str(next.hist_id, sizeof(next.hist_id), h, "id");
    const cJSON *items = cJSON_GetObjectItemCaseSensitive(h, "items"), *it;
    cJSON_ArrayForEach(it, items) {
      if (next.hist_n >= HIST_ITEMS) break;
      hist_item_t *x = &next.hist[next.hist_n++];
      copy_str(x->age, sizeof(x->age), it, "age");
      copy_str(x->text, sizeof(x->text), it, "text");
      x->tone = (uint8_t)get_int(it, "tone", 0);
    }
  }
  const cJSON *pet = cJSON_GetObjectItemCaseSensitive(j, "pet");
  next.pet_total = get_int(pet, "total", 0);
  next.pet_grown = get_int(pet, "grown", next.pet_total);
  next.pet_today = get_int(pet, "today", 0);
  next.pet_age = (int16_t)get_int(pet, "age", 0);
  next.pet_ev = get_int(pet, "ev", 0);
  char evk[10] = "";
  copy_str(evk, sizeof(evk), pet, "evk");
  next.pet_evk = !strcmp(evk, "heart") ? PET_HEART : !strcmp(evk, "rested") ? PET_RESTED : !strcmp(evk, "welcome") ? PET_WELCOME
                 : !strcmp(evk, "birthday") ? PET_BIRTHDAY : -1;
  next.pet_birthday = cJSON_IsTrue(cJSON_GetObjectItemCaseSensitive(pet, "birthday"));
  next.pet_asleep = cJSON_IsTrue(cJSON_GetObjectItemCaseSensitive(pet, "asleep"));
  copy_str(next.pet_name, sizeof(next.pet_name), pet, "name");
  // Left out when both are the default: an older daemon, or nothing chosen.
  const cJSON *look = cJSON_GetObjectItemCaseSensitive(j, "look");
  const cJSON *skin = cJSON_GetArrayItem(look, 0), *accent = cJSON_GetArrayItem(look, 1);
  look_set(cJSON_IsNumber(skin) ? skin->valueint : 0, cJSON_IsNumber(accent) ? accent->valueint : 0);
  ui_set_model(&next);
}

static void handle_line(char *text) {
  if (text[0] != '{') return;  // boot messages and panic output share the port
  cJSON *j = cJSON_Parse(text);
  if (!j) return;
  char t[10];
  copy_str(t, sizeof(t), j, "t");
  ui_event_t ev = {0};
  if (!strcmp(t, "state")) {
    parse_state_msg(j);
  } else if (!strcmp(t, "hello")) {
    ui_link_hello();
  } else if (!strcmp(t, "ack")) {
    ev.type = UI_EV_ACK;
    const cJSON *ok = cJSON_GetObjectItemCaseSensitive(j, "ok");
    ev.ok = cJSON_IsTrue(ok);
    copy_str(ev.text, sizeof(ev.text), j, "msg");
    ui_post(&ev);
  } else if (!strcmp(t, "tap")) {
    ev.type = UI_EV_TAP;
    ev.x = (int16_t)get_int(j, "x", 0);
    ev.y = (int16_t)get_int(j, "y", 0);
    ui_post(&ev);
  } else if (!strcmp(t, "swipe")) {
    char d[2];
    copy_str(d, sizeof(d), j, "dir");
    ev.type = UI_EV_SWIPE;
    ev.dir = d[0];
    ui_post(&ev);
  } else if (!strcmp(t, "goto")) {
    ev.type = UI_EV_GOTO;
    copy_str(ev.text, sizeof(ev.text), j, "screen");
    ui_post(&ev);
  } else if (!strcmp(t, "shot")) {
    ev.type = UI_EV_SHOT;
    ui_post(&ev);
  }
  cJSON_Delete(j);
}

static void rx_task(void *arg) {
  size_t len = 0;
  bool overflow = false;
  static uint8_t buf[512];
  for (;;) {
    int n = port_read(buf, sizeof(buf), pdMS_TO_TICKS(100));
    for (int i = 0; i < n; i++) {
      if (buf[i] == '\n') {
        if (!overflow) {
          line[len] = 0;
          handle_line(line);
        }
        len = 0;
        overflow = false;
      } else if (len < RX_LINE_MAX - 1) {
        line[len++] = (char)buf[i];
      } else {
        overflow = true;
      }
    }
  }
}

void link_begin(void) {
  tx_lock = xSemaphoreCreateMutex();
  port_begin();
  xTaskCreate(rx_task, "link", 8192, NULL, 5, NULL);
}

void link_act(const char *act, const char *id, const char *rev) {
  char buf[128];
  snprintf(buf, sizeof(buf), "{\"t\":\"act\",\"a\":\"%s\",\"id\":\"%s\",\"rev\":\"%s\"}", act, id, rev ? rev : "");
  link_send_line(buf);
}

void link_answer(const char *id, const char *rev, int questions, const uint8_t *picks, const uint8_t *option_count,
                 char typed[][TYPED_MAX + 1]) {
  cJSON *j = cJSON_CreateObject();
  cJSON_AddStringToObject(j, "t", "act");
  cJSON_AddStringToObject(j, "a", "answer");
  cJSON_AddStringToObject(j, "id", id);
  cJSON_AddStringToObject(j, "rev", rev);
  cJSON *ans = cJSON_AddArrayToObject(j, "ans");
  for (int q = 0; q < questions; q++) {
    cJSON *one = cJSON_CreateObject(), *nums = cJSON_AddArrayToObject(one, "o");
    for (int i = 0; i < option_count[q]; i++)
      if (picks[q] & (1 << i)) cJSON_AddItemToArray(nums, cJSON_CreateNumber(i));
    if (picks[q] & (1 << OPTION_MAX)) cJSON_AddStringToObject(one, "t", typed[q]);
    cJSON_AddItemToArray(ans, one);
  }
  char *text = cJSON_PrintUnformatted(j);
  if (text) link_send_line(text);
  cJSON_free(text);
  cJSON_Delete(j);
}

void link_watch(const char *id) {
  char buf[64];
  snprintf(buf, sizeof(buf), "{\"t\":\"watch\",\"id\":\"%s\"}", id);
  link_send_line(buf);
}

void link_send_shot(void) {
  enum { CHUNK = 2400 };
  static unsigned char b64[CHUNK * 4 / 3 + 8];
  static char out[sizeof(b64) + 64];
  const unsigned char *fb = (const unsigned char *)gfx_fb;
  size_t total = SCR_W * SCR_H * 2;
  int seq = 0, count = (int)((total + CHUNK - 1) / CHUNK);
  for (size_t off = 0; off < total; off += CHUNK, seq++) {
    size_t n = total - off < CHUNK ? total - off : CHUNK, w = 0;
    mbedtls_base64_encode(b64, sizeof(b64), &w, fb + off, n);
    b64[w] = 0;
    snprintf(out, sizeof(out), "{\"t\":\"shot\",\"i\":%d,\"n\":%d,\"d\":\"%s\"}", seq, count, b64);
    link_send_line(out);
  }
}
