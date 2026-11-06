// Art from the Mac for Bit's stage, such as a season's: docs/PROTOCOL.md, "Art". It's only looks, it's
// only ever drawn on Bit's stage, and nothing in it can react to an answer. With none, Bit's screen is
// exactly as it was without this.
#pragma once
#include <stdbool.h>
#include <stdint.h>

#include "gfx.h"

// The kinds of drawing this firmware knows. A new kind means a new format, and boards built before it
// just get less. Every board says it in its hello, so the Mac sends only what it can draw.
#define ART_FORMAT 1
#define ART_FORMAT_S "1"

#define ART_COLORS 15      // written 1 to 9 and a to f in a sprite's rows, and . for clear
#define ART_SPRITES 8
#define ART_SPRITE_MAX 32  // dots, each way
#define ART_FRAMES 4
#define ART_DOTS 8192      // every sprite's dots, in every frame, together: 4 KB, kept on boards with little RAM
#define ART_PIECES 4       // on the stage
#define ART_FALLING 24
#define ART_SAY 24
#define ART_LINE_MAX 8192  // the message, as sent

// Where on Bit something is worn: a row of its body. A head replaces what it's earned up there for the
// day, as the birthday hat does, and a neck replaces its scarf.
typedef enum { ART_HEAD, ART_FACE, ART_BODY, ART_NECK, ART_SLOTS } art_slot_t;
// Bit's modes, as bits, for hiding something it wears in some of them.
enum { ART_NAP = 1, ART_WORK = 2, ART_WALK = 4, ART_HOP = 8 };

typedef struct {
  uint8_t w, h, frames;
  uint16_t ms;  // between frames: 0 is still
  uint16_t at;  // its first dot in px
} art_sprite_t;

typedef struct {
  int8_t sprite;  // -1: nothing worn there
  int8_t x, y;    // dots from Bit's left edge, and from the top of its row
  uint8_t hide;   // ART_NAP and the rest
} art_wear_t;

typedef struct {
  uint8_t sprite, on;  // on: left, centre, right or sky
  int8_t x, y;         // dots in from that edge, and up from the ground or down from the sky
} art_piece_t;

typedef struct {
  int8_t sprite;  // -1: nothing falling
  uint8_t n;
  int8_t vy, vx;  // dots a second: a negative vy rises
  uint8_t sway;   // dots each one swings side to side
} art_fall_t;

typedef struct {
  char id[12];
  uint8_t colors;
  color_t pal[ART_COLORS + 1];
  uint8_t sprites;
  art_sprite_t sp[ART_SPRITES];
  uint16_t dots;
  uint8_t px[ART_DOTS / 2];  // two dots to a byte: 0 is clear, 1 to 15 a colour
  art_wear_t wear[ART_SLOTS];
  uint8_t pieces;
  art_piece_t set[ART_PIECES];
  art_fall_t fall;
  char say[ART_SAY + 1];
} art_t;

// Building one, from the link or the preview. Each says false if what it's given is outside the limits,
// and then the whole thing has to be dropped: it's never drawn in part.
bool art_begin(art_t *a, const char *id);
bool art_color(art_t *a, int index, uint32_t rgb);  // index 1 to 15, rgb 0xRRGGBB
// `rows` is `n` rows of `w` characters: h rows for each frame, one frame after another.
bool art_sprite(art_t *a, int w, int h, int ms, const char *const *rows, int n);
// on: head, face, body or neck. hide: ART_NAP and the rest.
bool art_wear(art_t *a, int sprite, const char *on, int x, int y, int hide);
// on: left, centre, right or sky.
bool art_piece(art_t *a, int sprite, const char *on, int x, int y);
bool art_fall(art_t *a, int sprite, int n, int vy, int vx, int sway);
bool art_say(art_t *a, const char *text);
// After all the rest: true if every sprite and colour it refers to is there.
bool art_finish(const art_t *a);

// What Bit's stage shows, from ui.c under its lock. NULL takes it away.
void art_use(const art_t *a);
// What's showing, or "" for nothing.
const char *art_id(void);

// Drawing, from pet.c. The stage is `width` wide, from `top` down to the line Bit stands on at `ground`,
// in dots of `dot` pixels. Behind Bit: what stands on the stage, and what falls past.
void art_draw_stage(int64_t now, int width, int top, int ground, int dot);
bool art_wears(art_slot_t slot);
// At Bit's left edge `x` and the top of the slot's row `y`, unless Bit is in a mode it hides in.
void art_draw_wear(art_slot_t slot, int64_t now, int x, int y, int dot, int modes);
// The line for the banner, or "".
const char *art_said(void);
