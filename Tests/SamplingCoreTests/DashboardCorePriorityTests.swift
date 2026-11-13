import XCTest
@testable import SamplingCore

/// Who can be lowered, the table mark, and restore-on-quit. No Darwin call.
final class DashboardCorePriorityTests: XCTestCase {
    func testOwnUserNonSystemProcessOffersLowerPriority() {
        let core = ready(eligible(42, "Mail", path: "/Applications/Mail.app/Contents/MacOS/Mail", bundleIdentifier: "com.apple.mail"))
        XCTAssertEqual(core.priorityMenuOffer(selfUid: 501), .lower)
        XCTAssertEqual(PriorityMenuOffer.lower.title, "降低优先级")
        XCTAssertEqual(PriorityMenuOffer.restore.title, "恢复优先级")
    }

    func testIneligibleRowsDoNotOfferLowerPriority() {
        let eligibleRow = eligible(42, "Mail")
        XCTAssertNil(ready(eligible(42, "Mail", userID: 0)).priorityMenuOffer(selfUid: 501))
        XCTAssertNil(ready(eligible(42, "Mail", userID: nil)).priorityMenuOffer(selfUid: 501))
        let missingStart = ready(eligible(42, "Mail", start: nil))
        XCTAssertEqual(missingStart.priorityMenuOffer(selfUid: 501), .lower)
        XCTAssertNil(missingStart.pauseMenuOffer(selfUid: 501))
        XCTAssertNil(ready(eligible(42, "Mail", path: nil)).priorityMenuOffer(selfUid: 501))
        XCTAssertNil(ready(eligible(42, "Mail", path: "")).priorityMenuOffer(selfUid: 501))
        for path in [
            "/System/Library/CoreServices/Finder.app/Contents/MacOS/Finder",
            "/usr/libexec/runningboardd",
            "/usr/sbin/syslogd",
            "/sbin/launchd",
            "/Systematic/tool",
            "/usr/libexecfoo",
        ] {
            let row = eligible(42, "Finder", path: path, bundleIdentifier: "com.apple.finder")
            XCTAssertNil(ready(row).priorityMenuOffer(selfUid: 501), path)
            var blocked = ready(row)
            XCTAssertEqual(blocked.lowerSelectedPriority(selfUid: 501), [], path)
            XCTAssertFalse(blocked.isLoweredPriority(pid: 42), path)
        }
        for path in ["/usr/bin/ruby", "/usr/lib/dyld", "/opt/homebrew/bin/node", "/Users/me/bin/tool"] {
            XCTAssertEqual(ready(eligible(42, "tool", path: path)).priorityMenuOffer(selfUid: 501), .lower, path)
        }
        XCTAssertEqual(ready(eligibleRow).priorityMenuOffer(selfUid: 501), .lower)
    }

    func testGroupedVisibleRowDoesNotOfferLowerPriority() {
        var core = DashboardCore(ownPid: 1)
        accept(&core, rows: [
            eligible(4, "Mail", memory: 200),
            eligible(9, "Mail", memory: 50),
        ])
        _ = core.setGroupedByApp(true)
        _ = core.select(pid: 4)
        XCTAssertEqual(core.selectedRow?.groupedMemberCount, 2)
        XCTAssertNil(core.priorityMenuOffer(selfUid: 501))
        XCTAssertEqual(core.lowerSelectedPriority(selfUid: 501), [])
        XCTAssertFalse(core.isLoweredPriority(pid: 4))
    }

    func testPausedProcessCanAlsoBeLowered() {
        var core = ready(eligible(42, "Mail", start: 100))
        XCTAssertEqual(core.pauseSelected(selfUid: 501), [.pauseProcess(pid: 42)])
        XCTAssertEqual(core.priorityMenuOffer(selfUid: 501), .lower)
        XCTAssertEqual(core.lowerSelectedPriority(selfUid: 501), [.lowerPriority(pid: 42)])
        core.finishLowerPriority(pid: 42, succeeded: true)
        XCTAssertTrue(core.isPaused(pid: 42))
        XCTAssertTrue(core.isLoweredPriority(pid: 42))
        XCTAssertEqual(core.pauseMenuOffer(selfUid: 501), .resume)
        XCTAssertEqual(core.priorityMenuOffer(selfUid: 501), .restore)
    }

    func testQuitRestoresEveryLoweredProcessAndClearsTheSet() {
        var core = DashboardCore(ownPid: 1)
        accept(&core, rows: [eligible(42, "Mail"), eligible(7, "Notes")])
        _ = core.select(pid: 42)
        XCTAssertEqual(core.lowerSelectedPriority(selfUid: 501), [.lowerPriority(pid: 42)])
        core.finishLowerPriority(pid: 42, succeeded: true)
        _ = core.select(pid: 7)
        XCTAssertEqual(core.lowerSelectedPriority(selfUid: 501), [.lowerPriority(pid: 7)])
        core.finishLowerPriority(pid: 7, succeeded: true)
        let restored = core.restoreLoweredPrioritiesForQuit()
        XCTAssertEqual(restored, [.restorePriority(pid: 7), .restorePriority(pid: 42)])
        XCTAssertFalse(core.isLoweredPriority(pid: 7))
        XCTAssertFalse(core.isLoweredPriority(pid: 42))
        XCTAssertEqual(core.restoreLoweredPrioritiesForQuit(), [])
    }

