#include "ui.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

#include "board.h"
#include "esp_timer.h"
#include "fonts.h"
#include "freertos/FreeRTOS.h"
#include "freertos/queue.h"
#include "freertos/semphr.h"
#include "game.h"
#include "gfx.h"
#include "keyboard.h"
#include "link.h"
#include "pet.h"
#include "sound.h"

// Palette (design: Spec, "Pixel system").
#define BLACK RGB(0x000000)
#define TILE RGB(0x0C0C0C)
#define LINE RGB(0x262626)
#define DOT_OFF RGB(0x1C1C1C)
#define CARD RGB(0x161616)
#define SPENT RGB(0x2A2A2A)
#define CODE RGB(0x0B0B0B)
#define MUTED RGB(0x9A9A9A)
#define MUTED2 RGB(0x8C8C8C)
#define FAINT RGB(0x505050)
#define WHITE RGB(0xFFFFFF)
#define ORANGE accent_color
#define GREEN RGB(0x3FD38A)
#define ERR_SEG RGB(0x9C3A10)

static const color_t c_line = LINE;
#define c_orange accent_color

#define BODY_OF(s) (&model.text[(s)->body])

// 5x5 icons.
static icon5_t I_GRID = {0x1B, 0x1B, 0x00, 0x1B, 0x1B};
static icon5_t I_RIGHT = {0x08, 0x04, 0x02, 0x04, 0x08};
static icon5_t I_LEFT = {0x02, 0x04, 0x08, 0x04, 0x02};
static icon5_t I_CROSS = {0x11, 0x0A, 0x04, 0x0A, 0x11};
static icon5_t I_CHECK = {0x01, 0x03, 0x16, 0x1C, 0x08};
static icon5_t I_BANG = {0x04, 0x04, 0x04, 0x00, 0x04};
static icon5_t I_DOTS = {0x00, 0x00, 0x15, 0x00, 0x00};
static icon5_t I_DASH = {0x00, 0x00, 0x0E, 0x00, 0x00};
static icon5_t I_FOOD = {0x04, 0x0E, 0x1F, 0x1F, 0x0E};
static icon5_t I_BUG = {0x11, 0x0E, 0x1F, 0x0E, 0x11};
static icon5_t I_BROOM = {0x01, 0x02, 0x04, 0x0E, 0x1F};
static icon5_t I_MOON = {0x0E, 0x18, 0x18, 0x18, 0x0E};
static icon5_t I_SUN = {0x15, 0x0E, 0x1F, 0x0E, 0x15};

// 10x10 sprites.
static const char *const S_ALERT[10] = {"....oo....", "...oooo...", "...oooo...", "...oooo...", "....oo....",
                                        "....oo....", "..........", "....oo....", "....oo....", ".........."};
static const char *const S_CROSS[10] = {"oo......oo", "ooo....ooo", ".ooo..ooo.", "..oooooo..", "...oooo...",
                                        "...oooo...", "..oooooo..", ".ooo..ooo.", "ooo....ooo", "oo......oo"};
static const char *const S_CHECK[10] = {"..........", ".........g", "........gg", ".......gg.", "g.....gg..",
                                        "gg...gg...", ".gg.gg....", "..ggg.....", "...g......", ".........."};
static const char *const S_SLEEP[10] = {"..........", "......ooo.", ".......o..", "......ooo.", ".www......",
                                        "...w......", "..w.......", ".www......", "..........", "wwwwwwwwww"};

typedef enum { SCR_BOOT, SCR_OVERVIEW, SCR_QUEUE, SCR_ASK, SCR_DIFF, SCR_DETAIL, SCR_LOST, SCR_PET, SCR_GAME, SCR_CHOICE, SCR_KEYS } screen_t;

typedef enum {
  A_NONE,
  A_OVERVIEW,
  A_QUEUE,
  A_TAB,
  A_SESSION,
  A_DONE_SEEN,
  A_CARD,
  A_NEXT,
  A_ALLOW,
  A_ASK_MAC,
  A_DENY,
  A_OPTION,
  A_CHOICE_NEXT,
  A_CHOICE_BACK,
  A_LATER,
  A_OPEN,
  A_MUTE,
  A_ALERT,
  A_PET_OPEN,
  A_PET,
  A_CARE,
  A_GAME_DONE,
} action_t;

typedef struct {
  int16_t x, y, w, h;
  uint8_t action;
  int16_t arg;
} hit_t;

enum {
  LINK_TIMEOUT_MS = 5000,
  ASK_IDLE_MS = 120000,     // untouched this long, an ask goes back to the queue: Allow isn't left live on the desk
  ARM_DELAY_MS = 600,       // a tap this soon after an ask appears is not an answer to it
  ALERT_MS = 8000,
  HOME_AFTER_MS = 30000,    // untouched this long with nothing needing you: the pet's home
  MARQUEE_HOLD_MS = 1500,   // long text rests at its start, so it can be read from the top
  MARQUEE_PX_PER_S = 40,
  MARQUEE_GAP = 32,         // between the end of the text and its start coming round again
  DIM_AFTER_MS = 120000,    // untouched this long on the home screen: dim
  ACK_TIMEOUT_MS = 3000,
  OPEN_TIMEOUT_MS = 9000,   // the daemon gives up on focusing the Mac after 8 s
  OPENED_MS = 2500,         // how long the button confirms it worked
  GAME_DONE_DELAY_MS = 900, // frantic taps at the end don't dismiss the score
  HANDS_OFF_MS = 1500,      // an ask interrupted the pet: see leave_pet_for_ask()
  HANDS_OFF_MORE_MS = 800,
  TOAST_MS = 3000,
  BRIGHT = 80,
  DIM = 8,
};

static const char *const TAB_CODES[5] = {"ALL", "CC", "CX", "OC", "PI"};
static const char *const AGENT_CODES[4] = {"CC", "CX", "OC", "PI"};
static const char *const AGENT_NAMES[4] = {"Claude", "Codex", "OpenCode", "Pi"};

static SemaphoreHandle_t model_lock;
static QueueHandle_t events;
static model_t model;
static volatile bool model_fresh, hello_seen, ever_linked;
static volatile int64_t last_rx_ms;
static int64_t model_rx_ms;

static screen_t screen = SCR_BOOT;
static uint32_t screen_gen;  // a press only counts on the screen it began on
static int tab;
static char cur_id[16], cur_rev[16];
static int64_t ask_armed_at, ask_opened_at;
static bool answering;
static int64_t answering_since;
static char alert_id[16];
static int64_t alert_until;
static bool opening;  // Open on Mac sent, no reply yet: more taps wouldn't help
static int64_t opening_since, opened_until;
static int32_t pet_seen;
static int pet_level_seen;
static int pet_hello = -1;       // a welcome back, saved for when the pet's on screen to give it
static int pet_pending = -1;     // waiting for the daemon to answer some care: one at a time
static int64_t pet_pending_since;
static bool game_over, game_new_best;
static int64_t game_over_at;
static int64_t hands_off_until;
static int32_t pet_ev_seen;
static volatile bool dim_resend;
static char toast[48];
static int64_t toast_until;
static int64_t last_touch_ms;
static int64_t marquee_from;     // when Detail's text last started from the top
static bool dimmed, wake_swallow, first_state = true;
static char blocked_seen[MAX_SESSIONS][16];
static int blocked_seen_n;
static int diff_scroll;
static int queue_top;  // rows scrolled past, on the queue
static bool ask_clipped;  // the code box doesn't show all of this ask

static hit_t hits[24];
static int hit_n;

// The answers so far to the question being asked, kept if you step away and come back.
static char q_rev[16];
static int q_index;
static uint8_t q_picks[QUESTION_MAX];              // bit i: option i; bit OPTION_MAX: the typed answer
static char q_typed[QUESTION_MAX][TYPED_MAX + 1];
static int pressed = -1;
static bool down;
static int down_x, down_y, last_x, last_y;
static int64_t down_ms;
static uint32_t down_gen;

static int64_t now_ms(void) { return esp_timer_get_time() / 1000; }

static void hit(int x, int y, int w, int h, action_t a, int arg) {
  if (hit_n < (int)(sizeof(hits) / sizeof(hits[0]))) hits[hit_n++] = (hit_t){x, y, w, h, a, arg};
}

static void go(screen_t s) {
  screen = s;
  screen_gen++;
  opened_until = 0;  // "look at Mac" belongs to the screen it was tapped on
}

static uint32_t age_of(const session_t *s) { return s->age + (uint32_t)((now_ms() - model_rx_ms) / 1000); }

static void fmt_age(char *out, size_t cap, uint32_t a) {
  if (a < 60) snprintf(out, cap, "%us", (unsigned)a);
  else if (a < 3600) snprintf(out, cap, "%um", (unsigned)(a / 60));
  else if (a < 86400) snprintf(out, cap, "%uh", (unsigned)(a / 3600));
  else snprintf(out, cap, "%ud", (unsigned)(a / 86400));
}

// On every ask and hero card, so it's always clear which machine is asking.
static const char *who(const session_t *s) { return s->host[0] ? s->host : s->name; }

static bool needs_you(const session_t *s) { return s->state == ST_BLOCKED || s->state == ST_ERROR; }

static session_t *find_session(const char *id) {
  for (int i = 0; i < model.n; i++)
    if (!strcmp(model.s[i].id, id)) return &model.s[i];
  return NULL;
}

static void undim(void) {
  if (dimmed) {
    dimmed = false;
    board_backlight(BRIGHT);
  }
}

// Sessions on the current tab, by rank: blocked, error, done, working, idle.
static int tab_list(int t, int *out) {
  int n = 0;
  for (int rank = ST_BLOCKED; rank <= ST_IDLE; rank++)
    for (int i = 0; i < model.n; i++) {
      const session_t *s = &model.s[i];
      if (s->state != rank) continue;
      if (t > 0 && strcmp(s->agent, TAB_CODES[t])) continue;
      out[n++] = i;
    }
  return n;
}

