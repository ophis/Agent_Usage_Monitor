import Foundation

// FR-8: the alerts in `collect --emit-alerts` output. Foundation only, so macos/Tests can build it alone.

let alertPrefix = "AUM-ALERT "

private struct Alert: Decodable {
    let text: String
}

/// The text of each `AUM-ALERT {"text": …}` line, in order; any other line (login-shell output) is skipped.
func alertTexts(_ output: Data) -> [String] {
    String(decoding: output, as: UTF8.self).split(whereSeparator: \.isNewline).compactMap { line in
        guard line.hasPrefix(alertPrefix) else { return nil }
        return (try? JSONDecoder().decode(Alert.self, from: Data(line.dropFirst(alertPrefix.count).utf8)))?.text
    }
}
