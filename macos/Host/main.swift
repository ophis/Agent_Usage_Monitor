import AppKit
import UserNotifications
import WidgetKit

// FR-23, FR-24: run `agent-usage-monitor collect`, refresh the widget, exit. M2 FR-8: post the alerts it prints.

let collectTimeout: TimeInterval = 40
let killGrace: TimeInterval = 2
// reloadAllTimelines is fire-and-forget XPC; give it a moment before exiting.
let exitDelay: TimeInterval = 2
// After collect exits, a stray child of the login shell may still hold its stdout open.
let outputGrace: TimeInterval = 2
// The first alert waits on the user's answer to macOS's Allow prompt; don't hold up the next collect for it.
let deliverTimeout: TimeInterval = 60
let logPath = NSHomeDirectory() + "/Library/Logs/agent-usage-monitor.log"

/// FR-8: alert send failures go to the log file, also when a widget click (not launchd) started the host.
func logLine(_ line: String) {
    let data = Data("agent-usage-monitor host: \(line)\n".utf8)
    guard let log = FileHandle(forWritingAtPath: logPath) else {
        FileHandle.standardError.write(data)
        return
    }
    log.seekToEndOfFile()
    log.write(data)
    log.closeFile()
}

/// collect's stdout, read on a background thread until EOF.
final class Output {
    private let lock = NSLock()
    private var data = Data()
    let eof = DispatchGroup()

    func append(_ chunk: Data) {
        lock.lock()
        data.append(chunk)
        lock.unlock()
    }

    var bytes: Data {
        lock.lock()
        defer { lock.unlock() }
        return data
    }
}

/// One delivery's completion, run once: by the last add, a refusal or the timeout.
final class Delivery {
    var done: (() -> Void)?

    func finish(_ problem: String?) {
        guard let done = done else { return }
        self.done = nil
        if let problem = problem { logLine(problem) }
        done()
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    private var pendingClick = false
    private var timedOut = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        UNUserNotificationCenter.current().delegate = self
        run()
    }

    // A widget click while this host runs arrives as a reopen, not a new launch.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        pendingClick = true
        return false
    }

    // Show alerts as banners even if a widget click made this app active.
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .list])
    }

    private func run() {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/zsh")
        // zsh -l only for the login PATH that has claude and codex.
        task.arguments = ["-l", "-c", "exec \"$HOME/.local/bin/agent-usage-monitor\" collect --emit-alerts"]
        let pipe = Pipe()
        task.standardOutput = pipe
        let output = Output()
        output.eof.enter()
        task.terminationHandler = { _ in
            DispatchQueue.global().async {
                _ = output.eof.wait(timeout: .now() + outputGrace)
                let bytes = output.bytes
                DispatchQueue.main.async { self.finished(bytes) }
            }
        }
        do {
            try task.run()
        } catch {
            FileHandle.standardError.write(Data("agent-usage-monitor host: cannot start /bin/zsh: \(error)\n".utf8))
            finished(Data())
            return
        }
        DispatchQueue.global().async {
            let reader = pipe.fileHandleForReading
            var chunk = reader.availableData
            while !chunk.isEmpty {
                output.append(chunk)
                chunk = reader.availableData
            }
            output.eof.leave()
        }
        let pid = task.processIdentifier
        DispatchQueue.main.asyncAfter(deadline: .now() + collectTimeout) {
            guard task.isRunning else { return }
            self.timedOut = true
            FileHandle.standardError.write(Data("agent-usage-monitor host: collect ran over \(Int(collectTimeout)) s, stopping it\n".utf8))
            task.terminate()
            DispatchQueue.main.asyncAfter(deadline: .now() + killGrace) {
                if task.isRunning { kill(pid, SIGKILL) }
            }
        }
    }

    /// FR-8: hand every alert to macOS; collect has already recorded them, so a failure is only logged.
    private func deliver(_ texts: [String], then done: @escaping () -> Void) {
        guard !texts.isEmpty else { return done() }
        let delivery = Delivery()
        delivery.done = done
        DispatchQueue.main.asyncAfter(deadline: .now() + deliverTimeout) {
            delivery.finish("\(texts.count) alert(s) not handed to macOS within \(Int(deliverTimeout)) s")
        }
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert]) { granted, error in
            DispatchQueue.main.async {
                guard granted else {
                    let reason = error.map { ": \($0)" } ?? ""
                    return delivery.finish("notifications not allowed\(reason); \(texts.count) alert(s) dropped")
                }
                let group = DispatchGroup()
                for text in texts {
                    let content = UNMutableNotificationContent()
                    content.title = "Agent Usage Monitor"
                    content.body = text
                    group.enter()
                    center.add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)) { error in
                        if let error = error { logLine("cannot post an alert: \(error)") }
                        group.leave()
                    }
                }
                group.notify(queue: .main) { delivery.finish(nil) }
            }
        }
    }

    private func finished(_ output: Data) {
        WidgetCenter.shared.reloadAllTimelines()
        deliver(alertTexts(output)) {
            DispatchQueue.main.asyncAfter(deadline: .now() + exitDelay) {
                if self.pendingClick && !self.timedOut {
                    self.pendingClick = false
                    self.run()
                } else {
                    NSApp.terminate(nil)
                }
            }
        }
    }
}

// One host at a time; the lowest pid stays so two hosts started together don't both exit.
let me = getpid()
if NSRunningApplication.runningApplications(withBundleIdentifier: Bundle.main.bundleIdentifier ?? "")
    .contains(where: { $0.processIdentifier < me }) {
    exit(0)
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
