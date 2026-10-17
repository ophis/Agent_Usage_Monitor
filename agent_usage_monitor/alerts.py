"""M2 alerts (FR-1 to FR-3, FR-9): decided from the snapshot inside store.write, deduped in its `notified`."""

import time

from agent_usage_monitor import derive

LABELS = {"five_hour": "5h", "seven_day": "7d"}
SAME_RESET = 600
KEEP = 7 * 86400


def _int_or_none(v):
    return v is None or (isinstance(v, int) and not isinstance(v, bool))


def _valid(key):
    return (isinstance(key, dict) and isinstance(key.get("name"), str) and key.get("window") in derive.WINDOWS
            and key.get("kind") == "full" and "resets_at" in key and _int_or_none(key["resets_at"])
            and isinstance(key.get("sent_at"), int) and not isinstance(key["sent_at"], bool))


def keys(value):
    """`notified` as read, without entries this version cannot use."""
    return [k for k in value if _valid(k)] if isinstance(value, list) else []


def _same_reset(a, b):
    if a is None or b is None:
        return a is None and b is None
    return abs(a - b) < SAME_RESET


def _reset_text(at, now):
    if at is None:
        return "重置时间未知"
    t, today = time.localtime(at), time.localtime(now)
    day = "" if t[:3] == today[:3] else "%d月%d日 " % (t.tm_mon, t.tm_mday)
    return "%s%s 重置" % (day, time.strftime("%H:%M", t))


def evaluate(snap, threshold, now):
    """Update snap["notified"] in place and return this run's alert texts, in row order."""
    notified = keys(snap.get("notified"))
    texts = []
    for row in snap["accounts"]:
        label = "%s · %s" % (row["client"], row.get("account") or row["name"])
        mine = [k for k in notified if k["name"] == row["name"]]

        def ended(k):
            if k["resets_at"] is not None:
                return k["resets_at"] <= now
            pct = (row.get(k["window"]) or {}).get("used_percent")
            return pct is not None and pct < threshold

        done = [k for k in mine if ended(k)]
        if row["available"] is True and done:
            texts.append("%s 现在可用" % label)
            notified = [k for k in notified if k not in done]
            mine = [k for k in mine if k not in done]
        for window in derive.WINDOWS:
            w = row.get(window)
            if w is None or w["used_percent"] is None or w["used_percent"] < threshold:
                continue
            if any(k["window"] == window and _same_reset(k["resets_at"], w["resets_at"]) for k in mine):
                continue
            notified.append({"name": row["name"], "window": window, "kind": "full", "resets_at": w["resets_at"],
                             "sent_at": now})
            texts.append("%s %s 已到 %d%%，%s" % (label, LABELS[window], w["used_percent"],
                                                _reset_text(w["resets_at"], now)))
    # pruned last, so a key older than 7 days still ends in its available-again alert (Mac asleep that long)
    snap["notified"] = [k for k in notified if now - k["sent_at"] <= KEEP]
    return texts