static int count_state(int st) {
  int n = 0;
  for (int i = 0; i < model.n; i++)
    if (model.s[i].state == st) n++;
  return n;
}

static int need_total(void) { return count_state(ST_BLOCKED) + count_state(ST_ERROR); }

static void clock_parts(struct tm *out) {
  time_t t = (time_t)(model.now + (now_ms() - model_rx_ms) / 1000);
  gmtime_r(&t, out);
}

static void open_session(const session_t *s);

static void open_ask(const session_t *s) {
  strlcpy(cur_id, s->id, sizeof(cur_id));
  strlcpy(cur_rev, s->rev, sizeof(cur_rev));
  ask_opened_at = ask_armed_at = now_ms();
  answering = false;
  diff_scroll = 0;
  if (s->ask == ASK_CHOICE && strcmp(q_rev, s->rev)) {
    strlcpy(q_rev, s->rev, sizeof(q_rev));
    q_index = 0;
    memset(q_picks, 0, sizeof(q_picks));
    memset(q_typed, 0, sizeof(q_typed));
  }
  go(s->ask == ASK_CHOICE ? SCR_CHOICE : SCR_ASK);
}

static void back_to_ask(const session_t *s) {
  ask_armed_at = now_ms();
  go(s && s->ask == ASK_CHOICE ? SCR_CHOICE : SCR_ASK);
}

static void open_detail(const session_t *s) {
  strlcpy(cur_id, s->id, sizeof(cur_id));
  link_watch(s->id);
  marquee_from = now_ms();
  go(SCR_DETAIL);
}

static void open_session(const session_t *s) {
  if (s->state == ST_BLOCKED) open_ask(s);
  else open_detail(s);
}

static void open_next_need(void) {
  for (int rank = ST_BLOCKED; rank <= ST_ERROR; rank++)
    for (int i = 0; i < model.n; i++)
      if (model.s[i].state == rank) {
        open_session(&model.s[i]);
        return;
      }
  go(SCR_QUEUE);
}

// ---------------------------------------------------------------- shared parts

static void mac_indicator(int right, color_t dot, color_t text) {
  int w = gfx_width(&vt16, "MAC", 0);
  gfx_text(&vt16, right - w, 2, text, "MAC");
  gfx_fill(right - w - 10, 7, 6, 6, dot);
}

// A column of a 5x5 icon over a label, centred in a button.
static void button(int x, int y, int w, int h, color_t bg, const color_t *border, icon5_t icon, int scale,
                   color_t icon_c, int gap, const font_t *f, color_t text_c, const char *label, int spacing) {
  gfx_box(x, y, w, h, bg, border, BLACK);
  int total = (icon ? 5 * scale + gap : 0) + f->size;
  int top = y + (h - total) / 2;
  if (icon) {
    gfx_icon(icon, x + (w - 5 * scale) / 2, top, scale, icon_c);
    top += 5 * scale + gap;
  }
  int tw = gfx_caps_width(f, label, spacing);
  gfx_caps(f, x + (w - tw) / 2, top, text_c, label, spacing);
}

static void card_label(const session_t *s, color_t c) {
  char label[44];
  snprintf(label, sizeof(label), "%s \xB7 %s", who(s), s->project);
  gfx_clip(16, 36, 208, 12);
  gfx_caps(&sk11, 16, 36, c, label, 0);
  gfx_noclip();
}

// The command or diff inside the ask card's code box.
static bool code_body(const session_t *s, int x, int y, int w, int h, color_t bg, color_t fg, bool dollar) {
  bool clipped = false;
  gfx_box(x, y, w, h, bg, NULL, CARD);
  gfx_clip(x, y, w, h);
  if (s->file[0]) {
    int ty = y + 6;
    char n[12];
    int right = x + w - 8;
    snprintf(n, sizeof(n), "-%d", s->del);
    int wd = gfx_width(&vt18, n, 0);
    gfx_text(&vt18, right - wd, ty - 1, ORANGE, n);
    right -= wd + 6;
    snprintf(n, sizeof(n), "+%d", s->add);
    int wa = gfx_width(&vt18, n, 0);
    gfx_text(&vt18, right - wa, ty - 1, GREEN, n);
    right -= wa + 6;
    gfx_clip(x + 8, y, right - x - 8, h);
    const char *name = s->file;  // a path too wide for the box keeps its end
    while (*name && gfx_width(&vt18, name, 0) > right - x - 8) name++;
    gfx_text(&vt18, x + 8, ty - 1, WHITE, name);
    gfx_clip(x, y, w, h);
    ty += 18;
    const char *p = BODY_OF(s);
    while (*p && ty < y + h) {
      const char *e = strchr(p, '\n');
      size_t len = e ? (size_t)(e - p) : strlen(p);
      char row[64];
      if (len >= sizeof(row)) len = sizeof(row) - 1;
      memcpy(row, p, len);
      row[len] = 0;
      gfx_text(&vt18, x + 8, ty - 1, row[0] == '-' ? ORANGE : row[0] == '+' ? GREEN : MUTED, row);
      ty += 18;
      p = e ? e + 1 : "";
    }
    clipped = *p != 0;
  } else {
    static char text[BODY_MAX + 4];
    snprintf(text, sizeof(text), "%s%s", dollar ? "$ " : "", BODY_OF(s));
    gfx_clip(x, y, w, h - 6);
    int lines = gfx_wrap(&vt18, x + 8, y + 6, w - 16, 18, fg, text, dollar ? 1 : 0, MUTED);
    clipped = lines * 18 > h - 12;
  }
  gfx_noclip();
  if (clipped) {  // never let a clipped command look complete
    gfx_fill(x + w - 26, y + h - 16, 26, 16, bg);
    gfx_right(&vt18, x + w - 4, y + h - 18, ORANGE, "...");
  }
  return clipped;
}

// The Mac can take a moment to come forward, so the button always says where it's up to.
static void open_button(int x, int y, int w, int h, const font_t *f, int scale) {
  bool opened = now_ms() < opened_until;
  if (opening) {
    button(x, y, w, h, CARD, NULL, I_DOTS, scale, FAINT, 8, f, FAINT, "Opening", 1);
    return;
  }
  button(x, y, w, h, opened ? GREEN : ORANGE, NULL, opened ? I_CHECK : I_RIGHT, scale, BLACK, 8, f, BLACK,
         opened ? "Look at Mac" : "Open on Mac", 1);
  if (!opened) hit(x, y, w, h, A_OPEN, 0);  // it worked: another tap would do nothing new
}

// ---------------------------------------------------------------- 01 Boot

static void draw_boot(void) {
  gfx_caps(&sk9, 6, 5, WHITE, "ttycat", 0);
  mac_indicator(234, FAINT, FAINT);

  gfx_box(6, 24, 228, 108, CARD, NULL, BLACK);
  gfx_caps(&sk11, 16, 36, WHITE, "Waiting for", 0);
  gfx_text(&ps32, 14, 58, ORANGE, "MAC");
  int pw = gfx_width(&vt16, "start the daemon", 0) + 12;
  gfx_box(14, 104, pw, 20, ORANGE, NULL, CARD);
  gfx_text(&vt16, 20, 106, BLACK, "start the daemon");
  gfx_box(150, 30, 78, 96, BLACK, NULL, CARD);
  gfx_sprite(S_SLEEP, 154, 44, 6, 1, DOT_OFF, ORANGE, WHITE, GREEN);

  gfx_box(6, 138, 228, 176, TILE, &c_line, BLACK);
  gfx_caps(&sk9, 20, 152, MUTED, "Link", 0);

  gfx_box(20, 173, 14, 14, GREEN, NULL, TILE);
  gfx_icon(I_CHECK, 22, 175, 2, BLACK);
  gfx_text(&vt18, 42, 171, WHITE, "USB power");

  bool serial = link_usb_connected();
  if (serial) {
    gfx_box(20, 201, 14, 14, GREEN, NULL, TILE);
    gfx_icon(I_CHECK, 22, 203, 2, BLACK);
  } else {
    gfx_border(20, 201, 14, 14, ORANGE);
    gfx_fill(25, 206, 4, 4, ORANGE);
    gfx_right(&vt16, 220, 200, ORANGE, "...");
  }
  gfx_text(&vt18, 42, 199, WHITE, "serial open");

  if (hello_seen) {
    gfx_box(20, 229, 14, 14, GREEN, NULL, TILE);
    gfx_icon(I_CHECK, 22, 231, 2, BLACK);
    gfx_text(&vt18, 42, 227, WHITE, "daemon hello");
  } else if (serial) {
    gfx_border(20, 229, 14, 14, ORANGE);
    gfx_fill(25, 234, 4, 4, ORANGE);
    gfx_right(&vt16, 220, 228, ORANGE, "...");
    gfx_text(&vt18, 42, 227, WHITE, "daemon hello");
  } else {
    gfx_border(20, 229, 14, 14, FAINT);
    gfx_text(&vt18, 42, 227, FAINT, "daemon hello");
  }

  gfx_fill(20, 272, 200, 2, LINE);
  gfx_text(&vt16, 20, 284, MUTED, "ttycat daemon");
  gfx_right(&vt16, 220, 284, MUTED, "fw " FW_VERSION);
}

// ---------------------------------------------------------------- the pet

static void draw_pet_stage(void) {
  int working = count_state(ST_WORKING);
  pet_look_t look = {
      // a dim screen sends it to sleep, unless there's work on
      .asleep = (dimmed && !working) || model.pet_asleep,
      .working = working,
      .level = pet_level(model.pet_grown),
      .birthday = model.pet_birthday,
      .scarf = model.pet_age >= 100,
      .poops = model.pet_poops,
      .need = (pet_need_t)model.pet_need,
  };
  pet_draw(now_ms(), &look);
}

static void open_home(void) {
  pet_react(now_ms(), PET_HEART);
  go(SCR_PET);
}

