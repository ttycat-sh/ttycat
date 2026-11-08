"""The board's colours are the daemon's tables (look.py), in the same order: the app checks itself against them too."""
import re
import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "daemon"))
import look  # noqa: E402


class SameAsTheDaemon(unittest.TestCase):
    def test_skins_and_accents(self):
        firmware = (ROOT / "main/gfx.c").read_text()
        skins = [(n, int(b, 16), int(s, 16)) for b, s, n in re.findall(r"\{RGB\(0x(\w{6})\), RGB\(0x(\w{6})\)\},\s*// (\w+)", firmware)]
        accents = [(n, int(v, 16)) for v, n in re.findall(r"^\s+RGB\(0x(\w{6})\),\s*// (\w+)", firmware, re.M)]
        self.assertEqual(skins, look.SKIN_COLOURS)
        self.assertEqual(accents, look.ACCENT_COLOURS)


if __name__ == "__main__":
    unittest.main()
