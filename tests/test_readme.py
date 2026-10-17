import os
import unittest

from tests.helpers import ROOT


class ReadmeTest(unittest.TestCase):
    """M2 FR-7: the README covers the upgrade, the first notification permission and the Step 1 conclusion."""

    def setUp(self):
        with open(os.path.join(ROOT, "README.md"), encoding="utf-8") as f:
            self.text = f.read()

    def section(self, heading):
        start = self.text.index("\n## %s\n" % heading)
        end = self.text.find("\n## ", start + 1)
        return self.text[start:end if end >= 0 else None]

    def test_upgrade(self):
        self.assertIn("After `git pull`, run `make -C ~/.local/share/agent-usage-monitor install` again", self.text)

    def test_first_notification_permission(self):
        alerts = self.section("Alerts")
        self.assertIn("click Allow", alerts)
        self.assertIn("System Settings › Notifications › Agent Usage Monitor", alerts)
        self.assertIn("`com.ophis.agent-usage-monitor`", alerts)

    def test_step1_conclusion(self):
        spike = self.section("Spike conclusions")
        self.assertIn("**TASK-638**", spike)
        for fact in ("`osascript`", "Script Editor", "`UNUserNotificationCenter`", "Allow prompt"):
            self.assertIn(fact, spike)


if __name__ == "__main__":
    unittest.main()
