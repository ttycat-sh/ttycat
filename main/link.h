// JSON lines to and from the Mac daemon over the board's USB port.
#pragma once
#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#include "model.h"

void link_begin(void);
void link_send_line(const char *json);
void link_act(const char *act, const char *id, const char *rev);
void link_watch(const char *id);
// A name the person typed for this session, or "" to take it back: it goes by its folder again.
void link_name(const char *id, const char *name);
// Each question's picks, as a bitmask of options and any typed text.
void link_answer(const char *id, const char *rev, int questions, const uint8_t *picks, const uint8_t *option_count,
                 char typed[][TYPED_MAX + 1]);
bool link_usb_connected(void);
// Says who this is: its build, its board, its chip's own ID, and the name the person gave it, if any.
void link_hello(void);
// The framebuffer as base64 lines: lets tools check the real rendered frame.
void link_send_shot(void);