static void meter(int y, const char *label, int value, bool low) {
  gfx_caps(&sk9, 126, y + 1, MUTED, label, 0);
  int filled = (value * 8 + 50) / 100;
  if (value > 0 && filled == 0) filled = 1;
  for (int i = 0; i < 8; i++)
    gfx_fill(164 + i * 9, y + 1, 7, 8, i < filled ? (low ? WHITE : ORANGE) : DOT_OFF);
}

static void care_button(int x, int y, const char *label, icon5_t icon, bool loud, bool enabled, int arg) {
  color_t ink = !enabled ? FAINT : loud ? BLACK : WHITE;
  button(x, y, 111, 52, loud && enabled ? ORANGE : TILE, loud && enabled ? NULL : &c_line, icon, 2, ink, 6, &sk9, ink, label, 1);
  hit(x, y, 111, 52, A_CARE, arg);
}

// Home: the pet, the time, how the agents are doing, and the care buttons.
static void draw_pet_screen(void) {
  gfx_icon(I_LEFT, 6, 8, 1, WHITE);
  int ax = gfx_caps(&sk9, 15, 5, WHITE, "Agents", 0);
  char count[8];
  snprintf(count, sizeof(count), "%d", model.n);
  gfx_text(&vt16, ax + 6, 2, MUTED, count);
  hit(0, 0, 90, 22, A_QUEUE, 0);
  mac_indicator(234, GREEN, MUTED);

  int32_t gained = model.pet_total - pet_seen;
  int level = pet_level(model.pet_grown);
  if (gained > 0 || level > pet_level_seen) {  // a level can come from age alone, with no turn to show
    pet_reward(gained > 0 ? (int)gained : 0, level > pet_level_seen);
    pet_seen = model.pet_total;
    pet_level_seen = level;
  }
  if (pet_hello >= 0) {
    pet_react(now_ms(), (pet_reaction_t)pet_hello);
    pet_hello = -1;
  }
  gfx_dashed(6, 112, 228, 2, LINE);
  draw_pet_stage();
  int px, py, pw, ph;
  pet_bounds(&px, &py, &pw, &ph);
  hit(px, py, pw, ph, A_PET, 0);

  // the desk clock, beside how the pet is doing
  struct tm t;
  clock_parts(&t);
  char hh[3], mm[3], date[20];
  snprintf(hh, sizeof(hh), "%02d", t.tm_hour);
  snprintf(mm, sizeof(mm), "%02d", t.tm_min);
  int x = gfx_text_sp(&ps24, 6, 120, WHITE, hh, -2);
  x = gfx_text_sp(&ps24, x, 120, ORANGE, ":", -2);
  gfx_text_sp(&ps24, x, 120, WHITE, mm, -2);
  static const char *const days[] = {"Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"};
  static const char *const months[] = {"Jan", "Feb", "Mar", "Apr", "May", "Jun",
                                       "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"};
  snprintf(date, sizeof(date), "%s %d %s", days[t.tm_wday], t.tm_mday, months[t.tm_mon]);
  gfx_caps(&sk9, 8, 150, MUTED, date, 1);
  meter(120, "Food", model.pet_food, model.pet_food < 25);
  meter(136, "Fun", model.pet_fun, model.pet_fun < 25);
  meter(152, "Rest", model.pet_energy, model.pet_energy < 20);

  char line[44];
  snprintf(line, sizeof(line), "%s \xB7 LV %d \xB7 %d snack%s", model.pet_name, pet_level(model.pet_grown), model.pet_snacks,
           model.pet_snacks == 1 ? "" : "s");
  gfx_center(&vt16, 0, SCR_W, 168, WHITE, line, 0);
  int working = count_state(ST_WORKING), done = count_state(ST_DONE);
  if (done) snprintf(line, sizeof(line), "%d done \xB7 %d working \xB7 tap to see", done, working);
  else if (working) snprintf(line, sizeof(line), "%d agent%s working", working, working == 1 ? "" : "s");
  else snprintf(line, sizeof(line), "%d turn%s today \xB7 %d day%s old", (int)model.pet_today, model.pet_today == 1 ? "" : "s",
                model.pet_age, model.pet_age == 1 ? "" : "s");
  gfx_center(&vt16, 0, SCR_W, 186, done ? GREEN : MUTED, line, 0);
  hit(0, 166, SCR_W, 38, A_QUEUE, 0);

  bool awake = !model.pet_asleep;
  care_button(6, 206, "Feed", I_FOOD, awake && model.pet_need == PET_NEED_FOOD, awake, 0);
  care_button(123, 206, "Hunt bugs", I_BUG, awake && model.pet_need == PET_NEED_BORED, awake, 1);
  care_button(6, 262, "Clean", I_BROOM, awake && model.pet_need == PET_NEED_MESS, awake && model.pet_poops, 2);
  care_button(123, 262, awake ? "Sleep" : "Wake up", awake ? I_MOON : I_SUN, !awake || model.pet_need == PET_NEED_TIRED, true, 3);
}

static void draw_game(void) {
  int64_t now = now_ms();
  if (!game_over && game_draw(now)) {
    char score[8];
    game_over = true;
    game_over_at = now;
    last_touch_ms = now;  // the score gets its full time on screen
    game_new_best = game_score() > model.pet_best;
    snprintf(score, sizeof(score), "%d", game_score());
    link_act("pet-play", "", score);
    pet_pending = 99;
    pet_pending_since = now;
  }
  if (!game_over) return;

  gfx_dashed(6, 112, 228, 2, LINE);
  draw_pet_stage();
  char num[8];
  snprintf(num, sizeof(num), "%d", game_score());
  gfx_center(&ps40, 0, SCR_W, 124, ORANGE, num, 0);
  gfx_center(&vt18, 0, SCR_W, 170, WHITE, game_score() == 1 ? "bug squashed" : "bugs squashed", 0);
  char best[24];
  if (game_new_best) snprintf(best, sizeof(best), "new best!");
  else snprintf(best, sizeof(best), "best %d", model.pet_best);
  gfx_center(&vt18, 0, SCR_W, 194, game_new_best ? GREEN : MUTED, best, 0);
  bool ready = now - game_over_at >= GAME_DONE_DELAY_MS;
  button(6, 250, 228, 60, ready ? ORANGE : TILE, ready ? NULL : &c_line, NULL, 0, 0, 0, &sk11, ready ? BLACK : FAINT, "Done", 2);
  if (ready) hit(6, 250, 228, 60, A_GAME_DONE, 0);
}

static void care(int what) {
  static const char *const acts[4] = {"pet-feed", NULL, "pet-clean", "pet-sleep"};
  int64_t now = now_ms();
  if (pet_pending >= 0 && now - pet_pending_since < ACK_TIMEOUT_MS) return;
  if (what == 1) {  // the hunt is played here; the daemon only hears the score
    if (model.pet_asleep || model.pet_energy < 10) {
      snprintf(toast, sizeof(toast), "%s is %s", model.pet_name, model.pet_asleep ? "asleep" : "too tired");
      toast_until = now + TOAST_MS;
      return;
    }
    game_begin(now, false);
    game_over = false;
    go(SCR_GAME);
    return;
  }
  link_act(acts[what], "", NULL);
  pet_pending = 99;  // just waiting for the reply: the reaction comes with the state, as it does for the Mac's
  pet_pending_since = now;
}

// An ask ended the pet's turn. Whoever was tapping away at bugs or buttons is still
// tapping, and the next screens hold Allow, so nothing counts until the taps stop.
static void leave_pet_for_ask(void) {
  hands_off_until = now_ms() + HANDS_OFF_MS;
  game_over = false;
  go(SCR_QUEUE);
}

// ---------------------------------------------------------------- A1 Overview

