// The screens of the ttycat design, their touch targets and navigation.
#pragma once
#include <stdbool.h>
#include <stdint.h>

#include "art.h"
#include "model.h"

typedef enum { UI_EV_TAP, UI_EV_SWIPE, UI_EV_GOTO, UI_EV_ACK, UI_EV_SHOT } ui_ev_type_t;

typedef struct {
  ui_ev_type_t type;
  int16_t x, y;        // tap
  char dir;            // swipe: L R U D
  bool ok;             // ack
  char text[48];       // goto: screen name; ack: message
} ui_event_t;

void ui_begin(void);
// One pass: input, timers, drawing. Call from a single task.
void ui_tick(void);
// From the link task.
void ui_post(const ui_event_t *ev);
void ui_set_model(const model_t *m);
void ui_set_art(const art_t *a);
void ui_link_hello(void);
