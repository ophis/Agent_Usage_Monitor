import AppKit
import WidgetKit

// Any launch (including a widget click) stamps spike.txt so the widget shows when the host last ran.
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        let dir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".local/state/quotaboard", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true,
                                                    attributes: [.posixPermissions: 0o700])
            let line = "opened \(ISO8601DateFormatter().string(from: Date()))\n"
            try line.write(to: dir.appendingPathComponent("spike.txt"), atomically: true, encoding: .utf8)
        } catch {
            FileHandle.standardError.write(Data("write failed: \(error)\n".utf8))
        }
        WidgetCenter.shared.reloadAllTimelines()
        // reloadAllTimelines is fire-and-forget XPC; give it a moment before exiting.
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { NSApp.terminate(nil) }
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