static void draw_overview(void) {
  int x = gfx_caps(&sk9, 6, 5, WHITE, "Overview", 0);
  char line[24];
  snprintf(line, sizeof(line), "%d session%s", model.n, model.n == 1 ? "" : "s");
  gfx_text(&vt16, x + 8, 2, MUTED, line);
  gfx_icon(I_CROSS, 221, 5, 2, WHITE);
  hit(196, 0, 44, 22, A_QUEUE, 0);

  for (int i = 0; i < 4; i++) {
    int cx = 6 + (i % 2) * 116, cy = 22 + (i / 2) * 122;
    int st[5] = {0};
    for (int k = 0; k < model.n; k++)
      if (!strcmp(model.s[k].agent, AGENT_CODES[i])) st[model.s[k].state]++;
    int count = st[0] + st[1] + st[2] + st[3] + st[4], need = st[ST_BLOCKED] + st[ST_ERROR];
    gfx_box(cx, cy, 112, 118, need ? CARD : TILE, need ? &c_orange : &c_line, BLACK);
    int tx = gfx_caps(&sk11, cx + 10, cy + 11, WHITE, AGENT_CODES[i], 0);
    gfx_text(&vt14, tx + 6, cy + 10, MUTED2, AGENT_NAMES[i]);
    char num[8];
    snprintf(num, sizeof(num), "%d", count);
    gfx_text(&ps24, cx + 10, cy + 30, count ? WHITE : FAINT, num);
    // eight segments: blocked, error, done, working, idle
    static const uint8_t order[5] = {ST_BLOCKED, ST_ERROR, ST_DONE, ST_WORKING, ST_IDLE};
    color_t tone[5] = {ORANGE, ERR_SEG, GREEN, WHITE, FAINT};
    int seg = 0;
    for (int k = 0; k < 5; k++)
      for (int j = 0; j < st[order[k]] && seg < 8; j++, seg++)
        gfx_fill(cx + 10 + seg * 92 / 8, cy + 60, 92 / 8 - (seg == 7 ? 0 : 1), 6, tone[k]);
    for (; seg < 8; seg++) gfx_fill(cx + 10 + seg * 92 / 8, cy + 60, 92 / 8 - (seg == 7 ? 0 : 1), 6, DOT_OFF);

    char l1[32] = "", l2[32] = "";
    if (st[ST_BLOCKED]) snprintf(l1, sizeof(l1), "%d needs you", st[ST_BLOCKED]);
    if (st[ST_ERROR]) {
      size_t len = strlen(l1);
      snprintf(l1 + len, sizeof(l1) - len, "%s%d error", len ? " \xB7 " : "", st[ST_ERROR]);
    }
    bool loud = l1[0] != 0;
    const char *const words[3] = {"done", "working", "idle"};
    const int vals[3] = {st[ST_DONE], st[ST_WORKING], st[ST_IDLE]};
    int hidden = 0;
    for (int k = 0; k < 3; k++) {
      if (!vals[k]) continue;
      if (!l1[0]) {
        snprintf(l1, sizeof(l1), "%d %s", vals[k], words[k]);
        continue;
      }
      char more[32];
      snprintf(more, sizeof(more), "%s%s%d %s", l2, l2[0] ? " \xB7 " : "", vals[k], words[k]);
      if (gfx_width(&vt14, more, 0) <= 92) strlcpy(l2, more, sizeof(l2));
      else hidden += vals[k];
    }
    if (hidden) {
      size_t len = strlen(l2);
      snprintf(l2 + len, sizeof(l2) - len, " +%d", hidden);
    }
    if (!l1[0]) strlcpy(l1, "no sessions", sizeof(l1));
    gfx_clip(cx + 10, cy + 70, 92, 46);
    gfx_text(&vt14, cx + 10, cy + (l2[0] ? 78 : 91), loud ? ORANGE : WHITE, l1);
    gfx_text(&vt14, cx + 10, cy + 98, MUTED2, l2);
    gfx_noclip();
    if (need) {
      gfx_fill(cx + 112 - 22, cy + 8, 14, 14, ORANGE);
      char b[4];
      snprintf(b, sizeof(b), "%d", need > 9 ? 9 : need);
      gfx_center(&vt14, cx + 112 - 22, 14, cy + 8, BLACK, b, 0);
    }
    hit(cx, cy, 112, 118, A_CARD, i + 1);
  }

  int asks = count_state(ST_BLOCKED), errs = count_state(ST_ERROR);
  if (asks + errs) {
    gfx_box(6, 268, 228, 46, ORANGE, NULL, BLACK);
    char a[24], b[40] = "";
    snprintf(a, sizeof(a), "Needs you \xB7 %d", asks + errs);
    gfx_caps(&sk9, 16, 277, BLACK, a, 0);
    if (asks) snprintf(b, sizeof(b), "%d approval%s", asks, asks == 1 ? "" : "s");
    if (errs) {
      size_t len = strlen(b);
      snprintf(b + len, sizeof(b) - len, "%s%d error%s", len ? " \xB7 " : "", errs, errs == 1 ? "" : "s");
    }
    gfx_text(&vt14, 16, 290, BLACK, b);
    int nw = gfx_caps_width(&sk9, "Next", 0);
    gfx_caps(&sk9, 204 - nw, 287, BLACK, "Next", 0);
    gfx_icon(I_RIGHT, 214, 286, 2, BLACK);
    hit(6, 268, 228, 46, A_NEXT, 0);
  } else {
    gfx_box(6, 268, 228, 46, TILE, &c_line, BLACK);
    gfx_caps(&sk9, 18, 277, MUTED, "All clear", 0);
    gfx_text(&vt14, 18, 290, MUTED, "nothing needs you");
    // the way to the pet when agents are busy and the clock can't appear
    int nw = gfx_caps_width(&sk9, model.pet_name, 0);
    gfx_caps(&sk9, 204 - nw, 277, WHITE, model.pet_name, 0);
    gfx_icon(I_RIGHT, 214, 283, 2, WHITE);
    static const char *const asks[] = {"", "is hungry", "made a mess", "is tired", "is bored"};
    gfx_right(&vt14, 204, 290, model.pet_need ? ORANGE : FAINT, model.pet_asleep ? "asleep" : model.pet_need ? asks[model.pet_need] : "is fine");
    hit(6, 268, 228, 46, A_PET_OPEN, 0);
  }
}

// ---------------------------------------------------------------- A2 Queue

// The hero stands in for the first session only if that one needs something. On CLEAR it's a
// summary, and every session gets a row of its own.
static int queue_hero_takes(const int *list, int n) {
  return n && model.s[list[0]].state <= ST_DONE ? 1 : 0;
}

static void draw_queue(void) {
  gfx_icon(I_GRID, 7, 5, 2, WHITE);
  hit(0, 0, 44, 22, A_OVERVIEW, 0);
  struct tm t;
  clock_parts(&t);
  char hm[8];
  snprintf(hm, sizeof(hm), "%02d:%02d", t.tm_hour, t.tm_min);
  gfx_text(&vt16, 30, 2, WHITE, hm);
  int mac_w = gfx_width(&vt16, "MAC", 0);
  mac_indicator(234, GREEN, MUTED);
  int need = need_total();
  if (need) {
    char b[6];
    snprintf(b, sizeof(b), "!%d", need);
    int bw = gfx_width(&vt16, b, 0) + 8;
    int bx = 234 - mac_w - 10 - 6 - bw;
    gfx_box(bx, 3, bw, 14, ORANGE, NULL, BLACK);
    gfx_text(&vt16, bx + 4, 2, BLACK, b);
  }

  // tabs
  int list[MAX_SESSIONS];
  for (int i = 0; i < 5; i++) {
    int n = tab_list(i, list), nneed = 0;
    bool has_done = false;
    for (int k = 0; k < n; k++) {
      if (needs_you(&model.s[list[k]])) nneed++;
      if (model.s[list[k]].state == ST_DONE) has_done = true;
    }
    int x0 = 6 + i * (228 + 3) / 5, x1 = 6 + (i + 1) * (228 + 3) / 5 - 3, w = x1 - x0;
    bool on = i == tab;
    gfx_fill(x0, 22, w, 30, on ? CARD : TILE);
    if (on) gfx_fill(x0, 50, w, 2, ORANGE);
    gfx_corners(x0, 22, w, 30, BLACK);
    gfx_center(&sk9, x0, w, 24, on ? WHITE : MUTED2, TAB_CODES[i], 0);
    char c[6];
    snprintf(c, sizeof(c), "%d", n);
    gfx_center(&vt14, x0, w, 36, on ? WHITE : FAINT, c, 0);
    if (nneed) {
      char b[4];
      snprintf(b, sizeof(b), "%d", nneed > 9 ? 9 : nneed);
      gfx_fill(x0 + w - 12, 24, 10, 10, ORANGE);
      gfx_center(&vt12, x0 + w - 12, 10, 23, BLACK, b, 0);
    } else if (has_done) {
      gfx_fill(x0 + w - 8, 25, 5, 5, GREEN);
    }
    hit(x0, 20, w, 34, A_TAB, i);
  }

  // hero
  int n = tab_list(tab, list);
  const session_t *top = n ? &model.s[list[0]] : NULL;
  const char *label, *word, *suffix = "";
  char lab[44], det[80], suf[20] = "";
  color_t wc, border;
  const char *const *sprite;
  action_t act = A_SESSION;
  int w = 0;
  for (int k = 0; k < n; k++)
    if (model.s[list[k]].state == ST_WORKING) w++;
  if (top && top->state <= ST_DONE) {
    snprintf(lab, sizeof(lab), "%s \xB7 %s", who(top), top->project);
    label = lab;
  } else {
    label = "Nothing needs you";
  }
  if (top && top->state == ST_BLOCKED) {
    word = top->tool[0] ? top->tool : "ASK";
    suffix = "needs you";
    bool sh = !strcmp(top->tool, "BASH") || !strcmp(top->tool, "SHELL");
    snprintf(det, sizeof(det), "%s%s", sh ? "$ " : "", top->detail);
    wc = border = ORANGE;
    sprite = S_ALERT;
  } else if (top && top->state == ST_ERROR) {
    word = "ERROR";
    fmt_age(suf, sizeof(suf), age_of(top));
    strlcat(suf, " ago", sizeof(suf));
    suffix = suf;
    strlcpy(det, top->detail, sizeof(det));
    wc = border = ORANGE;
    sprite = S_CROSS;
  } else if (top && top->state == ST_DONE) {
    word = "DONE";
    suffix = "tap: seen";
    strlcpy(det, top->detail, sizeof(det));
    wc = border = GREEN;
    sprite = S_CHECK;
    act = A_DONE_SEEN;
  } else {
    word = "CLEAR";
    snprintf(det, sizeof(det), "%d working \xB7 %d idle", w, n - w);
    wc = WHITE;
    border = LINE;
    sprite = S_SLEEP;
  }
  gfx_box(6, 56, 228, 56, CARD, &border, BLACK);
  gfx_fill(14, 63, 42, 42, BLACK);
  if (top && top->state > ST_DONE && w) pet_worker(now_ms(), 19, 70, 2, 0);
  else gfx_sprite(sprite, 15, 64, 3, 1, DOT_OFF, ORANGE, WHITE, GREEN);
  gfx_clip(64, 58, 156, 52);
  gfx_caps(&sk9, 64, 60, MUTED2, label, 0);
  int rx = gfx_text(&ps16, 64, 73, wc, word);
  gfx_text(&vt14, rx + 6, 73 + ps16.base - vt14.base, MUTED, suffix);
  gfx_text(&vt14, 64, 93, MUTED, det);
  gfx_noclip();
  int taken = queue_hero_takes(list, n);
  if (taken) {
    gfx_icon(I_RIGHT, 221, 81, 1, WHITE);
    hit(6, 56, 228, 56, act, (int)(top - model.s));
  }

  // rows
  int below = n - taken;  // the rows under the hero
  if (queue_top >= below) queue_top = below > 5 ? (below - 1) / 5 * 5 : 0;
  int rows = below - queue_top > 5 ? 5 : below - queue_top;
  for (int i = 0; i < rows; i++) {
    const session_t *s = &model.s[list[i + taken + queue_top]];
    int y = 116 + i * 37;
    gfx_box(6, y, 228, 34, TILE, s->state == ST_BLOCKED ? &c_orange : &c_line, BLACK);
    color_t ibg, ibd, ifg;
    const uint8_t *icon;
    switch (s->state) {
      case ST_BLOCKED: ibg = ibd = ORANGE; ifg = BLACK; icon = I_BANG; break;
      case ST_ERROR: ibg = BLACK; ibd = ORANGE; ifg = ORANGE; icon = I_CROSS; break;
      case ST_DONE: ibg = ibd = GREEN; ifg = BLACK; icon = I_CHECK; break;
      case ST_WORKING: ibg = ibd = TILE; ifg = TILE; icon = I_DASH; break;  // the mascot, below
      default: ibg = TILE; ibd = LINE; ifg = FAINT; icon = I_DASH; break;
    }
    gfx_box(14, y + 9, 16, 16, ibg, &ibd, TILE);
    gfx_icon(icon, 17, y + 12, 2, ifg);
    if (s->state == ST_WORKING) pet_worker(now_ms(), 14, y + 10, 1, i);
    char age[8];
    fmt_age(age, sizeof(age), age_of(s));
    int aw = gfx_width(&vt14, age, 0);
    int col_r = tab == 0 ? 199 : 226;
    gfx_right(&vt14, col_r, y + 2 + px13.base - vt14.base, MUTED, age);
    gfx_clip(37, y + 2, col_r - aw - 5 - 37, 15);
    gfx_text(&px13, 37, y + 2, WHITE, s->project);
    gfx_clip(37, y + 16, col_r - 37, 16);
    int dx = s->host[0] ? gfx_text(&vt14, 37, y + 18, WHITE, s->host) + 5 : 37;
    gfx_text(&vt14, dx, y + 18, MUTED, s->detail);
    gfx_noclip();
    if (tab == 0) gfx_right(&sk9, 226, y + 12, MUTED2, s->agent);
    hit(6, y, 228, 34, A_SESSION, list[i + taken + queue_top]);
  }

  char foot[24];
  if (below > 5) snprintf(foot, sizeof(foot), "%d-%d of %d", queue_top + taken + 1, queue_top + taken + rows, n);
  else snprintf(foot, sizeof(foot), "%d session%s", n, n == 1 ? "" : "s");
  gfx_text(&vt14, 6, 302, MUTED, foot);
  gfx_right(&vt14, 234, 302, MUTED,
            queue_top + rows < below ? "swipe up for more" : queue_top ? "swipe down: back" : "swipe < > agents");

  // A4: attention from an agent on another tab
  const session_t *al = alert_id[0] && now_ms() < alert_until ? find_session(alert_id) : NULL;
  if (al && al->state == ST_BLOCKED) {
    gfx_border(0, 0, SCR_W, SCR_H, ORANGE);
    gfx_box(6, 22, 228, 30, ORANGE, NULL, BLACK);
    gfx_icon(I_BANG, 14, 32, 2, BLACK);
    char txt[44];
    snprintf(txt, sizeof(txt), "%s \xB7 %s needs you", al->agent, al->project);
    int vw = gfx_caps_width(&sk9, "View >", 0);
    gfx_clip(32, 22, 226 - vw - 8 - 32, 30);
    gfx_caps(&sk9, 32, 32, BLACK, txt, 0);
    gfx_noclip();
    gfx_caps(&sk9, 226 - vw, 32, BLACK, "View >", 0);
    hit(6, 20, 228, 34, A_ALERT, 0);
    // the banner covers the tabs: it wins the hit test
    hit_t top_hit = hits[hit_n - 1];
    memmove(&hits[1], &hits[0], sizeof(hit_t) * (hit_n - 1));
    hits[0] = top_hit;
  }
}

