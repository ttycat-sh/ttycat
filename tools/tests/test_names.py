"""A name for a session, typed on the board: the real firmware UI, run by the preview harness.

It's the keyboard, but it isn't an ask: it sends the Mac a name and nothing else, and gives way to a prompt.
"""
import unittest

from test_answers import ALLOW, WORKING, ask, run, state, tap

RENAME = (171, 10)  # in the Detail screen's header, on the official 240x320 board
CANCEL = (30, 10)
KEY_Q, KEY_A, DONE = (11, 135), (23, 186), (216, 291)


def working(session="a", project="recipe-box"):
    return f'm_add("{session}","CC","Claude","","{project}","Edit: index.html","","","","","","",0,0,70,{WORKING},0);'


def naming(*calls):
    """On the keyboard, for session a's name."""
    return [*state(*(calls or [working()])), "run(1000);", 'go_to("detail:a");', "run(500);", *tap(*RENAME), "run(300);"]


class Names(unittest.TestCase):
    def test_done_sends_the_name_that_was_typed(self):
        self.assertEqual(run([*naming(), *tap(*KEY_Q), *tap(*KEY_A), *tap(*DONE)]), [["act", "name", "a", "[Qa]"]])

    def test_cancel_sends_nothing(self):
        self.assertEqual(run([*naming(), *tap(*KEY_Q), *tap(*CANCEL), "run(500);"]), [])

    def test_done_on_nothing_takes_the_name_back(self):
        self.assertEqual(run([*naming(), *tap(*DONE)]), [["act", "name", "a", "[]"]])

    def test_one_act_at_a_time(self):
        # No ack comes back in the harness, so a second name waits for one: the board says it's busy.
        steps = [*naming(), *tap(*KEY_Q), *tap(*DONE), "run(500);", *tap(*RENAME), "run(300);", *tap(*KEY_A), *tap(*DONE)]
        self.assertEqual(run(steps), [["act", "name", "a", "[Q]"]])

    def test_the_next_name_goes_once_the_mac_has_answered(self):
        steps = [*naming(), *tap(*KEY_Q), *tap(*DONE), "void ack(int,const char*);", 'ack(1,"");', "run(500);",
                 *tap(*RENAME), "run(300);", *tap(*KEY_A), *tap(*DONE)]
        self.assertEqual(run(steps), [["act", "name", "a", "[Q]"], ["act", "name", "a", "[A]"]])

    def test_a_prompt_arriving_takes_the_keyboard_away_and_nothing_is_sent(self):
        # What's waiting comes first. The taps that would have finished the name land on the queue, and answer nothing.
        steps = [*naming(), *tap(*KEY_Q), *state(working(), ask("r1").replace('"a"', '"b"', 1)), "run(1200);",
                 *tap(*DONE), "run(1000);", *tap(*ALLOW)]
        self.assertEqual(run(steps), [])

    def test_a_session_that_ends_takes_the_keyboard_with_it(self):
        steps = [*naming(), *tap(*KEY_Q), *state(working("b", "band-site")), "run(1200);", *tap(*DONE)]
        self.assertEqual(run(steps), [])

    def test_the_name_is_asked_for_only_from_its_own_page(self):
        # Where Rename is on the Detail screen, the queue has nothing that names anything.
        sent = run([*state(working()), "run(1000);", *tap(*RENAME), "run(300);", *tap(*KEY_Q), *tap(*DONE)])
        self.assertEqual([act for act in sent if act[1] == "name"], [])


if __name__ == "__main__":
    unittest.main()
