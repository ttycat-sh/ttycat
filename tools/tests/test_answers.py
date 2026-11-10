"""A tap answers only the prompt that was on the screen: the real firmware UI, run by the preview harness.

Each test drives the board as a finger would and reads back the acts it would have sent the Mac.
Needs only `cc`, as tools/preview does.
"""
import json
import subprocess
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
MAIN, PREVIEW = ROOT / "main", ROOT / "tools/preview"
REPLACED = {"main.c", "board.c", "link.c", "sound.c"}  # harness.c stands in for these
BLOCKED, WORKING = 0, 3
APPROVE, TERMINAL, CHOICE = 1, 2, 3
ALLOW = (180, 258)  # the Allow button on the official 240x320 board
OPTION_1 = (120, 150)  # the first option on a choice
Q = json.dumps


def ask(rev, kind=APPROVE, body="npm install sharp"):
    return (f'm_add("a","CC","Claude","","recipe-box",{Q(body)},"BASH","wants to run",{Q(body)},"","",{Q(rev)},'
            f"0,0,12,{BLOCKED},{kind});")


def state(*calls):
    return ["m_reset(1793000000LL);", *calls, "m_pet(0,0,0,0,0,0,0,-1);", "send_model();"]


def run(steps):
    """The acts the board sends while the steps run."""
    decls = ("void m_reset(long long);void m_add(const char*,const char*,const char*,const char*,const char*,const char*,"
             "const char*,const char*,const char*,const char*,const char*,const char*,int,int,int,int,int);"
             "void m_q(const char*,int);void m_opt(const char*,const char*);void m_pet(int,int,int,int,int,int,int,int);"
             "void send_model(void);void run(int);void go_to(const char*);void touch(int,int);void lift(void);")
    with tempfile.TemporaryDirectory() as d:
        d = Path(d)
        (d / "script.c").write_text(decls + "void script(void){" + "".join(steps) + "}")
        sources = [str(f) for f in sorted(MAIN.glob("*.c")) if f.name not in REPLACED]
        subprocess.run(["cc", "-O1", "-w", "-I", str(PREVIEW / "stubs"), "-I", str(MAIN), *sources, str(PREVIEW / "harness.c"),
                        str(d / "script.c"), "-o", str(d / "fw")], check=True, capture_output=True)
        out = subprocess.run([str(d / "fw"), str(d)], check=True, capture_output=True, text=True).stdout
    return [line.split() for line in out.splitlines() if line.startswith("act ")]


def tap(x, y, then=()):
    """A finger down, held, then lifted: `then` happens while it's down, just before it lifts."""
    return [f"touch({x},{y});", "run(100);", *then, "lift();", "run(100);"]


def opened(*calls):
    return [*state(*calls), "run(1000);", 'go_to("ask:a");', "run(1000);"]


class Answers(unittest.TestCase):
    def test_allow_answers_the_prompt_on_screen(self):
        self.assertEqual(run([*opened(ask("r1")), *tap(*ALLOW)]), [["act", "allow", "a", "r1"]])

    def test_a_tap_too_soon_after_a_prompt_appears_does_nothing(self):
        steps = [*state(ask("r1")), "run(1000);", 'go_to("ask:a");', "run(100);", *tap(*ALLOW)]
        self.assertEqual(run(steps), [])

    def test_a_prompt_replaced_as_the_finger_lifts_is_not_answered(self):
        # The same pane asks again, and the new prompt arrives in the same moment the finger lifts off Allow.
        steps = [*opened(ask("r1")), *tap(*ALLOW, then=state(ask("r2", body="rm -rf ~")))]
        self.assertEqual(run(steps), [])

    def test_the_new_prompt_is_answered_only_once_it_has_been_shown(self):
        steps = [*opened(ask("r1")), *tap(*ALLOW, then=state(ask("r2"))), "run(1000);", *tap(*ALLOW)]
        self.assertEqual(run(steps), [["act", "allow", "a", "r2"]])

    def test_one_act_at_a_time(self):
        # No ack comes back in the harness, so a second Allow waits for one.
        self.assertEqual(run([*opened(ask("r1")), *tap(*ALLOW), "run(1000);", *tap(*ALLOW)]), [["act", "allow", "a", "r1"]])

    def test_a_choice_that_turns_into_one_for_the_terminal_is_not_answered(self):
        choice = [ask("r1", CHOICE, "Where?"), 'm_q("Where should it go?",0);', 'm_opt("Here","");', 'm_opt("There","");']
        steps = [*opened(*choice), *tap(*OPTION_1, then=state(ask("r1", TERMINAL, "Where?"))), "run(1000);"]
        self.assertEqual(run(steps), [])


if __name__ == "__main__":
    unittest.main()