// ---------------------------------------------------------------- 04/05/08 Asks

static void draw_ask(const session_t *s) {
  bool approve = s->ask == ASK_APPROVE;
  if (approve) {
    int asks = count_state(ST_BLOCKED), pos = 1;
    for (int r = 0, k = 0; r < model.n; r++)
      if (model.s[r].state == ST_BLOCKED) {
        k++;
        if (&model.s[r] == s) pos = k;
      }
    int x = gfx_caps(&sk9, 6, 5, WHITE, "Approval", 0) + 8;
    int shown = asks > 6 ? 6 : asks;
    for (int i = 0; i < shown; i++) gfx_fill(x + i * 11, 8, 8, 3, i == (pos - 1) % 6 ? ORANGE : FAINT);
    char of[16];
    snprintf(of, sizeof(of), "%d of %d", pos, asks);
    gfx_text(&vt16, x + shown * 11 + 5, 2, MUTED, of);
  } else {
    gfx_caps(&sk9, 6, 5, WHITE, "Needs you", 0);
    char w[20], a[8];
    fmt_age(a, sizeof(a), age_of(s));
    snprintf(w, sizeof(w), "waiting %s", a);
    gfx_right(&vt16, 234, 2, MUTED, w);
  }

  gfx_box(6, 24, 228, 196, CARD, NULL, BLACK);
  card_label(s, WHITE);
  gfx_text(&vt16, 16, 52, MUTED2, s->verb);
  gfx_text(&ps32, 14, 70, ORANGE, s->tool[0] ? s->tool : "ASK");
  bool sh = !strcmp(s->tool, "BASH") || !strcmp(s->tool, "SHELL");

  if (approve) {
    ask_clipped = code_body(s, 14, 112, 212, 100, CODE, GREEN, sh);
    bool busy = answering;
    button(6, 226, 111, 64, TILE, &c_line, I_CROSS, 3, busy ? FAINT : ORANGE, 10, &sk11, busy ? FAINT : WHITE, "Deny", 2);
    if (model.no_approve) {  // Deny still works here. To say yes, it has to be on the Mac
      button(123, 226, 111, 64, TILE, &c_line, NULL, 0, 0, 0, &sk11, busy ? FAINT : WHITE, "On Mac", 2);
    } else {
      button(123, 226, 111, 64, busy ? CARD : ORANGE, NULL, I_CHECK, 3, busy ? FAINT : BLACK, 10, &sk11, busy ? FAINT : BLACK,
             busy ? "Sending" : "Allow", busy ? 0 : 2);
    }
    if (!busy) {
      hit(6, 226, 111, 64, A_DENY, 0);
      hit(123, 226, 111, 64, model.no_approve ? A_ASK_MAC : A_ALLOW, 0);
    }
    gfx_center(&vt16, 0, SCR_W, 298, ask_clipped ? ORANGE : FAINT,
               s->file[0] ? "swipe up for full diff"
                          : ask_clipped ? "swipe up for all of it"
                          : model.no_approve ? "approve this one on your Mac" : "also waiting in the terminal", 0);
  } else {
    ask_clipped = code_body(s, 14, 112, 212, 62, CODE, sh ? GREEN : MUTED, sh);
    gfx_dashed(14, 182, 212, 2, SPENT);
    gfx_icon(I_BANG, 14, 193, 2, ORANGE);
    gfx_clip(32, 184, 194, 34);
    gfx_wrap(&vt16, 32, 185, 194, 16, MUTED2, s->note[0] ? s->note : "Answer this one in the terminal", 0, 0);
    gfx_noclip();
    button(6, 226, 72, 64, TILE, &c_line, NULL, 0, 0, 0, &sk9, MUTED, "Later", 1);
    open_button(84, 226, 150, 64, &sk11, 3);
    hit(6, 226, 72, 64, A_LATER, 0);
    if (s->host[0]) {
      char via[32];
      snprintf(via, sizeof(via), "opens it over ssh \xB7 %s", s->host);
      gfx_center(&vt16, 0, SCR_W, 298, FAINT, via, 0);
    } else {
      gfx_center(&vt16, 0, SCR_W, 298, FAINT, "runs herdr focus \xB7 ghostty", 0);
    }
  }
}

// Everything the code box couldn't show, reached by swiping up on an ask. Not a
// separate design board: the same code box, using the whole screen.
static void draw_full(const session_t *s) {
  gfx_icon(I_LEFT, 6, 8, 1, WHITE);
  gfx_caps(&sk9, 15, 5, WHITE, "Back", 0);
  hit(0, 0, 60, 22, A_LATER, 1);
  gfx_box(6, 24, 228, 290, CODE, NULL, BLACK);
  gfx_clip(6, 26, 228, 286);
  int y = 30 - diff_scroll * 18;
  if (s->file[0]) {
    y += 18 * gfx_wrap(&vt18, 14, y, 212, 18, WHITE, s->file, 0, 0);
    const char *p = BODY_OF(s);
    static char row[BODY_MAX];
    while (*p) {
      const char *e = strchr(p, '\n');
      size_t len = e ? (size_t)(e - p) : strlen(p);
      if (len >= sizeof(row)) len = sizeof(row) - 1;
      memcpy(row, p, len);
      row[len] = 0;
      color_t c = row[0] == '-' ? ORANGE : row[0] == '+' ? GREEN : MUTED;
      y += 18 * gfx_wrap(&vt18, 14, y, 212, 18, c, row, 0, 0);
      p = e ? e + 1 : "";
    }
  } else {
    bool sh = !strcmp(s->tool, "BASH") || !strcmp(s->tool, "SHELL");
    static char text[BODY_MAX + 4];
    snprintf(text, sizeof(text), "%s%s", sh ? "$ " : "", BODY_OF(s));
    gfx_wrap(&vt18, 14, y, 212, 18, sh ? GREEN : MUTED, text, sh ? 1 : 0, MUTED);
  }
  gfx_noclip();
}

// ---------------------------------------------------------------- choices

static const question_t *current_question(const session_t *s) { return &model.q[s->q_first + q_index]; }

