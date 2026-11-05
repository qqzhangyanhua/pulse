import AppKit
import Darwin
import Foundation

/// Maps a pid to `NSRunningApplication` and performs quit / force-quit.
enum ProcessActions {
    @MainActor
    static func terminate(pid: pid_t) async -> ProcessActionResult {
        guard let app = NSRunningApplication(processIdentifier: pid) else {
            return isAlive(pid) ? .requestFailed : .notFound
        }
        guard app.terminate() else { return .requestFailed }
        return await waitForExit(pid: pid, timeoutNanoseconds: 2_500_000_000)
    }

    @MainActor
    static func confirmForceQuit(displayName: String) -> Bool {
        let alert = NSAlert()
        alert.messageText = "立即退出“\(displayName)”？"
        alert.informativeText = "应用没有响应正常退出。系统将立即结束该进程。"
        alert.alertStyle = .informational
        alert.addButton(withTitle: "立即退出")
        alert.addButton(withTitle: "取消")
        return alert.runModal() == .alertFirstButtonReturn
    }

    @MainActor
    static func forceTerminate(pid: pid_t) async -> ProcessActionResult {
        guard let app = NSRunningApplication(processIdentifier: pid) else {
            return isAlive(pid) ? .requestFailed : .notFound
        }
        guard app.forceTerminate() else { return .requestFailed }
        return await waitForExit(pid: pid, timeoutNanoseconds: 2_000_000_000)
    }

    @MainActor
    private static func waitForExit(pid: pid_t, timeoutNanoseconds: UInt64) async -> ProcessActionResult {
        let steps = 25
        let slice = timeoutNanoseconds / UInt64(steps)
        for _ in 0..<steps {
            try? await Task.sleep(nanoseconds: slice)
            if !isAlive(pid) {
                return .exited
            }
        }
        return isAlive(pid) ? .stillRunning : .exited
    }

    /// Existence check only (`signal 0`); never used as a kill path.
    private static func isAlive(_ pid: pid_t) -> Bool {
        if NSRunningApplication(processIdentifier: pid) != nil {
            return true
        }
        if kill(pid, 0) == 0 {
            return true
        }
        return errno == EPERM
    }
}
