import Foundation

// TASK-645: the settings window's data, as `read-accounts` prints it and `write-accounts` reads it. The rules live in
// agent_usage_monitor/accounts.py, the same ones collect reads the file with. Foundation only, so macos/Tests can build it.

/// FR-1, FR-2: a widget click opens the app with its widgetURL, launchd starts it with XPC_SERVICE_NAME set to the job
/// label; only LaunchServices (Finder, Spotlight, Dock, `open`) sets `application.<bundle id>.…` (observed on macOS 26,
/// not documented). Anything else refreshes, as before.
func opensSettings(xpcServiceName: String?, openedURL: Bool) -> Bool {
    !openedURL && xpcServiceName?.hasPrefix("application.") == true
}

/// One account; `original` is its object in the file as JSON, so write-accounts keeps the keys the window does not show.
struct AccountRow: Codable, Identifiable, Equatable {
    var id = UUID()
    var name = ""
    var client = "claude"
    var dir = ""
    var account = ""
    var original = "{}"
    /// write-accounts' problem with this row; kept on the row so it moves with it.
    var problem: String?

    enum CodingKeys: String, CodingKey { case name, client, dir, account, original }
}

struct AccountsFile: Decodable {
    /// FR-9: the file cannot be shown; `accounts` then holds the defaults.
    let error: String?
    let threshold: Double
    let accounts: [AccountRow]
    let original: String
}

struct SaveRequest: Encodable {
    let threshold: Double
    let accounts: [AccountRow]
    let original: String
}

struct Problem: Decodable {
    /// The row, or nil for the threshold or the file as a whole.
    let index: Int?
    let message: String
}

struct SaveProblems: Decodable {
    let problems: [Problem]
}

/// The CLI prints one JSON line last; the login shell may print lines before it.
func lastLine<T: Decodable>(_ type: T.Type, _ output: Data) -> T? {
    guard let line = String(decoding: output, as: UTF8.self).split(whereSeparator: \.isNewline).last else { return nil }
    return try? JSONDecoder().decode(type, from: Data(line.utf8))
}
