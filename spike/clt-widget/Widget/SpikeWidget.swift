import OSLog
import SwiftUI
import WidgetKit

private let log = Logger(subsystem: "com.ophis.quotaboard.spike", category: "widget")

struct SpikeEntry: TimelineEntry {
    let date: Date
    let text: String
}

struct SpikeProvider: TimelineProvider {
    func placeholder(in context: Context) -> SpikeEntry {
        SpikeEntry(date: Date(), text: "…")
    }

    func getSnapshot(in context: Context, completion: @escaping (SpikeEntry) -> Void) {
        completion(read())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<SpikeEntry>) -> Void) {
        completion(Timeline(entries: [read()], policy: .after(Date().addingTimeInterval(300))))
    }

    private func read() -> SpikeEntry {
        // In the sandbox NSHomeDirectory() is the container; the exception is relative to the real home.
        let home = String(cString: getpwuid(getuid())!.pointee.pw_dir)
        let path = home + "/.local/state/quotaboard/spike.txt"
        let text: String
        do {
            text = try String(contentsOfFile: path, encoding: .utf8)
            log.notice("read ok: \(text, privacy: .public)")
        } catch {
            text = "read failed: \(error.localizedDescription)"
            log.error("read failed: \(String(describing: error), privacy: .public)")
        }
        return SpikeEntry(date: Date(), text: text)
    }
}

struct SpikeView: View {
    let entry: SpikeEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Quotaboard spike").font(.headline)
            Text(entry.text).font(.system(.body, design: .monospaced))
            Text("rendered \(entry.date, style: .time)").font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .containerBackground(.fill.tertiary, for: .widget)
    }
}

@main
struct SpikeWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "SpikeWidget", provider: SpikeProvider()) { SpikeView(entry: $0) }
            .configurationDisplayName("Quotaboard Spike")
            .description("Reads ~/.local/state/quotaboard/spike.txt")
            .supportedFamilies([.systemMedium])
    }
}
