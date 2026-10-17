import os
import unittest

from agent_usage_monitor import accounts
from tests.helpers import ROOT, Env


class LoadTest(unittest.TestCase):
    def setUp(self):
        self.env = Env()
        self.addCleanup(self.env.cleanup)

    def load(self):
        return accounts.load(self.env.environ)

    def assert_invalid(self, data, *needles):
        self.env.write_accounts(data)
        with self.assertRaises(accounts.AccountsError) as cm:
            self.load()
        msg = str(cm.exception)
        self.assertIn(accounts.config_path(self.env.environ), msg)
        for n in needles:
            self.assertIn(n, msg)

    def test_config_path(self):
        self.assertEqual(accounts.config_path(self.env.environ),
                         os.path.join(self.env.config, "agent-usage-monitor", "accounts.json"))
        environ = dict(self.env.environ, XDG_CONFIG_HOME="")
        self.assertEqual(accounts.config_path(environ),
                         os.path.join(self.env.home, ".config", "agent-usage-monitor", "accounts.json"))

    def test_file_order_and_realpath(self):
        for n in ("c", "a", "b"):
            self.env.mkdir(n)
        os.symlink(os.path.join(self.env.home, "b"), os.path.join(self.env.home, "link-b"))
        self.env.write_accounts({"accounts": [
            {"name": "c", "client": "codex", "dir": "~/c"},
            {"name": "a", "client": "claude", "dir": os.path.join(self.env.home, "a")},
            {"name": "b", "client": "claude", "dir": "~/link-b"},
        ]})
        threshold, accts, hint = self.load()
        self.assertEqual(threshold, 90)
        self.assertIsNone(hint)
        home = os.path.realpath(self.env.home)
        self.assertEqual(accts, [
            accounts.Account("c", "codex", os.path.join(home, "c")),
            accounts.Account("a", "claude", os.path.join(home, "a")),
            accounts.Account("b", "claude", os.path.join(home, "b")),
        ])

    def test_defaults_both(self):
        for n in (".claude", ".codex", ".claude-bak"):
            self.env.mkdir(n)
        threshold, accts, hint = self.load()
        home = os.path.realpath(self.env.home)
        self.assertEqual(threshold, 90)
        self.assertEqual(accts, [
            accounts.Account("claude", "claude", os.path.join(home, ".claude")),
            accounts.Account("codex", "codex", os.path.join(home, ".codex")),
        ])
        self.assertIn(accounts.config_path(self.env.environ), hint)
        self.assertNotIn("\n", hint)

    def test_defaults_partial_and_none(self):
        _, accts, _ = self.load()
        self.assertEqual(accts, [])
        self.env.mkdir(".codex")
        _, accts, _ = self.load()
        self.assertEqual([a.name for a in accts], ["codex"])

    def test_invalid_json(self):
        self.assert_invalid("{not json", "JSON")

    def test_invalid_deeply_nested(self):
        self.assert_invalid("[" * 200000, "JSON")

    def test_invalid_shape(self):
        self.assert_invalid([], "object")
        self.assert_invalid({"accounts": {}}, "accounts")
        self.assert_invalid({}, "accounts")

    def test_invalid_item(self):
        self.env.mkdir("a")
        self.assert_invalid({"accounts": ["x"]}, "accounts[0]")
        self.assert_invalid({"accounts": [{"client": "codex", "dir": "~/a"}]}, "accounts[0]", "name")
        self.assert_invalid({"accounts": [{"name": "a", "dir": "~/a"}]}, "accounts[0]", "(a)", "client")
        self.assert_invalid({"accounts": [{"name": "a", "client": "codex", "dir": 3}]}, "accounts[0]", "dir")

    def test_invalid_duplicate_name(self):
        self.env.mkdir("a")
        self.env.mkdir("b")
        self.assert_invalid({"accounts": [
            {"name": "x", "client": "codex", "dir": "~/a"},
            {"name": "x", "client": "codex", "dir": "~/b"},
        ]}, "accounts[1]", "(x)", "duplicate")

    def test_invalid_client(self):
        self.env.mkdir("a")
        self.assert_invalid({"accounts": [{"name": "a", "client": "gemini", "dir": "~/a"}]},
                            "accounts[0]", "(a)", "client")

    def test_invalid_dir_missing(self):
        self.assert_invalid({"accounts": [{"name": "a", "client": "codex", "dir": "~/nope"}]},
                            "accounts[0]", "(a)", "dir")
        with open(os.path.join(self.env.home, "file"), "w"):
            pass
        self.assert_invalid({"accounts": [{"name": "a", "client": "codex", "dir": "~/file"}]},
                            "accounts[0]", "dir")

    def test_invalid_same_realpath(self):
        self.env.mkdir("a")
        os.symlink(os.path.join(self.env.home, "a"), os.path.join(self.env.home, "alias"))
        self.assert_invalid({"accounts": [
            {"name": "a", "client": "codex", "dir": "~/a"},
            {"name": "b", "client": "claude", "dir": "~/alias"},
        ]}, "accounts[1]", "(b)", "accounts[0]")

    def test_account_display_string(self):
        for n in ("a", "b", "c"):
            self.env.mkdir(n)
        self.env.write_accounts({"accounts": [
            {"name": "a", "client": "claude", "dir": "~/a", "account": "you@example.com"},
            {"name": "b", "client": "codex", "dir": "~/b", "account": "you@example.com"},
            {"name": "c", "client": "claude", "dir": "~/c"},
        ]})
        _, accts, _ = self.load()
        self.assertEqual([a.account for a in accts], ["you@example.com", "you@example.com", None])

    def test_example_file(self):
        for n in (".claude", ".claude-work", ".codex"):
            self.env.mkdir(n)
        with open(os.path.join(ROOT, "accounts.example.json"), encoding="utf-8") as f:
            self.env.write_accounts(f.read())
        home = os.path.realpath(self.env.home)
        self.assertEqual(self.load(), (90, [
            accounts.Account("claude", "claude", os.path.join(home, ".claude"), "you@example.com"),
            accounts.Account("claude-work", "claude", os.path.join(home, ".claude-work"), "work@example.com"),
            accounts.Account("codex", "codex", os.path.join(home, ".codex"), "you@example.com"),
        ], None))

    def test_invalid_account(self):
        self.env.mkdir("a")
        for bad in ("", 3, None, ["x"]):
            with self.subTest(bad=bad):
                self.assert_invalid({"accounts": [{"name": "a", "client": "codex", "dir": "~/a", "account": bad}]},
                                    "accounts[0]", "(a)", "account")

    def test_threshold(self):
        self.env.write_accounts({"threshold": 80, "accounts": []})
        self.assertEqual(self.load()[0], 80)
        self.env.write_accounts({"threshold": 100, "accounts": []})
        self.assertEqual(self.load()[0], 100)
        self.env.write_accounts({"threshold": 0.5, "accounts": []})
        self.assertEqual(self.load()[0], 0.5)

    def test_threshold_invalid(self):
        for bad in (0, 101, -1, "90", True, None):
            self.assert_invalid({"threshold": bad, "accounts": []}, "threshold")


if __name__ == "__main__":
    unittest.main()
