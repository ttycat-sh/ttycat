// What the daemon says is going on. Replaced whole, once a second.
#pragma once
#include <stdbool.h>
#include <stdint.h>

#define MAX_SESSIONS 24
#define HIST_ITEMS 5
#define BODY_MAX 1024   // a longer ask isn't offered on the board
#define BODY_POOL 6144  // few sessions ask at once, so they share this
#define MAX_QUESTIONS 12   // shared by every session that's asking
#define QUESTION_MAX 4     // in one ask
#define OPTION_MAX 4       // in one question
#define TYPED_MAX 200      // a typed answer
#define FW_VERSION "0.10.1"
#define FW_PROTOCOL "1"  // docs/PROTOCOL.md: goes up when a change would break devices already built
#define FW_LABEL "custom"  // your own build's name, shown in the app's Setup

// What this build tells the Mac it runs. A plain version is what makes it ttycat's own, and able to
// approve prompts without being asked about, so only a release says that (tools/release_firmware.sh).
// Anything else says what it is, down to its source (main/CMakeLists.txt), so each change asks again.
#ifdef FW_RELEASE
#define FW_NAME FW_VERSION
#else
#ifndef FW_BUILD_ID
#define FW_BUILD_ID "unbuilt"
#endif
#define FW_NAME FW_LABEL "-" FW_VERSION "-" FW_BUILD_ID
#endif
#ifndef FW_BOARD
#define FW_BOARD "unbuilt"  // which folder in boards/, from main/CMakeLists.txt
#endif

// In the order the queue sorts them.
typedef enum { ST_BLOCKED, ST_ERROR, ST_DONE, ST_WORKING, ST_IDLE } state_t;
// ASK_APPROVE: Allow/Deny work. ASK_CHOICE: pick or type an answer here.
// ASK_TERMINAL: can only be answered at the Mac.
typedef enum { ASK_NONE, ASK_APPROVE, ASK_TERMINAL, ASK_CHOICE } ask_t;

// Text is offsets into model_t.text.
typedef struct {
  uint16_t text, label[OPTION_MAX], desc[OPTION_MAX];
  uint8_t options;
  bool multi;
} question_t;

typedef struct {
  char id[16];       // herdr pane id
  char agent[3];     // tab code: CC, CX, OC, PI
  char name[12];     // Claude
  char host[8];      // the machine, when it isn't this Mac
  char project[28];
  char detail[72];   // one line for rows and the hero
  char tool[8];      // BASH, EDIT, SHELL, ASK
  char verb[20];     // wants to run
  uint16_t body;     // into model_t.text: the command, or a diff's lines separated by \n
  char file[32];     // set for a diff
  char note[72];     // why this can't be answered here
  char rev[16];      // identifies this exact prompt; echoed with an answer
  int16_t add, del;
  uint32_t age;      // seconds in this state when the message was sent
  uint8_t state, ask;
  uint8_t q_first, q_n;  // into model_t.q
} session_t;

typedef struct {
  char age[6];
  char text[121];
  uint8_t tone;  // 0 faint, 1 orange, 2 green
} hist_item_t;

typedef struct {
  session_t s[MAX_SESSIONS];
  int n;
  int64_t now;       // local time, seconds since 1970 as if UTC
  char hist_id[16];
  hist_item_t hist[HIST_ITEMS];
  int hist_n;
  int32_t pet_total, pet_today;  // turns agents have finished
  int32_t pet_grown;             // what its level comes from: time, and tokens
  bool pet_asleep, pet_birthday;
  int16_t pet_age;
  int32_t pet_ev;  // numbers the latest care, from here or the Mac
  int8_t pet_evk;  // what it looks like: a pet_reaction_t, or -1 for nothing
  char pet_name[12];
  bool no_approve;  // the Mac won't take Allow or answers from this build until the person says so
  char art_id[12];  // the art Bit's stage should show, or "": art.h
  char text[BODY_POOL];          // text[0] is always the empty string
  int text_used;
  question_t q[MAX_QUESTIONS];
  int q_used;
} model_t;
