import glob
import os
import re
import unittest

from tests.helpers import ROOT

# CJK punctuation, ideographs and full-width forms.
CJK = re.compile("[　-〿一-鿿＀-￯]")


class HostStringsTest(unittest.TestCase):
    """TASK-877: the settings window, its menus and its status and error lines are in English."""

    def test_host_swift_has_no_cjk(self):
        paths = sorted(glob.glob(os.path.join(ROOT, "macos", "Host", "*.swift")))
        self.assertTrue(paths)
        for path in paths:
            with open(path, encoding="utf-8") as f:
                for n, line in enumerate(f, 1):
                    with self.subTest(file=os.path.basename(path), line=n):
                        self.assertIsNone(CJK.search(line), line)

    def test_readme_settings_window_has_no_cjk(self):
        with open(os.path.join(ROOT, "README.md"), encoding="utf-8") as f:
            text = f.read()
        start = text.index("\n### Settings window\n")
        section = text[start:text.index("\n### ", start + 1)]
        self.assertIsNone(CJK.search(section))


if __name__ == "__main__":
    unittest.main()
