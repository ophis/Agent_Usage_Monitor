import AppKit
import UserNotifications
import WidgetKit

// FR-23, FR-24: run `agent-usage-monitor collect`, refresh the widget, exit. M2 FR-8: post the alerts it prints,
// then record the ones macOS took (TASK-640).

let collectTimeout: TimeInterval = 40
let killGrace: TimeInterval = 2
// reloadAllTimelines is fire-and-forget XPC; give it a moment before exiting.
let exitDelay: TimeInterval = 2
// After collect exits, a stray child of the login shell may still hold its stdout open.
let outputGrace: TimeInterval = 2
// The first alert waits on the user's answer to macOS's Allow prompt. With collect (40 + 2 + 2 s), the adds,
// record-alerts (20 + 2 s) and exitDelay the host ends by about 268 s, before the LaunchAgent's next run at 300 s.
let authTimeout: TimeInterval = 180
let addTimeout: TimeInterval = 20
let recordTimeout: TimeInterval = 20
let settingsHint = "turn them on in 系统设置 › 通知 › Agent Usage Monitor (System Settings › Notifications › Agent Usage Monitor)"
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

/// One delivery's completion, run once: by the last add, a refusal or a timeout; passes the lines macOS took.
final class Delivery {
    var done: (([String]) -> Void)?
    var granted = false
    var sent: [String] = []

    func finish(_ problem: String?) {
        guard let done = done else { return }
        self.done = nil
        if let problem = problem { logLine(problem) }
        done(sent)
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

    /// FR-8: hand every alert to macOS; pass on the lines of those it took. The rest stay unrecorded, so the next
    /// collect prints them again.
    private func deliver(_ alerts: [AlertLine], then done: @escaping ([String]) -> Void) {
        guard !alerts.isEmpty else { return done([]) }
        let delivery = Delivery()
        delivery.done = done
        DispatchQueue.main.asyncAfter(deadline: .now() + authTimeout) {
            guard !delivery.granted else { return }
            delivery.finish("no answer to the notification prompt within \(Int(authTimeout)) s; \(alerts.count) alert(s) "
                            + "kept for the next run; if no prompt shows, \(settingsHint)")
        }
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert]) { granted, error in
            DispatchQueue.main.async {
                // Already given up: posting now would repeat on the next run.
                guard delivery.done != nil else { return }
                guard granted else {
                    let reason = error.map { ": \($0)" } ?? ""
                    return delivery.finish("notifications not allowed\(reason); \(alerts.count) alert(s) kept for the next run; "
                                           + settingsHint)
                }
                delivery.granted = true
                DispatchQueue.main.asyncAfter(deadline: .now() + addTimeout) {
                    delivery.finish("\(alerts.count - delivery.sent.count) alert(s) not handed to macOS within "
                                    + "\(Int(addTimeout)) s; kept for the next run")
                }
                let group = DispatchGroup()
                for alert in alerts {
                    let content = UNMutableNotificationContent()
                    content.title = "Agent Usage Monitor"
                    content.body = alert.text
                    group.enter()
                    center.add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)) { error in
                        DispatchQueue.main.async {
                            if let error = error {
                                logLine("cannot post an alert, kept for the next run: \(error)")
                            } else {
                                delivery.sent.append(alert.line)
                            }
                            group.leave()
                        }
                    }
                }
                group.notify(queue: .main) { delivery.finish(nil) }
            }
        }
    }

    /// TASK-640: `record-alerts` records the lines macOS took in `notified`. No login shell: it needs no PATH.
    private func record(_ lines: [String], then done: @escaping () -> Void) {
        guard !lines.isEmpty else { return done() }
        let task = Process()
        task.executableURL = URL(fileURLWithPath: NSHomeDirectory() + "/.local/bin/agent-usage-monitor")
        task.arguments = ["record-alerts"]
        let pipe = Pipe()
        task.standardInput = pipe
        task.terminationHandler = { _ in DispatchQueue.main.async(execute: done) }
        do {
            try task.run()
        } catch {
            logLine("cannot record \(lines.count) sent alert(s), the next run sends them again: \(error)")
            return done()
        }
        do {
            try pipe.fileHandleForWriting.write(contentsOf: Data(lines.map { $0 + "\n" }.joined().utf8))
            try pipe.fileHandleForWriting.close()
        } catch {
            logLine("cannot pass the sent alerts to record-alerts, the next run sends them again: \(error)")
        }
        let pid = task.processIdentifier
        DispatchQueue.main.asyncAfter(deadline: .now() + recordTimeout) {
            guard task.isRunning else { return }
            logLine("record-alerts ran over \(Int(recordTimeout)) s, stopping it")
            task.terminate()
            DispatchQueue.main.asyncAfter(deadline: .now() + killGrace) {
                if task.isRunning { kill(pid, SIGKILL) }
            }
        }
    }

    private func finished(_ output: Data) {
        WidgetCenter.shared.reloadAllTimelines()
        deliver(alertLines(output)) { sent in
            self.record(sent) {
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
}

// One host at a time; the lowest pid stays so two hosts started together don't both exit.
let me = getpid()
if NSRunningApplication.runningApplications(withBundleIdentifier: Bundle.main.bundleIdentifier ?? "")
    .contains(where: { $0.processIdentifier < me }) {
    exit(0)
}

// A record-alerts that exits before reading its stdin must fail the write, not kill the host.
signal(SIGPIPE, SIG_IGN)
let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
