import XCTest

/// Source shape for launch reconcile and quit-time resume. Not a live signal.
final class PausedProcessWiringSourceTests: XCTestCase {
    func testApplicationWillTerminateResumesPausedProcesses() throws {
        let delegate = try repoText("Pulse/MenuBar/PulseAppDelegate.swift")
        XCTAssertFalse(delegate.contains("UserDefaults"))
        XCTAssertFalse(delegate.contains("AppStorage"))
        let terminate = try functionBody(named: "applicationWillTerminate", in: delegate)
        XCTAssertTrue(terminate.contains("ProcessPause.resumeAll"))
        XCTAssertTrue(terminate.contains("pausedLedger"))
        XCTAssertTrue(terminate.contains("restoreLoweredPrioritiesForQuit"))
        XCTAssertTrue(terminate.contains("menuBar.uninstall()"))

        let launch = try functionBody(named: "didLaunch", in: delegate)
        XCTAssertTrue(launch.contains("ProcessPause.reconcileStored()"))
        XCTAssertTrue(launch.contains("installPausedLedger"))

        let signals = try repoText("Pulse/Sampling/ProcessPauseSignal.swift")
        XCTAssertTrue(signals.contains("SIGSTOP"))
        XCTAssertTrue(signals.contains("SIGCONT"))
        let resumeAll = try functionBody(named: "resumeAll", in: signals)
        XCTAssertTrue(resumeAll.contains("resume(record.pid)"))
        XCTAssertTrue(resumeAll.contains("clear()"))
        XCTAssertTrue(resumeAll.contains("PausedProcessStore.save"))

        let store = try repoText("Pulse/Models/PausedProcessStore.swift")
        XCTAssertTrue(store.contains("pulse.pausedProcesses"))

        let sidebar = try WiringSourceText.text(for: "ProcessDetailSidebar")
        XCTAssertFalse(sidebar.contains("NSAlert"))
        XCTAssertFalse(sidebar.contains("UserDefaults"))
        XCTAssertTrue(sidebar.contains("更多"))
        XCTAssertTrue(sidebar.contains("priorityMenuOffer"))
        XCTAssertFalse(sidebar.contains("挂起"))
        XCTAssertFalse(sidebar.contains("冻结"))
        XCTAssertFalse(sidebar.contains("限速"))
        XCTAssertFalse(sidebar.contains("节流"))
    }

    private func repoText(_ relative: String) throws -> String {
        try String(contentsOf: repoRoot().appendingPathComponent(relative), encoding: .utf8)
    }

    private func repoRoot() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private func functionBody(named name: String, in source: String) throws -> String {
        let patterns = ["func \(name)(", "func \(name)()"]
        for pattern in patterns {
            guard let range = source.range(of: pattern),
                  let brace = source[range.lowerBound...].firstIndex(of: "{")
            else { continue }
            return try balancedSlice(from: brace, in: source, label: name)
        }
        throw PauseSourceError.missing(name)
    }

    private func balancedSlice(from start: String.Index, in source: String, label: String) throws -> String {
        var depth = 0
        var index = start
        while index < source.endIndex {
            let character = source[index]
            if character == "{" { depth += 1 }
            if character == "}" {
                depth -= 1
                if depth == 0 { return String(source[start...index]) }
            }
            index = source.index(after: index)
        }
        throw PauseSourceError.missing("balanced brace for \(label)")
    }
}

private enum PauseSourceError: Error, CustomStringConvertible {
    case missing(String)
    var description: String {
        switch self {
        case .missing(let detail): return "missing \(detail)"
        }
    }
}
