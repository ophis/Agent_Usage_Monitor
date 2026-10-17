import Foundation

// Assert-based self-test of macos/Widget/Snapshot.swift; `make swift-test` builds and runs it.

var failures = 0

func check<T: Equatable>(_ name: String, _ got: T, _ want: T) {
    if got != want {
        failures += 1
        print("FAIL \(name):\n  got  \(got)\n  want \(want)")
    }
}

let t = 1_792_166_400

func row(_ name: String, five: Int?, seven: Int?, available: Bool?, client: String? = "claude",
         stale: Bool = false, source: String = "app-server", resets: (Int?, Int?) = (nil, nil),
         account: String? = nil) -> Row {
    Row(name: name, client: client, account: account, available: available,
        fiveHour: UsageWindow(usedPercent: five, resetsAt: resets.0),
        sevenDay: UsageWindow(usedPercent: seven, resetsAt: resets.1),
        source: source, stale: stale)
}

func show(_ accounts: [Row]) -> [DisplayRow] {
    rows(Snapshot(generatedAt: t, accounts: accounts), now: t)
}

// rows_sample: 5H above 7D; the title is the client, not the name, and starts with ⚠ when stale; client carried for the colour
check("rows_sample", show([
    row("personal", five: 42, seven: 61, available: true, account: "you@example.com"),
    row("claude-work", five: 0, seven: 20, available: true, stale: true),
    row("codex", five: 15, seven: 33, available: true, client: "codex"),
]), [
    DisplayRow(title: "claude", client: "claude", account: "you@example.com",
               bars: [Bar(label: "5H", percent: 42), Bar(label: "7D", percent: 61)]),
    DisplayRow(title: "⚠ claude", client: "claude", bars: [Bar(label: "5H", percent: 0), Bar(label: "7D", percent: 20)]),
    DisplayRow(title: "codex", client: "codex", bars: [Bar(label: "5H", percent: 15), Bar(label: "7D", percent: 33)]),
])
check("zero_accounts", show([]), [])

// reset_lines: from resets_at and the entry date; none when null or not in the future
check("reset_lines", show([row("claude", five: 4, seven: 9, available: true, resets: (t + 3 * 3600 + 42 * 60, t))])[0].bars,
      [Bar(label: "5H", percent: 4, reset: "resets: 3h 42m"), Bar(label: "7D", percent: 9, reset: nil)])

// reset_text: days, hours and minutes, leading zero units left out
for (s, want) in [(1, "resets: 1m"), (59, "resets: 1m"), (60, "resets: 1m"), (12 * 60 + 59, "resets: 12m"),
                  (38 * 60 + 59, "resets: 38m"), (3599, "resets: 59m"), (3600, "resets: 1h 0m"),
                  (2 * 3600 + 9 * 60, "resets: 2h 9m"), (3 * 3600 + 42 * 60, "resets: 3h 42m"), (86399, "resets: 23h 59m"),
                  (86400, "resets: 1d 0h 0m"), (6 * 86400 + 5 * 60, "resets: 6d 0h 5m"),
                  (6 * 86400 + 3600 + 60, "resets: 6d 1h 1m"), (6 * 86400 + 3 * 3600 + 59, "resets: 6d 3h 0m")] {
    check("reset_text \(s)", resetText(t + s, now: t), want)
}
for (at, name) in [(nil, "nil"), (t, "now"), (t - 60, "past")] as [(Int?, String)] {
    check("reset_text \(name)", resetText(at, now: t), nil)
}

// stale_title: ⚠ leads, so cutting a long title's tail keeps it
check("stale_title", show([row("claude-personal-backup", five: 1, seven: 2, available: true, stale: true)]).map(\.title),
      ["⚠ claude"])

// account_line: the account sits on the last reset line, else on a line of its own under the last bar
let mixed = show([row("a", five: 0, seven: 100, available: false, resets: (nil, t + 60), account: "you@example.com"),
                  row("b", five: 16, seven: 15, available: true, resets: (t + 60, t + 120), account: "work@example.com"),
                  row("c", five: 16, seven: 15, available: true, resets: (t + 60, nil), account: "x@example.com"),
                  row("d", five: 16, seven: 15, available: true, account: "you@example.com"),
                  row("e", five: 16, seven: 15, available: true, resets: (t + 60, t + 120))])
check("account_bar", mixed.map(\.accountBar), [1, 1, 0, nil, nil])
check("account_line", mixed.map(\.accountLine), [false, false, false, true, false])
check("account_none_no_bars", DisplayRow(title: "x", client: nil, account: "you@example.com", bars: []).accountLine, true)