static void draw_choice(const session_t *s) {
  const question_t *q = current_question(s);
  gfx_icon(I_LEFT, 6, 8, 1, WHITE);
  gfx_caps(&sk9, 15, 5, WHITE, q_index ? "Back" : "Later", 0);
  hit(0, 0, 60, 22, q_index ? A_CHOICE_BACK : A_LATER, 0);
  if (s->q_n > 1) {
    char of[20];
    snprintf(of, sizeof(of), "question %d of %d", q_index + 1, s->q_n);
    gfx_right(&vt16, 234, 2, MUTED, of);
  } else {
    char w[20], a[8];
    fmt_age(a, sizeof(a), age_of(s));
    snprintf(w, sizeof(w), "waiting %s", a);
    gfx_right(&vt16, 234, 2, MUTED, w);
  }

  gfx_box(6, 24, 228, 74, CARD, NULL, BLACK);
  card_label(s, WHITE);
  gfx_clip(16, 48, 208, 48);
  int lines = gfx_wrap(&vt16, 16, 49, 208, 16, WHITE, &model.text[q->text], 0, 0);
  gfx_noclip();
  if (lines > 3) {  // never let a clipped question look complete
    gfx_fill(202, 80, 26, 16, CARD);
    gfx_right(&vt18, 226, 78, ORANGE, "...");
  }

  int rows = q->options + 1;
  int step = 172 / rows > 44 ? 44 : 172 / rows;
  for (int i = 0; i < rows; i++) {
    int y = 102 + i * step, h = step - 3;
    bool typed_row = i == q->options;
    bool on = q_picks[q_index] & (1 << (typed_row ? OPTION_MAX : i));
    gfx_box(6, y, 228, h, on ? CARD : TILE, on ? &c_orange : &c_line, BLACK);
    int by = y + (h - 12) / 2;
    if (on) gfx_fill(14, by, 12, 12, ORANGE);
    else gfx_border(14, by, 12, 12, q->multi ? MUTED : FAINT);
    if (on) gfx_icon(I_CHECK, 15, by + 1, 2, BLACK);
    const char *label = typed_row ? (q_typed[q_index][0] ? q_typed[q_index] : "Type an answer...")
                                  : &model.text[q->label[i]];
    const char *desc = typed_row ? "" : &model.text[q->desc[i]];
    color_t lc = typed_row && !q_typed[q_index][0] ? MUTED : WHITE;
    gfx_clip(32, y + 1, 198, h - 2);
    if (desc[0] && h >= 30) {
      gfx_text(&vt16, 32, y + (h - 30) / 2, lc, label);
      gfx_text(&vt14, 32, y + (h - 30) / 2 + 15, MUTED, desc);
    } else {
      gfx_text(&vt16, 32, y + (h - 15) / 2, lc, label);
    }
    gfx_noclip();
    hit(6, y, 228, h, A_OPTION, i);
  }

  open_button(6, 276, 111, 40, &sk9, 1);
  bool last = q_index + 1 >= s->q_n, ready = q_picks[q_index] != 0;
  bool enabled = ready && !answering;
  button(123, 276, 111, 40, enabled ? ORANGE : TILE, enabled ? NULL : &c_line, last ? I_CHECK : I_RIGHT, 1, enabled ? BLACK : FAINT, 8,
         &sk9, enabled ? BLACK : FAINT, answering ? "Sending" : last ? "Send" : "Next", 1);
  if (enabled) hit(123, 276, 111, 40, A_CHOICE_NEXT, 0);
}

static void pick_option(const session_t *s, int i) {
  const question_t *q = current_question(s);
  if (i == q->options) {  // the typed answer: to the keyboard
    keyboard_open(q_typed[q_index], TYPED_MAX + 1, &model.text[q->text]);
    go(SCR_KEYS);
    return;
  }
  if (q->multi) q_picks[q_index] ^= (uint8_t)(1 << i);
  else q_picks[q_index] = (uint8_t)(1 << i);
}

static void keyboard_finished(bool saved) {
  session_t *s = find_session(cur_id);
  if (saved && s) {
    const question_t *q = current_question(s);
    uint8_t typed_bit = 1 << OPTION_MAX;
    if (!q_typed[q_index][0]) q_picks[q_index] &= (uint8_t)~typed_bit;
    else if (q->multi) q_picks[q_index] |= typed_bit;
    else q_picks[q_index] = typed_bit;
  }
  back_to_ask(s);
}

// ---------------------------------------------------------------- 09 Detail

// One line in w px. Text that doesn't fit rests, then scrolls round and comes back.
static void marquee(const font_t *f, int x, int y, int w, color_t c, const char *text) {
  int tw = gfx_width(f, text, 0), off = 0;
  if (tw > w) {
    int travel = tw + MARQUEE_GAP;
    int64_t round = MARQUEE_HOLD_MS + (int64_t)travel * 1000 / MARQUEE_PX_PER_S;
    int64_t t = (now_ms() - marquee_from) % round;
    if (t > MARQUEE_HOLD_MS) off = (int)((t - MARQUEE_HOLD_MS) * MARQUEE_PX_PER_S / 1000);
  }
  gfx_clip(x, y - 2, w, 20);
  gfx_text(f, x - off, y, c, text);
  if (off) gfx_text(f, x - off + tw + MARQUEE_GAP, y, c, text);
  gfx_noclip();
}

static void draw_detail(const session_t *s) {
  int list[MAX_SESSIONS], n = tab_list(0, list), pos = 1;
  for (int i = 0; i < n; i++)
    if (&model.s[list[i]] == s) pos = i + 1;
  gfx_icon(I_LEFT, 6, 8, 1, WHITE);
  gfx_caps(&sk9, 15, 5, WHITE, "Queue", 0);
  hit(0, 0, 60, 22, A_QUEUE, 0);
  char of[12];
  snprintf(of, sizeof(of), "%d / %d", pos, n);
  gfx_right(&vt16, 234, 2, MUTED, of);

  gfx_box(6, 24, 228, 72, CARD, NULL, BLACK);
  int tw = gfx_caps_width(&sk9, s->agent, 0);
  gfx_fill(16, 36, tw + 8, 13, CODE);
  gfx_caps(&sk9, 20, 38, WHITE, s->agent, 0);
  uint32_t a = age_of(s);
  char dur[16];
  if (a < 60) snprintf(dur, sizeof(dur), "%us", (unsigned)a);
  else if (a < 3600) snprintf(dur, sizeof(dur), "%um %us", (unsigned)(a / 60), (unsigned)(a % 60));
  else snprintf(dur, sizeof(dur), "%uh %um", (unsigned)(a / 3600), (unsigned)(a % 3600 / 60));
  int dw = gfx_width(&vt16, dur, 0);
  gfx_right(&vt16, 224, 34, MUTED2, dur);
  gfx_clip(16 + tw + 14, 30, 224 - dw - 4 - 16 - tw - 14, 20);
  gfx_text(&px16, 16 + tw + 14, 34, WHITE, s->project);
  gfx_noclip();
  static const char *const words[] = {"BLOCKED", "ERROR", "DONE", "WORKING", "IDLE"};
  color_t wc = s->state == ST_DONE ? GREEN : s->state == ST_IDLE ? WHITE : ORANGE;
  int word_end = gfx_text(&ps16, 16, 58, wc, words[s->state]);
  if (s->host[0]) gfx_text(&vt16, word_end + 8, 60, MUTED2, s->host);
  if (s->state == ST_WORKING) pet_worker(now_ms(), 192, 58, 2, 0);

  gfx_box(6, 102, 228, 146, TILE, &c_line, BLACK);
  gfx_caps(&sk9, 18, 112, MUTED, "Recent", 0);
  int shown = !strcmp(model.hist_id, s->id) ? model.hist_n : 0;
  // A new event moves every row down: start them all from the top rather than mid-word.
  static char newest[sizeof(model.hist[0].text)];
  const char *top = shown ? model.hist[0].text : s->detail;
  if (strcmp(newest, top)) {
    strlcpy(newest, top, sizeof(newest));
    marquee_from = now_ms();
  }
  for (int i = 0; i < shown; i++) {
    const hist_item_t *h = &model.hist[i];
    int y = 128 + i * 23;
    gfx_text(&vt16, 18, y, FAINT, h->age);
    color_t tone = h->tone == 1 ? ORANGE : h->tone == 2 ? GREEN : FAINT;
    gfx_fill(52, y + 4, 6, 6, tone);
    marquee(&vt16, 66, y, 160, i == 0 ? WHITE : MUTED, h->text);
  }
  if (!shown) marquee(&vt16, 18, 128, 208, FAINT, s->detail);

  button(6, 254, 111, 60, TILE, &c_line, I_DASH, 2, MUTED, 8, &sk9, WHITE, sound_muted() ? "Unmute" : "Mute chime", 1);
  open_button(123, 254, 111, 60, &sk9, 2);
  hit(6, 254, 111, 60, A_MUTE, 0);
}

// ---------------------------------------------------------------- 10 Link lost

