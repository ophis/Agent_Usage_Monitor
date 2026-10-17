"""Account list (FR-1 to FR-4)."""

import collections
import json
import os

# account: a display string such as an email, or None; unlike name it may repeat
Account = collections.namedtuple("Account", "name client dir account", defaults=(None,))

CLIENTS = ("claude", "codex")
DEFAULT_THRESHOLD = 90


class AccountsError(Exception):
    pass


def home(environ):
    return environ.get("HOME") or os.path.expanduser("~")


def expand(path, environ):
    if path == "~" or path.startswith("~/"):
        path = home(environ) + path[1:]
    return os.path.realpath(path)


def config_path(environ):
    base = environ.get("XDG_CONFIG_HOME") or os.path.join(home(environ), ".config")
    return os.path.join(base, "agent-usage-monitor", "accounts.json")


def load(environ):
    """Return (threshold, [Account], hint); hint is a stderr line or None."""
    path = config_path(environ)
    try:
        with open(path, encoding="utf-8") as f:
            text = f.read()
    except FileNotFoundError:
        dirs = [(name, expand("~/." + name, environ)) for name in CLIENTS]
        accounts = [Account(name, name, d) for name, d in dirs if os.path.isdir(d)]
        hint = ("agent-usage-monitor: no account list at %s; using default accounts in ~/.claude and ~/.codex"
                % path)
        return DEFAULT_THRESHOLD, accounts, hint
    except (OSError, UnicodeDecodeError) as e:
        raise AccountsError("%s: cannot read: %s" % (path, e))

    def fail(problem):
        return AccountsError("%s: %s" % (path, problem))

    try:
        data = json.loads(text)
    except (ValueError, RecursionError) as e:
        raise fail("not valid JSON: %s" % e)
    if not isinstance(data, dict):
        raise fail("top level must be an object")

    threshold = data.get("threshold", DEFAULT_THRESHOLD)
    if isinstance(threshold, bool) or not isinstance(threshold, (int, float)) or not 0 < threshold <= 100:
        raise fail("threshold must be a number in (0, 100]")

    items = data.get("accounts")
    if not isinstance(items, list):
        raise fail("accounts must be a list")

    accounts = []
    seen_names = {}
    seen_dirs = {}
    for i, item in enumerate(items):
        where = "accounts[%d]" % i
        if not isinstance(item, dict):
            raise fail("%s: must be an object" % where)
        name = item.get("name")
        if not isinstance(name, str) or not name:
            raise fail("%s: name must be a non-empty string" % where)
        where = "%s (%s)" % (where, name)
        if name in seen_names:
            raise fail("%s: duplicate name, also accounts[%d]" % (where, seen_names[name]))
        client = item.get("client")
        if client not in CLIENTS:
            raise fail("%s: client must be one of %s" % (where, ", ".join(CLIENTS)))
        raw_dir = item.get("dir")
        if not isinstance(raw_dir, str) or not raw_dir:
            raise fail("%s: dir must be a non-empty string" % where)
        real = expand(raw_dir, environ)
        if not os.path.isdir(real):
            raise fail("%s: dir %s is not an existing directory" % (where, raw_dir))
        if real in seen_dirs:
            raise fail("%s: dir is the same directory as accounts[%d]" % (where, seen_dirs[real]))
        account = item.get("account")
        if "account" in item and (not isinstance(account, str) or not account):
            raise fail("%s: account must be a non-empty string" % where)
        seen_names[name] = i
        seen_dirs[real] = i
        accounts.append(Account(name, client, real, account))
    return threshold, accounts, None
