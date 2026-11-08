import AppKit
import Darwin
import Foundation

/// Quit and force-quit. An application object stays on AppKit. Otherwise the path decides.
enum ProcessActions {
    @MainActor
    static func terminate(pid: pid_t) async -> ProcessActionResult {
        await quitApplicationOrSignal(pid: pid, timeoutNanoseconds: 2_500_000_000, force: false) { app in
            app.terminate()
        }
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
        await quitApplicationOrSignal(pid: pid, timeoutNanoseconds: 2_000_000_000, force: true) { app in
            app.forceTerminate()
        }
    }

    @MainActor
    private static func quitApplicationOrSignal(
        pid: pid_t,
        timeoutNanoseconds: UInt64,
        force: Bool,
        application: (NSRunningApplication) -> Bool
    ) async -> ProcessActionResult {
        if let app = NSRunningApplication(processIdentifier: pid) {
            guard application(app) else { return .requestFailed }
            return await waitForExit(pid: pid, timeoutNanoseconds: timeoutNanoseconds)
        }
        return await signalOrRefuse(pid: pid, force: force, timeoutNanoseconds: timeoutNanoseconds)
    }

    @MainActor
    private static func signalOrRefuse(
        pid: pid_t,
        force: Bool,
        timeoutNanoseconds: UInt64
    ) async -> ProcessActionResult {
        let route = ProcessQuitRoute.decide(
            hasApplication: false,
            executablePath: executablePath(pid: pid),
            force: force
        )
        switch route {
        case .application, .refused:
            return ProcessQuitRoute.refusedResult(isAlive: isAlive(pid))
        case .signal(.sigterm):
            return await deliver(SIGTERM, pid: pid, timeoutNanoseconds: timeoutNanoseconds)
        case .signal(.sigkill):
            return await deliver(SIGKILL, pid: pid, timeoutNanoseconds: timeoutNanoseconds)
        }
    }

    @MainActor
    private static func deliver(
        _ signal: Int32,
        pid: pid_t,
        timeoutNanoseconds: UInt64
    ) async -> ProcessActionResult {
        if kill(pid, signal) != 0 {
            return ProcessQuitRoute.signalFailure(noSuchProcess: errno == ESRCH)
        }
        return await waitForExit(pid: pid, timeoutNanoseconds: timeoutNanoseconds)
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

    private static func executablePath(pid: pid_t) -> String? {
        let capacity = 4_096
        var buffer = [CChar](repeating: 0, count: capacity)
        let length = buffer.withUnsafeMutableBufferPointer { raw -> Int32 in
            pulse_proc_pidpath(pid, raw.baseAddress, UInt32(capacity))
        }
        guard length > 0 else { return nil }
        return String(cString: buffer)
    }
}

@_silgen_name("proc_pidpath")
private func pulse_proc_pidpath(
    _ pid: Int32,
    _ buffer: UnsafeMutableRawPointer?,
    _ buffersize: UInt32
) -> Int32