    func testTablesAndQuitRestoreUseTheGlossaryMark() throws {
        let pane = try WiringSourceText.text(for: "ProcessTablePane")
        let energy = try repoText("Pulse/Views/EnergyProcessTable.swift")
        let mark = try repoText("Pulse/Views/LoweredPriorityMark.swift")
        let package = try repoText("Package.swift")
        let parts = package.components(separatedBy: "sources:")
        XCTAssertEqual(parts.count, 2)
        XCTAssertTrue(pane.contains("已降低优先级"))
        XCTAssertTrue(energy.contains("已降低优先级"))
        XCTAssertTrue(mark.contains("已降低优先级"))
        XCTAssertTrue(mark.contains("恢复优先级"))
        XCTAssertFalse(pane.contains("限速"))
        XCTAssertFalse(pane.contains("节流"))
        XCTAssertFalse(energy.contains("限速"))
        XCTAssertFalse(energy.contains("节流"))
        XCTAssertTrue(parts[0].contains("\"Sampling/ProcessPriority.swift\""))
        XCTAssertFalse(parts[1].contains("ProcessPriority.swift"))
        XCTAssertTrue(parts[1].contains("\"Models/DashboardCore+Priority.swift\""))
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

    func testFailedLowerDoesNotMarkAndSuccessfulLowerDoes() {
        var core = ready(eligible(42, "Mail", start: nil))
        XCTAssertFalse(core.isLoweredPriority(pid: 42))
        XCTAssertEqual(core.lowerSelectedPriority(selfUid: 501), [.lowerPriority(pid: 42)])
        core.finishLowerPriority(pid: 42, succeeded: false)
        XCTAssertFalse(core.isLoweredPriority(pid: 42))
        XCTAssertEqual(core.priorityMenuOffer(selfUid: 501), .lower)
        XCTAssertEqual(core.restoreLoweredPrioritiesForQuit(), [])

        core.finishLowerPriority(pid: 42, succeeded: true)
        XCTAssertTrue(core.isLoweredPriority(pid: 42))
        XCTAssertEqual(core.priorityMenuOffer(selfUid: 501), .restore)
        XCTAssertEqual(core.restoreLoweredPrioritiesForQuit(), [.restorePriority(pid: 42)])
        XCTAssertFalse(core.isLoweredPriority(pid: 42))
    }

    func testLoweringMarksTheProcessAndRestoreClearsIt() {
        var core = ready(eligible(42, "Mail", start: 100))
        XCTAssertFalse(core.isLoweredPriority(pid: 42))
        let lowered = core.lowerSelectedPriority(selfUid: 501)
        XCTAssertEqual(lowered, [.lowerPriority(pid: 42)])
        XCTAssertFalse(core.isLoweredPriority(pid: 42))
        core.finishLowerPriority(pid: 42, succeeded: true)
        XCTAssertTrue(core.isLoweredPriority(pid: 42))
        XCTAssertEqual(core.priorityMenuOffer(selfUid: 501), .restore)

        XCTAssertEqual(core.lowerSelectedPriority(selfUid: 501), [])
        XCTAssertTrue(core.isLoweredPriority(pid: 42))

        let restored = core.restoreLoweredPriority(pid: 42)
        XCTAssertEqual(restored, [.restorePriority(pid: 42)])
        XCTAssertFalse(core.isLoweredPriority(pid: 42))
        XCTAssertEqual(core.priorityMenuOffer(selfUid: 501), .lower)
        XCTAssertEqual(core.restoreLoweredPriority(pid: 42), [])
    }

    private func ready(_ row: ProcessRow) -> DashboardCore {
        var core = DashboardCore(ownPid: 1)
        accept(&core, rows: [row])
        _ = core.select(pid: row.pid)
        return core
    }

    private func eligible(
        _ pid: Int32,
        _ name: String,
        path: String? = "/usr/bin/ruby",
        userID: UInt32? = 501,
        start: UInt64? = 100,
        memory: UInt64 = 80,
        bundleIdentifier: String? = nil
    ) -> ProcessRow {
        ProcessRow(
            pid: pid,
            name: name,
            bundleIdentifier: bundleIdentifier,
            executablePath: path,
            cpuPercent: 1,
            memoryBytes: memory,
            threadCount: 1,
            userID: userID,
            startTimeSeconds: start
        )
    }

    @discardableResult
    private func accept(_ core: inout DashboardCore, rows: [ProcessRow]) -> [DashboardEffect] {
        let capturedAt = Date(timeIntervalSince1970: 1_700_000_000)
        let snapshot = MemorySnapshot(
            usedBytes: 8_000_000,
            totalBytes: 16_000_000,
            breakdown: MemoryBreakdown(appBytes: 1, wiredBytes: 1, compressedBytes: 1, cachedBytes: 1),
            pressure: .normal,
            pressureMetric: 0.1,
            pressureSeries: [],
            capturedAt: capturedAt,
            swapUsedBytes: 0
        )
        return core.apply(
            result: Result<SampledFrame, PriorityDeliveryError>.success(
                SampledFrame(
                    snapshot: snapshot,
                    rows: rows,
                    detail: nil,
                    processListFailed: false,
                    systemCpuPercent: 1,
                    hostNetworkRates: .missing,
                    hostDiskRates: .missing
                )
            ),
            accepted: true,
            page: core.selectedPage
        )
    }
}

private enum PriorityDeliveryError: Error {
    case unavailable
}