static void draw_lost(const session_t *s) {
  gfx_caps(&sk9, 6, 5, WHITE, "Approval", 0);
  int w = gfx_width(&vt16, "MAC", 0);
  gfx_text(&vt16, 234 - w, 2, ORANGE, "MAC");
  gfx_icon(I_CROSS, 234 - w - 9, 8, 1, ORANGE);

  gfx_box(6, 24, 228, 196, SPENT, NULL, BLACK);
  card_label(s, MUTED2);
  char verb[24];
  strlcpy(verb, s->verb, sizeof(verb));
  if (!strncmp(verb, "wants", 5)) {  // wants to run -> wanted to run
    memmove(verb + 6, verb + 5, strlen(verb + 5) + 1);
    memcpy(verb, "wanted", 6);
  }
  gfx_text(&vt16, 16, 52, MUTED2, verb);
  gfx_text(&ps32, 14, 70, MUTED, s->tool[0] ? s->tool : "ASK");
  gfx_box(14, 112, 212, 84, LINE, NULL, SPENT);
  static char text[BODY_MAX + 4];
  bool sh = !strcmp(s->tool, "BASH") || !strcmp(s->tool, "SHELL");
  snprintf(text, sizeof(text), "%s%s", sh ? "$ " : "", BODY_OF(s));
  gfx_clip(14, 112, 212, 78);
  gfx_wrap(&vt18, 22, 118, 196, 18, MUTED, text, 0, 0);
  gfx_noclip();

  gfx_box(0, 112, SCR_W, 40, ORANGE, NULL, BLACK);
  gfx_center(&ps12, 0, SCR_W, 124, BLACK, "LINK LOST", 0);

  for (int i = 0; i < 2; i++) {
    int x = 6 + i * 117;
    gfx_fill(x, 226, 111, 64, CODE);
    gfx_dashed(x, 226, 111, 64, LINE);
    gfx_corners(x, 226, 111, 64, BLACK);
    int tw = gfx_caps_width(&sk11, i ? "Allow" : "Deny", 2);
    gfx_caps(&sk11, x + (111 - tw) / 2, 252, FAINT, i ? "Allow" : "Deny", 2);
  }
  gfx_center(&vt16, 0, SCR_W, 298, MUTED, "answer it in the terminal", 0);
}

// ---------------------------------------------------------------- input

static void change_tab(int delta) {
  tab = (tab + delta + 5) % 5;
  queue_top = 0;
  alert_id[0] = 0;
  screen_gen++;
}

static void answer(const char *act) {
  session_t *s = find_session(cur_id);
  if (!s || answering) return;
  // the daemon checks this rev against the prompt on screen right before answering
  link_act(act, s->id, s->rev);
  answering = true;
  answering_since = now_ms();
}

static void do_action(const hit_t *h) {
  int64_t now = now_ms();
  session_t *s = NULL;
  switch (h->action) {
    case A_OVERVIEW: go(SCR_OVERVIEW); break;
    case A_QUEUE: go(SCR_QUEUE); break;
    case A_TAB:
      tab = h->arg;
      queue_top = 0;
      screen_gen++;
      break;
    case A_SESSION:
      if (h->arg >= 0 && h->arg < model.n) open_session(&model.s[h->arg]);
      break;
    case A_DONE_SEEN:
      if (h->arg >= 0 && h->arg < model.n) link_act("seen", model.s[h->arg].id, NULL);
      break;
    case A_CARD:
      tab = h->arg;
      queue_top = 0;
      go(SCR_QUEUE);
      break;
    case A_NEXT: open_next_need(); break;
    case A_ALLOW:
      if (now - ask_armed_at >= ARM_DELAY_MS) answer("allow");
      break;
    case A_ASK_MAC:
      if (now - ask_armed_at >= ARM_DELAY_MS && (s = find_session(cur_id))) {
        link_act("ask-mac", s->id, s->rev);
        strlcpy(toast, "Look on your Mac", sizeof(toast));
        toast_until = now + TOAST_MS;
      }
      break;
    case A_DENY:
      if (now - ask_armed_at >= ARM_DELAY_MS) answer("deny");
      break;
    case A_OPTION:
      if (now - ask_armed_at >= ARM_DELAY_MS && (s = find_session(cur_id))) pick_option(s, h->arg);
      break;
    case A_CHOICE_BACK:
      if (q_index) q_index--;
      ask_armed_at = now;
      screen_gen++;
      break;
    case A_CHOICE_NEXT:
      if (now - ask_armed_at < ARM_DELAY_MS || answering || !(s = find_session(cur_id))) break;
      if (q_index + 1 < s->q_n) {
        q_index++;
        ask_armed_at = now;
        screen_gen++;
      } else {
        uint8_t counts[QUESTION_MAX];
        for (int i = 0; i < s->q_n; i++) counts[i] = model.q[s->q_first + i].options;
        link_answer(s->id, s->rev, s->q_n, q_picks, counts, q_typed);
        answering = true;
        answering_since = now;
      }
      break;
    case A_LATER:
      if (h->arg == 1) {  // from the full diff, back to the ask
        back_to_ask(find_session(cur_id));
      } else {
        go(SCR_QUEUE);
      }
      break;
    case A_OPEN:
      s = find_session(cur_id);
      if (s && !opening) {
        link_act("open", s->id, NULL);
        opening = true;
        opening_since = now;
        opened_until = 0;
      }
      break;
    case A_MUTE: sound_set_muted(!sound_muted()); break;
    case A_ALERT:
      s = find_session(alert_id);
      alert_id[0] = 0;
      if (s) open_session(s);
      break;
    case A_PET_OPEN: open_home(); break;
    case A_PET:
      link_act("pet-pat", "", NULL);
      break;
    case A_CARE: care(h->arg); break;
    case A_GAME_DONE:
      game_over = false;
      go(SCR_PET);
      break;
    default: break;
  }
}

static bool hands_off(int64_t now) {
  if (now >= hands_off_until) return false;
  hands_off_until = now + HANDS_OFF_MORE_MS;  // still tapping: wait for it to stop
  return true;
}

static int hit_at(int x, int y) {
  for (int i = 0; i < hit_n; i++) {
    const hit_t *h = &hits[i];
    if (x >= h->x && y >= h->y && x < h->x + h->w && y < h->y + h->h) return i;
  }
  return -1;
}

static void on_tap(int x, int y) {
  int i = hit_at(x, y);
  if (i >= 0) do_action(&hits[i]);
}

static void on_swipe(char dir) {
  if (screen == SCR_QUEUE && (dir == 'L' || dir == 'R')) {
    change_tab(dir == 'L' ? 1 : -1);
  } else if (screen == SCR_QUEUE && (dir == 'U' || dir == 'D')) {
    int list[MAX_SESSIONS];
    int count = tab_list(tab, list);
    int below = count - queue_hero_takes(list, count);
    if (dir == 'U' && queue_top + 5 < below) queue_top += 5;
    if (dir == 'D') queue_top = queue_top > 5 ? queue_top - 5 : 0;
    screen_gen++;
  } else if (screen == SCR_DETAIL && dir == 'R') {
    go(SCR_QUEUE);
  } else if (screen == SCR_CHOICE && dir == 'U' && !answering) {
    diff_scroll = 0;  // the whole ask, with every option's description
    go(SCR_DIFF);
  } else if (screen == SCR_ASK && dir == 'U' && !answering) {
    const session_t *s = find_session(cur_id);
    if (s && (s->file[0] || ask_clipped)) {
      diff_scroll = 0;
      go(SCR_DIFF);
    }
  } else if (screen == SCR_DIFF) {
    if (dir == 'U') diff_scroll += 8;
    if (dir == 'D') {
      if (diff_scroll == 0) {
        back_to_ask(find_session(cur_id));
      } else {
        diff_scroll = diff_scroll > 8 ? diff_scroll - 8 : 0;
      }
    }
  } else if ((screen == SCR_OVERVIEW || screen == SCR_PET) && dir == 'R') {
    go(SCR_QUEUE);
  } else if (screen == SCR_PET && dir == 'L') {
    go(SCR_QUEUE);
  }
}

static void keyboard_finished_if(keyboard_result_t r) {
  if (r != KEYBOARD_TYPING) keyboard_finished(r == KEYBOARD_DONE);
}

static void touch_poll(void) {
  int x, y;
  bool now_down = board_touch(&x, &y);
  int64_t now = now_ms();
  if (now_down) {
    last_touch_ms = now;
    last_x = x;
    last_y = y;
  }
  if (now_down && !down) {
    down = true;
    down_x = x;
    down_y = y;
    down_ms = now;
    down_gen = screen_gen;
    char msg[40];
    snprintf(msg, sizeof(msg), "{\"t\":\"touch\",\"x\":%d,\"y\":%d}", x, y);
    link_send_line(msg);
    // a touch on the dim screen only wakes it
    wake_swallow = dimmed || hands_off(now);
    undim();
    pressed = wake_swallow ? -1 : hit_at(x, y);
    if (screen == SCR_GAME && !wake_swallow && !game_over) game_touch(x, y, now);  // on the press: it's a game
  } else if (!now_down && down) {
    down = false;
    pressed = -1;
    if (wake_swallow || down_gen != screen_gen) return;
    if (screen == SCR_KEYS) {  // on release, where the finger ended up, like a phone
      keyboard_finished_if(keyboard_release(last_x, last_y, now));
      return;
    }
    int dx = last_x - down_x, dy = last_y - down_y;
    int ax = abs(dx), ay = abs(dy);
    if (ax > 36 && ax > ay) on_swipe(dx < 0 ? 'L' : 'R');
    else if (ay > 36 && ay > ax) on_swipe(dy < 0 ? 'U' : 'D');
    else if (ax < 14 && ay < 14 && now - down_ms < 1500) on_tap(down_x, down_y);
  }
}

// ---------------------------------------------------------------- model updates

static void notice_new_asks(void) {
  char was[MAX_SESSIONS][16];
  int was_n = blocked_seen_n;
  memcpy(was, blocked_seen, sizeof(was));
  blocked_seen_n = 0;
  for (int i = 0; i < model.n; i++) {
    const session_t *s = &model.s[i];
    if (s->state != ST_BLOCKED) continue;
    strlcpy(blocked_seen[blocked_seen_n++], s->id, 16);
    bool known = false;
    for (int k = 0; k < was_n; k++)
      if (!strcmp(was[k], s->id)) known = true;
    if (known || first_state) continue;
    sound_chime();
    undim();
    if (screen == SCR_PET || screen == SCR_GAME) leave_pet_for_ask();
    if (screen == SCR_QUEUE && tab != 0 && strcmp(s->agent, TAB_CODES[tab])) {
      strlcpy(alert_id, s->id, sizeof(alert_id));
      alert_until = now_ms() + ALERT_MS;
    }
  }
  if (first_state) {
    pet_seen = model.pet_total;  // only what happens from now on is news
    pet_level_seen = pet_level(model.pet_grown);
    pet_ev_seen = model.pet_ev;
  } else if (model.pet_ev != pet_ev_seen) {  // care, given here or on the Mac: both show it
    pet_ev_seen = model.pet_ev;
    bool hello = model.pet_evk == PET_RESTED || model.pet_evk == PET_WELCOME || model.pet_evk == PET_BIRTHDAY;
    if (hello && screen != SCR_PET) pet_hello = model.pet_evk;
    else if (model.pet_evk >= 0) pet_react(now_ms(), (pet_reaction_t)model.pet_evk);
  }
  first_state = false;
}