// null_window (TASK-585 D1): the whole window null → no row
let noFive = Row(name: "codex", client: "codex", account: nil, available: true, fiveHour: nil,
                 sevenDay: UsageWindow(usedPercent: 33, resetsAt: nil), source: "app-server", stale: false)
check("null_window", show([noFive]), [DisplayRow(title: "codex", client: "codex", bars: [Bar(label: "7D", percent: 33)])])
// No client (a snapshot from before clients were written): the name stands in.
let noWindows = Row(name: "x", client: nil, account: nil, available: nil, fiveHour: nil, sevenDay: nil, source: "none", stale: false)
check("null_windows", show([noWindows]), [DisplayRow(title: "x", client: nil, bars: [])])

// content: no snapshot or no accounts → nil, the FR-27 no-data view
check("content_nil", content(nil, now: t), nil)
check("content_zero_accounts", content(Snapshot(generatedAt: t, accounts: []), now: t), nil)
check("content_one", content(Snapshot(generatedAt: t, accounts: [noFive]), now: t),
      [DisplayRow(title: "codex", client: "codex", bars: [Bar(label: "7D", percent: 33)])])

// null_percent: track only and —
let unknown = show([row("x", five: nil, seven: 5, available: nil, source: "none")])
check("null_percent", unknown[0].bars, [Bar(label: "5H", percent: nil), Bar(label: "7D", percent: 5)])
check("null_percent_text", unknown[0].bars.map(\.text), ["—", "5%"])
check("null_percent_level", unknown[0].bars[0].level, .unknown)
check("percent_text_over", Bar(label: "5H", percent: 120).text, "120%")

// level_thresholds
for (p, want) in [(0, Level.normal), (79, .normal), (80, .warn), (89, .warn), (90, .critical), (100, .critical),
                  (120, .critical)] {
    check("level \(p)", Bar(label: "5H", percent: p).level, want)
}

// hue: base colour by client; ≥80 yellow and ≥90 red override it; unknown has no fill
for (client, level, want) in [("claude", Level.normal, Hue?.some(.teal)), ("codex", .normal, .periwinkle),
                              ("gemini", .normal, .gray), (nil, .normal, .gray),
                              ("claude", .warn, .yellow), ("codex", .warn, .yellow), (nil, .warn, .yellow),
                              ("claude", .critical, .red), ("gemini", .critical, .red),
                              ("claude", .unknown, nil), ("codex", .unknown, nil)] as [(String?, Level, Hue?)] {
    check("hue \(client ?? "nil") \(level)", hue(client: client, level: level), want)
}

// fill_width: at least the bar height when percent > 0, never past the track
for (p, want) in [(nil, 0.0), (0, 0), (-5, 0), (1, 6), (4, 6), (50, 50), (100, 100), (120, 100)] as [(Int?, Double)] {
    check("fill_width \(p.map(String.init) ?? "nil")", fillWidth(percent: p, track: 100, height: 6), want)
}
check("fill_width_narrow_track", fillWidth(percent: 1, track: 4, height: 6), 4)

// fit: accounts by window rows, dividers between them, +k reserved only on overflow
func account(_ name: String, bars: Int, reset: String? = nil, email: String? = nil) -> DisplayRow {
    DisplayRow(title: name, client: nil, account: email, bars: (0..<bars).map { Bar(label: "\($0)", percent: 1, reset: reset) })
}
let r = Metrics.row, d = Metrics.divider, k = Metrics.more, z = Metrics.reset
// A medium widget is at least 155 pt tall; content margins take at most 16 pt a side. Every row with its reset line.
let medium = [account("claude", bars: 2, reset: "resets: 1h 0m"), account("codex", bars: 1, reset: "resets: 1d 0h")]
check("fit_medium_claude_codex", fit(medium, height: 155 - 2 * 16), Display(rows: medium, more: 0))
check("fit_reset_exact", fit(medium, height: 3 * (r + z) + d), Display(rows: medium, more: 0))
check("fit_reset_short", fit(medium, height: 3 * (r + z) + d - 1), Display(rows: [medium[0]], more: 1))
// fit_medium_overflow: +k sits under the last name, so it costs no account slot
let mediumMore = medium + [account("gemini", bars: 1, reset: "resets: 1m")]
check("fit_medium_overflow", fit(mediumMore, height: 155 - 2 * 16), Display(rows: medium, more: 1))
let claudeCodex = [account("claude", bars: 2), account("codex", bars: 1)]
check("fit_exact", fit(claudeCodex, height: 3 * r + d), Display(rows: claudeCodex, more: 0))
check("fit_short_reserves_more", fit(claudeCodex, height: 3 * r + d - 1), Display(rows: [claudeCodex[0]], more: 1))
let three = [account("a", bars: 2), account("b", bars: 2), account("c", bars: 2)]
check("fit_overflow", fit(three, height: 4 * r + d), Display(rows: Array(three.prefix(2)), more: 1))
check("fit_overflow_short", fit(three, height: 4 * r + d - 1), Display(rows: [three[0]], more: 2))
// A last account of one row with no reset line has no free spot under its name: +k gets its own line.
let singles = [account("a", bars: 1), account("b", bars: 1), account("c", bars: 1)]
check("fit_single_row_needs_room", fit(singles, height: 2 * r + d + k), Display(rows: Array(singles.prefix(2)), more: 1))
check("fit_single_row_short", fit(singles, height: 2 * r + d + k - 1), Display(rows: [singles[0]], more: 2))
check("more_room", [account("a", bars: 2), account("b", bars: 1, reset: "resets: 1m"), account("c", bars: 1),
                    account("d", bars: 0)].map(moreRoom), [0, 0, k, k])
