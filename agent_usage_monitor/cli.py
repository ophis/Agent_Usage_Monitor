import argparse
import concurrent.futures
import os
import signal
import sys
import time

from agent_usage_monitor import accounts, claude, codex, proc as procs, store


def _codex(account, environ):
    try:
        windows = codex.probe(account.dir, environ)
    except codex.ProbeError as e:
        return {}, True, "agent-usage-monitor: codex %s: %s" % (account.name, e)
    return dict(windows, fetched_at=int(time.time()), source="app-server"), False, None


def collect(environ):
    path = environ.get("PATH", "")
    local_bin = os.path.join(accounts.home(environ), ".local", "bin")
    if local_bin not in path.split(os.pathsep):
        # claude and codex install here; the host's zsh -l skips ~/.zshrc, where PATH usually gains it
        environ = dict(environ, PATH=path + os.pathsep + local_bin if path else local_bin)
    try:
        threshold, accts, hint = accounts.load(environ)
    except accounts.AccountsError as e:
        print("agent-usage-monitor: %s" % e, file=sys.stderr)
        return 2
    if hint:
        print(hint, file=sys.stderr)
    state = store.state_dir(environ)
    snap, _ = store.read(store.snapshot_path(state))  # store.write reports an unreadable snapshot
    rows = {row["name"]: row for row in (snap or {}).get("accounts", [])}
    jobs = {}
    for account in accts:
        if account.client == "codex":
            jobs[account.name] = (_codex, account, environ)
        else:
            jobs[account.name] = (claude.refresh, account.name, rows.get(account.name, {}), state, environ,
                                  claude.config_dir_of(account, environ))
    updates, failed = {}, set()
    # FR-14: one thread per account, so a stuck probe holds up only its own row
    interrupted = None
    with concurrent.futures.ThreadPoolExecutor(max(len(jobs), 1)) as pool:
        futures = {name: pool.submit(*job) for name, job in jobs.items()}
        try:
            concurrent.futures.wait(futures.values())
        except SystemExit as e:
            # SIGTERM (main): end the probes still running and write the rows that finished
            interrupted = e
            procs.kill_all()
        for name, future in futures.items():
            fields, kept, message = future.result()
            updates[name] = fields
            if kept:
                failed.add(name)
            if message:
                print(message, file=sys.stderr)
    for line in store.write(state, accts, threshold, updates, failed):
        print(line, file=sys.stderr)
    if interrupted:
        raise interrupted
    return 0


def main(argv=None):
    # the default SIGTERM action skips finally, which would orphan the probes' process groups
    signal.signal(signal.SIGTERM, lambda *_: sys.exit(143))
    parser = argparse.ArgumentParser(prog="agent-usage-monitor")
    sub = parser.add_subparsers(dest="command", required=True)
    sub.add_parser("collect", help="read every account's limits and write the snapshot")
    parser.parse_args(argv)
    return collect(os.environ)