void ui_set_model(const model_t *m) {
  xSemaphoreTake(model_lock, portMAX_DELAY);
  memcpy(&model, m, sizeof(model));
  model_rx_ms = now_ms();
  model_fresh = true;
  last_rx_ms = model_rx_ms;
  ever_linked = true;
  xSemaphoreGive(model_lock);
}

void ui_link_hello(void) {
  last_rx_ms = now_ms();
  hello_seen = true;
  dim_resend = true;  // a daemon that's just connected doesn't know
}

void ui_post(const ui_event_t *ev) { xQueueSend(events, ev, 0); }

void ui_begin(void) {
  model_lock = xSemaphoreCreateMutex();
  events = xQueueCreate(8, sizeof(ui_event_t));
  last_touch_ms = now_ms();
  gfx_clear(BLACK);
  draw_boot();
  board_flush();
  board_backlight(BRIGHT);
}

static void handle_goto(const char *name) {
  if (!strcmp(name, "pet")) {
    last_touch_ms = now_ms();
    go(SCR_PET);
  } else if (!strcmp(name, "game:bot")) {
    game_begin(now_ms(), true);
    game_over = false;
    go(SCR_GAME);
  } else if (!strcmp(name, "pet:birthday")) {
    pet_react(now_ms(), PET_BIRTHDAY);
  } else if (!strcmp(name, "pet:heart")) {
    pet_react(now_ms(), PET_HEART);
  } else if (!strcmp(name, "pet:reward")) {
    pet_reward(3, false);
  } else if (!strcmp(name, "pet:level")) {
    pet_reward(1, true);
  } else if (!strcmp(name, "pet:sleep")) {
    last_touch_ms = now_ms() - DIM_AFTER_MS - 1;
  } else if (!strcmp(name, "overview")) {
    go(SCR_OVERVIEW);
  } else if (!strcmp(name, "queue")) {
    go(SCR_QUEUE);
  } else if (!strncmp(name, "tab:", 4)) {
    tab = atoi(name + 4) % 5;
    go(SCR_QUEUE);
  } else if (!strncmp(name, "ask:", 4)) {
    session_t *s = find_session(name + 4);
    if (s) open_ask(s);
  } else if (!strncmp(name, "detail:", 7)) {
    session_t *s = find_session(name + 7);
    if (s) open_detail(s);
  }
}

static void step_navigation(void) {
  int64_t now = now_ms();
  bool linked = now - last_rx_ms < LINK_TIMEOUT_MS && last_rx_ms != 0;

  if (!linked && ever_linked) {
    bool asking = screen == SCR_ASK || screen == SCR_DIFF || screen == SCR_CHOICE || screen == SCR_KEYS;
    if (asking && find_session(cur_id)) go(SCR_LOST);
    else if (screen != SCR_BOOT && screen != SCR_LOST) go(SCR_BOOT);
    answering = opening = false;
    hello_seen = false;
    undim();
    return;
  }
  if (!linked) return;
  if (screen == SCR_LOST) go(SCR_QUEUE);
  if (screen == SCR_BOOT && ever_linked) {
    go(SCR_QUEUE);
    last_touch_ms = now;
  }

  if (screen == SCR_ASK || screen == SCR_DIFF || screen == SCR_CHOICE || screen == SCR_KEYS) {
    session_t *s = find_session(cur_id);
    if (!s || s->state != ST_BLOCKED) {
      // answered here or at the terminal: on to the next one, else back
      answering = false;
      if (count_state(ST_BLOCKED) && strcmp(cur_id, "")) open_next_need();
      else go(SCR_QUEUE);
    } else if (strcmp(s->rev, cur_rev)) {
      // a different prompt in the same pane: treat it as newly opened
      open_ask(s);
    } else if (s->ask == ASK_APPROVE && now - (ask_opened_at > last_touch_ms ? ask_opened_at : last_touch_ms) >= ASK_IDLE_MS) {
      go(SCR_QUEUE);  // nobody's here; the prompt is still there, and in the terminal
    }
  }
  if (screen == SCR_DETAIL && !find_session(cur_id)) go(SCR_QUEUE);
  if (pet_pending >= 0 && now - pet_pending_since > ACK_TIMEOUT_MS) {
    pet_pending = -1;
    strlcpy(toast, "no reply from the Mac", sizeof(toast));
    toast_until = now + TOAST_MS;
  }
  if (opening && now - opening_since > OPEN_TIMEOUT_MS) {
    opening = false;
    strlcpy(toast, "no reply from the Mac", sizeof(toast));
    toast_until = now + TOAST_MS;
  }
  if (answering && now - answering_since > ACK_TIMEOUT_MS) {
    answering = false;
    strlcpy(toast, "no reply from the Mac", sizeof(toast));
    toast_until = now + TOAST_MS;
  }

  // Home when untouched, unless something needs you: the pet must never hide that.
  bool need = need_total() > 0;
  bool between = screen == SCR_QUEUE || screen == SCR_OVERVIEW || screen == SCR_DETAIL ||
                 (screen == SCR_GAME && game_over);
  if (between && !need && now - last_touch_ms > HOME_AFTER_MS) {
    game_over = false;
    go(SCR_PET);
  }
  if (screen == SCR_PET) {
    if (need) leave_pet_for_ask();
    else if (!dimmed && now - last_touch_ms > DIM_AFTER_MS) {
      dimmed = true;
      board_backlight(DIM);
    }
  }
}

static void draw_pressed(void) {
  if (pressed < 0 || pressed >= hit_n || !down) return;
  const hit_t *h = &hits[pressed];
  if (h->action == A_PET) return;
  gfx_border(h->x, h->y, h->w, h->h, WHITE);
}

void ui_tick(void) {
  xSemaphoreTake(model_lock, portMAX_DELAY);
  if (model_fresh) {
    model_fresh = false;
    notice_new_asks();
  }

  ui_event_t ev;
  bool shot = false;
  while (xQueueReceive(events, &ev, 0) == pdTRUE) {
    switch (ev.type) {
      case UI_EV_TAP:
        if (hands_off(now_ms())) break;
        last_touch_ms = now_ms();
        if (dimmed) {  // as with a finger, it only wakes the screen
          undim();
          break;
        }
        if (screen == SCR_GAME && !game_over) game_touch(ev.x, ev.y, now_ms());
        else if (screen == SCR_KEYS) keyboard_finished_if(keyboard_release(ev.x, ev.y, now_ms()));
        else on_tap(ev.x, ev.y);
        break;
      case UI_EV_SWIPE:
        last_touch_ms = now_ms();
        on_swipe(ev.dir);
        break;
      case UI_EV_GOTO: handle_goto(ev.text); break;
      case UI_EV_SHOT: shot = true; break;
      case UI_EV_ACK:
        answering = false;
        if (pet_pending >= 0) {
          pet_pending = -1;
        }
        if (opening) {
          opening = false;
          if (ev.ok) opened_until = now_ms() + OPENED_MS;
        }
        if (!ev.ok && ev.text[0]) {
          strlcpy(toast, ev.text, sizeof(toast));
          toast_until = now_ms() + TOAST_MS;
        }
        break;
    }
  }
  touch_poll();
  step_navigation();

  // Hits are rebuilt with each frame, while a held press keeps pointing at its slot.
  hit_n = 0;
  gfx_clear(BLACK);
  session_t *cur = find_session(cur_id);
  switch (screen) {
    case SCR_BOOT: draw_boot(); break;
    case SCR_OVERVIEW: draw_overview(); break;
    case SCR_QUEUE: draw_queue(); break;
    case SCR_ASK:
      if (cur) draw_ask(cur);
      break;
    case SCR_DIFF:
      if (cur) draw_full(cur);
      break;
    case SCR_CHOICE:
      if (cur) draw_choice(cur);
      break;
    case SCR_KEYS:
      keyboard_draw(now_ms(), down && !wake_swallow, last_x, last_y);
      break;
    case SCR_PET: draw_pet_screen(); break;
    case SCR_GAME: draw_game(); break;
    case SCR_DETAIL:
      if (cur) draw_detail(cur);
      break;
    case SCR_LOST:
      if (cur) draw_lost(cur);
      break;
  }
  draw_pressed();
  if (now_ms() < toast_until) {
    int ty = screen == SCR_PET ? 184 : 296;  // the care screen's buttons reach the bottom
    gfx_fill(0, ty, SCR_W, screen == SCR_PET ? 18 : 24, BLACK);
    gfx_center(&vt16, 0, SCR_W, ty + (screen == SCR_PET ? 2 : 4), ORANGE, toast, 0);
  }
  xSemaphoreGive(model_lock);
  board_flush();
  if (shot) link_send_shot();
  static bool dim_said;
  if (dimmed != dim_said || dim_resend) {  // Bit dozes on a dim screen: the Mac shows that too
    dim_said = dimmed;
    dim_resend = false;
    link_send_line(dimmed ? "{\"t\":\"dim\",\"on\":true}" : "{\"t\":\"dim\",\"on\":false}");
  }
  static int64_t last_hello;
  int64_t now = now_ms();
  if (now - last_rx_ms > 2000 && now - last_hello > 1000) {
    last_hello = now;
    link_send_line("{\"t\":\"hello\",\"fw\":\"" FW_NAME "\",\"b\":\"" FW_BOARD "\",\"p\":" FW_PROTOCOL "}");
  }
}