// An account with no reset line takes a line of its own; on a reset line it costs nothing and takes +k's spot.
let emails = [account("a", bars: 2, email: "you@example.com"), account("b", bars: 1, email: "work@example.com")]
check("fit_account_line", fit(emails, height: 3 * r + 2 * z + d), Display(rows: emails, more: 0))
check("fit_account_line_short", fit(emails, height: 3 * r + 2 * z + d - 1), Display(rows: [emails[0]], more: 1))
let emailsReset = [account("a", bars: 2, reset: "resets: 1m", email: "you@example.com"),
                   account("b", bars: 1, reset: "resets: 1m", email: "you@example.com"), account("c", bars: 1)]
check("fit_account_on_reset", fit(emailsReset, height: 3 * (r + z) + d + k), Display(rows: Array(emailsReset.prefix(2)), more: 1))
check("fit_account_on_reset_needs_room", fit(emailsReset, height: 3 * (r + z) + d + k - 1),
      Display(rows: [emailsReset[0]], more: 2))
check("fit_account_no_bars", fit([account("x", bars: 0, email: "you@example.com")], height: r + z),
      Display(rows: [account("x", bars: 0, email: "you@example.com")], more: 0))
// The account on an earlier reset line leaves the last bar row's left side free.
let earlier = DisplayRow(title: "c", client: nil, account: "you@example.com",
                         bars: [Bar(label: "5H", percent: 1, reset: "resets: 1m"), Bar(label: "7D", percent: 1)])
check("more_room_account", [emails[0], emailsReset[0], earlier].map(moreRoom), [k, k, 0])
check("fit_nothing", fit(three, height: 0), Display(rows: [], more: 3))
check("fit_zero", fit([], height: 100), Display(rows: [], more: 0))
check("fit_no_bars_one_row", fit([account("x", bars: 0)], height: r), Display(rows: [account("x", bars: 0)], more: 0))

// fit_compact (medium): one bar line per account, plus a line for the account and resets when it has either
let shot = show([row("a", five: 0, seven: 100, available: false, resets: (nil, t + 11 * 3600), account: "you@example.com"),
                 row("b", five: 25, seven: 24, available: true, resets: (t + 2 * 3600, t + 4 * 86400), account: "work@example.com"),
                 Row(name: "c", client: "codex", account: "you@example.com", available: true, fiveHour: nil,
                     sevenDay: UsageWindow(usedPercent: 0, resetsAt: t + 6 * 86400), source: "app-server", stale: false)])
let cd = Metrics.compactDivider
check("fit_compact_screenshot", fit(shot, height: 155 - 2 * 16, compact: true), Display(rows: shot, more: 0))
check("fit_large_screenshot", fit(shot, height: 155 - 2 * 16), Display(rows: [shot[0]], more: 2))
check("fit_compact_exact", fit(shot, height: 3 * (r + z) + 2 * cd, compact: true), Display(rows: shot, more: 0))
check("fit_compact_short", fit(shot, height: 3 * (r + z) + 2 * cd - 1, compact: true),
      Display(rows: Array(shot.prefix(2)), more: 1))
check("fit_compact_short_more", fit(shot, height: 2 * (r + z) + cd + k - 1, compact: true), Display(rows: [shot[0]], more: 2))
check("second_line", [shot[0], account("x", bars: 1, reset: "resets: 1m"), account("x", bars: 2),
                      account("x", bars: 0, email: "you@example.com")].map(\.secondLine), [true, true, false, true])
