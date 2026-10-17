import AppKit
import WidgetKit

// FR-23, FR-24: run `agent-usage-monitor collect`, refresh the widget, exit.

let collectTimeout: TimeInterval = 40
let killGrace: TimeInterval = 2
// reloadAllTimelines is fire-and-forget XPC; give it a moment before exiting.
let exitDelay: TimeInterval = 2

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var pendingClick = false
    private var timedOut = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        run()
    }

    // A widget click while this host runs arrives as a reopen, not a new launch.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        pendingClick = true
        return false
    }

    private func run() {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/zsh")
        // zsh -l only for the login PATH that has claude and codex.
        task.arguments = ["-l", "-c", "exec \"$HOME/.local/bin/agent-usage-monitor\" collect"]
        task.terminationHandler = { _ in DispatchQueue.main.async { self.finished() } }
        do {
            try task.run()
        } catch {
            FileHandle.standardError.write(Data("agent-usage-monitor host: cannot start /bin/zsh: \(error)\n".utf8))
            finished()
            return
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

    private func finished() {
        WidgetCenter.shared.reloadAllTimelines()
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
