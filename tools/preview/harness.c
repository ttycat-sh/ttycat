// The real firmware UI, on a Mac: everything below ui.c is replaced by these few stand-ins, so a script
// can drive it and save exactly what it would have sent to the panel.
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "board.h"
#include "esp_random.h"
#include "esp_timer.h"
#include "freertos/FreeRTOS.h"
#include "freertos/queue.h"
#include "gfx.h"
#include "link.h"
#include "model.h"
#include "sound.h"
#include "ui.h"

static int64_t clock_ms = 1000000;
static uint32_t seed = 0x2F6E2B1;
static bool finger;
static int finger_x, finger_y;
static bool muted;
static model_t m;
static const char *out_dir;

int64_t esp_timer_get_time(void) { return clock_ms * 1000; }
uint32_t esp_random(void) {
  seed ^= seed << 13;
  seed ^= seed >> 17;
  seed ^= seed << 5;
  return seed;
}

// One queue is all there is.
static ui_event_t q_items[64];
static int q_head, q_tail;
QueueHandle_t xQueueCreate(int n, int size) { (void)n; (void)size; return (QueueHandle_t)1; }
int xQueueSend(QueueHandle_t q, const void *item, int wait) {
  (void)q; (void)wait;
  memcpy(&q_items[q_tail++ % 64], item, sizeof(ui_event_t));
  return 1;
}
int xQueueReceive(QueueHandle_t q, void *item, int wait) {
  (void)q; (void)wait;
  if (q_head == q_tail) return 0;
  memcpy(item, &q_items[q_head++ % 64], sizeof(ui_event_t));
  return 1;
}

void board_begin(void) {}
i2c_master_bus_handle_t board_i2c(void) { return NULL; }
bool board_exio_set(int line, bool high) { (void)line; (void)high; return true; }
void board_backlight(int percent) { (void)percent; }
void board_flush(void) {}
bool board_touch(int *x, int *y) { *x = finger_x; *y = finger_y; return finger; }
void link_begin(void) {}
void link_send_line(const char *json) { (void)json; }
void link_act(const char *act, const char *id, const char *rev) { (void)act; (void)id; (void)rev; }
void link_watch(const char *id) { (void)id; }
void link_answer(const char *id, const char *rev, int questions, const uint8_t *picks, const uint8_t *option_count, char typed[][TYPED_MAX + 1]) {
  (void)id; (void)rev; (void)questions; (void)picks; (void)option_count; (void)typed;
}
bool link_usb_connected(void) { return true; }
void link_send_shot(void) {}
void sound_begin(void) {}
void sound_chime(void) {}
bool sound_muted(void) { return muted; }
void sound_set_muted(bool on) { muted = on; }

// ---------------------------------------------------------------- what the script calls

static uint16_t add_text(const char *s) {
  uint16_t at = (uint16_t)m.text_used;
  strcpy(&m.text[at], s);
  m.text_used += (int)strlen(s) + 1;
  return at;
}

void m_reset(int64_t now) {
  memset(&m, 0, sizeof(m));
  m.now = now;
  m.text_used = 1;
  m.pet_evk = -1;
  strlcpy(m.pet_name, "Bit", sizeof(m.pet_name));
}

void m_add(const char *id, const char *agent, const char *name, const char *host, const char *project, const char *detail, const char *tool,
           const char *verb, const char *body, const char *file, const char *note, const char *rev, int add, int del, int age, int state, int ask) {
  session_t *s = &m.s[m.n++];
  strlcpy(s->id, id, sizeof(s->id));
  strlcpy(s->agent, agent, sizeof(s->agent));
  strlcpy(s->name, name, sizeof(s->name));
  strlcpy(s->host, host, sizeof(s->host));
  strlcpy(s->project, project, sizeof(s->project));
  strlcpy(s->detail, detail, sizeof(s->detail));
  strlcpy(s->tool, tool, sizeof(s->tool));
  strlcpy(s->verb, verb, sizeof(s->verb));
  s->body = body[0] ? add_text(body) : 0;
  strlcpy(s->file, file, sizeof(s->file));
  strlcpy(s->note, note, sizeof(s->note));
  strlcpy(s->rev, rev, sizeof(s->rev));
  s->add = (int16_t)add;
  s->del = (int16_t)del;
  s->age = (uint32_t)age;
  s->state = (uint8_t)state;
  s->ask = (uint8_t)ask;
  s->q_first = (uint8_t)m.q_used;
}

void m_q(const char *text, int multi) {
  question_t *q = &m.q[m.q_used++];
  q->text = add_text(text);
  q->multi = multi;
  m.s[m.n - 1].q_n++;
}

void m_opt(const char *label, const char *desc) {
  question_t *q = &m.q[m.q_used - 1];
  q->label[q->options] = add_text(label);
  q->desc[q->options] = desc[0] ? add_text(desc) : 0;
  q->options++;
}

void m_hist(const char *id, const char *age, int tone, const char *text) {
  strlcpy(m.hist_id, id, sizeof(m.hist_id));
  hist_item_t *h = &m.hist[m.hist_n++];
  strlcpy(h->age, age, sizeof(h->age));
  strlcpy(h->text, text, sizeof(h->text));
  h->tone = (uint8_t)tone;
}

void m_pet(int total, int today, int grown, int food, int fun, int energy, int poops, int need, int asleep, int birthday, int snacks, int age, int best, int ev, int evk) {
  m.pet_total = total;
  m.pet_today = today;
  m.pet_grown = grown;
  m.pet_food = (uint8_t)food;
  m.pet_fun = (uint8_t)fun;
  m.pet_energy = (uint8_t)energy;
  m.pet_poops = (uint8_t)poops;
  m.pet_need = (uint8_t)need;
  m.pet_asleep = asleep;
  m.pet_birthday = birthday;
  m.pet_snacks = (int16_t)snacks;
  m.pet_age = (int16_t)age;
  m.pet_best = (int16_t)best;
  m.pet_ev = ev;
  m.pet_evk = (int8_t)evk;
}

static int64_t since_model;

void send_model(void) {
  ui_set_model(&m);
  since_model = 0;
}

void run(int ms) {
  for (int t = 0; t < ms; t += 50) {
    ui_tick();
    clock_ms += 50;
    since_model += 50;
    if (since_model >= 1000) send_model();
  }
}

void go_to(const char *name) {
  ui_event_t ev = {.type = UI_EV_GOTO};
  strlcpy(ev.text, name, sizeof(ev.text));
  ui_post(&ev);
}

void ack(int ok, const char *text) {
  ui_event_t ev = {.type = UI_EV_ACK, .ok = ok};
  strlcpy(ev.text, text, sizeof(ev.text));
  ui_post(&ev);
}

void touch(int x, int y) {
  finger = true;
  finger_x = x;
  finger_y = y;
}

void lift(void) { finger = false; }

void snap(const char *name) {
  char path[512];
  snprintf(path, sizeof(path), "%s/%s.raw", out_dir, name);
  FILE *f = fopen(path, "wb");
  if (!f) { perror(path); exit(1); }
  fwrite(gfx_fb, 2, SCR_W * SCR_H, f);
  fclose(f);
}

void script(void);

int main(int argc, char **argv) {
  if (argc < 2) return 2;
  out_dir = argv[1];
  gfx_fb = calloc(SCR_W * SCR_H, 2);
  ui_begin();
  script();
  return 0;
}