check("more_room_compact", [shot[0], account("x", bars: 2, reset: "resets: 1m"), account("x", bars: 2)]
          .map(compactMoreRoom), [k, 0, k])
let bare = [account("a", bars: 2), account("b", bars: 1), account("c", bars: 1)]
check("fit_compact_no_second_line", fit(bare, height: 3 * r + 2 * cd, compact: true), Display(rows: bare, more: 0))
check("fit_compact_no_second_line_short", fit(bare, height: 3 * r + 2 * cd - 1, compact: true),
      Display(rows: Array(bare.prefix(2)), more: 1))

// load_*
let dir = FileManager.default.temporaryDirectory.appendingPathComponent("agent-usage-monitor-swift-test-\(getpid())")
try! FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
defer { try? FileManager.default.removeItem(at: dir) }

func load(_ content: String?) -> Snapshot? {
    let path = dir.appendingPathComponent("snapshot.json").path
    try? FileManager.default.removeItem(atPath: path)
    if let content = content { try! content.write(toFile: path, atomically: true, encoding: .utf8) }
    return loadSnapshot(path: path)
}

check("load_missing", load(nil) == nil, true)
check("load_garbage", load("{not json") == nil, true)
check("load_wrong_shape", load(#"{"schema": 1, "accounts": "nope"}"#) == nil, true)
check("load_no_schema", load(#"{"generated_at": 0, "accounts": []}"#) == nil, true)
check("load_schema_2", load(#"{"schema": 2, "generated_at": 0, "accounts": []}"#) == nil, true)
check("load_schema_1", load(#"{"schema": 1, "generated_at": 0, "accounts": []}"#) == nil, false)
let valid = load("""
{"schema": 1, "generated_at": \(t - 120), "threshold": 90, "unknown_key": [1],
 "accounts": [{"name": "codex", "client": "codex", "dir": "/Users/u/.codex",
   "available": false, "available_at": \(t + 3600),
   "five_hour": null,
   "seven_day": {"used_percent": 93, "resets_at": \(t + 3600)},
   "fetched_at": \(t - 120), "source": "app-server", "stale": false, "usage_disabled_version": null},
  {"name": "old", "five_hour": null, "seven_day": null},
  {"name": "mail", "client": "claude", "account": "you@example.com", "five_hour": null, "seven_day": null}],
 "summary": {"available": [], "next": {"name": "codex", "at": \(t + 3600)}},
 "notified": [{"name": "codex", "window": "seven_day", "kind": "full", "resets_at": \(t + 3600), "sent_at": \(t - 120)}]}
""")
check("load_valid", valid.map { rows($0, now: t) }, [
    DisplayRow(title: "codex", client: "codex", bars: [Bar(label: "7D", percent: 93, reset: "resets: 1h 0m")]),
    DisplayRow(title: "old", client: nil, bars: []),
    DisplayRow(title: "claude", client: "claude", account: "you@example.com", bars: []),
])

// alertLines (macos/Host/Alerts.swift): only `AUM-ALERT ` lines with a JSON string `text`
func alertTexts(_ output: Data) -> [String] { alertLines(output).map(\.text) }
check("alerts_parse", alertTexts(Data("""
Last login: Mon
AUM-ALERT {"text": "codex · cx 5h 已到 92%，17:00 重置"}
AUM-ALERT{"text": "no space"}
AUM-ALERT not json
AUM-ALERT {"text": 3}
AUM-ALERT {"other": "x"}
 AUM-ALERT {"text": "indented"}
AUM-ALERT {"text": "claude · a\\"b \\u73b0\\u5728\\u53ef\\u7528"}

""".utf8)), ["codex · cx 5h 已到 92%，17:00 重置", "claude · a\"b 现在可用"])
check("alerts_empty", alertTexts(Data()), [])
check("alerts_crlf", alertTexts(Data("motd\r\nAUM-ALERT {\"text\": \"x\"}\r\n".utf8)), ["x"])
check("alerts_no_newline", alertTexts(Data(#"AUM-ALERT {"text": "x"}"#.utf8)), ["x"])
// The line goes back to record-alerts verbatim, add and remove included.
let full = #"AUM-ALERT {"text": "x", "add": [{"name": "cx"}], "remove": []}"#
check("alerts_line", alertLines(Data("motd\r\n\(full)\r\n".utf8)), [AlertLine(text: "x", line: full)])

if failures > 0 {
    print("\(failures) failed")
    exit(1)
}
print("swift-test ok")
