import XCTest
@testable import SamplingCore

/// Pause marks and the resume-before-quit decision. No signals and no alerts.
final class DashboardCorePauseTests: XCTestCase {
    func testOwnUserNonSystemProcessOffersPause() {
        let core = ready(pausable(42, "Mail", path: "/Applications/Mail.app/Contents/MacOS/Mail", bundleIdentifier: "com.apple.mail"))
        XCTAssertEqual(core.pauseMenuOffer(selfUid: 501), .pause)
        XCTAssertEqual(PauseMenuOffer.pause.title, "暂停")
        XCTAssertEqual(PauseMenuOffer.resume.title, "继续")
    }

    func testIneligibleRowsDoNotOfferPause() {
        let eligible = pausable(42, "Mail")
        XCTAssertNil(ready(eligible, userID: 0).pauseMenuOffer(selfUid: 501))
        XCTAssertNil(ready(eligible, userID: nil).pauseMenuOffer(selfUid: 501))
        XCTAssertNil(ready(pausable(42, "Mail", start: nil)).pauseMenuOffer(selfUid: 501))
        XCTAssertNil(ready(pausable(42, "Mail", path: nil)).pauseMenuOffer(selfUid: 501))
        XCTAssertNil(ready(pausable(42, "Mail", path: "")).pauseMenuOffer(selfUid: 501))
        for path in [
            "/System/Library/CoreServices/Finder.app/Contents/MacOS/Finder",
            "/usr/libexec/runningboardd",
            "/usr/sbin/syslogd",
            "/sbin/launchd",
            "/Systematic/tool",
            "/usr/libexecfoo",
        ] {
            let row = pausable(42, "Finder", path: path, bundleIdentifier: "com.apple.finder")
            XCTAssertNil(ready(row).pauseMenuOffer(selfUid: 501), path)
        }
        for path in ["/usr/bin/ruby", "/usr/lib/dyld", "/opt/homebrew/bin/node", "/Users/me/bin/tool"] {
            XCTAssertEqual(ready(pausable(42, "tool", path: path)).pauseMenuOffer(selfUid: 501), .pause, path)
        }
    }

    func testGroupedVisibleRowDoesNotOfferPause() {
        var core = DashboardCore(ownPid: 1)
        accept(&core, rows: [
            pausable(4, "Mail", memory: 200),
            pausable(9, "Mail", memory: 50),
        ])
        _ = core.setGroupedByApp(true)
        _ = core.select(pid: 4)
        XCTAssertEqual(core.selectedRow?.groupedMemberCount, 2)
        XCTAssertNil(core.rows.first { $0.pid == 4 }?.groupedMemberCount)
        XCTAssertNil(core.pauseMenuOffer(selfUid: 501))
        XCTAssertEqual(core.pauseSelected(selfUid: 501), [])
        XCTAssertTrue(core.pausedLedger.records.isEmpty)
    }

    func testPauseRecordsTheProcessAndResumeDropsIt() {
        var core = ready(pausable(42, "Mail", start: 100))
        let paused = core.pauseSelected(selfUid: 501)
        XCTAssertEqual(paused, [.pauseProcess(pid: 42)])
        XCTAssertEqual(core.pausedLedger.records, [PausedProcessRecord(pid: 42, startTimeSeconds: 100)])
        XCTAssertTrue(core.isPaused(pid: 42))
        XCTAssertEqual(core.pauseMenuOffer(selfUid: 501), .resume)

        let resumed = core.resumePaused(pid: 42)
        XCTAssertEqual(resumed, [.resumeProcess(pid: 42)])
        XCTAssertFalse(core.isPaused(pid: 42))
        XCTAssertTrue(core.pausedLedger.records.isEmpty)
        XCTAssertEqual(core.pauseMenuOffer(selfUid: 501), .pause)
        XCTAssertEqual(core.resumePaused(pid: 42), [])
    }

    func testReusedPidDoesNotShowThePausedMark() {
        var core = ready(pausable(42, "Mail", start: 100))
        _ = core.pauseSelected(selfUid: 501)
        accept(&core, rows: [pausable(42, "Mail", start: 999)])
        _ = core.select(pid: 42)
        XCTAssertFalse(core.isPaused(pid: 42))
        XCTAssertEqual(core.pauseMenuOffer(selfUid: 501), .pause)
    }

    func testUnpausedQuitStillTerminates() {
        var core = ready(pausable(42, "Mail"))
        let effects = core.quitSelected()
        guard case .terminate(let pid, let force, _) = effects.first else {
            return XCTFail("expected terminate, got \(effects)")
        }
        XCTAssertEqual(effects.count, 1)
        XCTAssertEqual(pid, 42)
        XCTAssertFalse(force)
    }

    func testQuitOfPausedProcessAsksToResumeFirst() {
        var core = ready(pausable(42, "Mail", start: 100))
        _ = core.pauseSelected(selfUid: 501)

        let prompt = core.quitSelected()
        XCTAssertEqual(prompt, [.confirmResumeBeforeQuit(pid: 42, displayName: "Mail")])
        XCTAssertNil(core.quitOutcome.record(for: 42))

        let cancelled = core.resolveResumeBeforeQuit(pid: 42, confirmed: false)
        XCTAssertEqual(cancelled, [])
        XCTAssertTrue(core.isPaused(pid: 42))
        XCTAssertNil(core.quitOutcome.record(for: 42))

        let ignored = core.resolveResumeBeforeQuit(pid: 99, confirmed: true)
        XCTAssertEqual(ignored, [])
        XCTAssertTrue(core.isPaused(pid: 42))

        let confirmed = core.resolveResumeBeforeQuit(pid: 42, confirmed: true)
        XCTAssertEqual(confirmed.first, .resumeProcess(pid: 42))
        guard confirmed.count == 2, case .terminate(let pid, let force, let token) = confirmed[1] else {
            return XCTFail("expected resume then terminate, got \(confirmed)")
        }
        XCTAssertEqual(pid, 42)
        XCTAssertFalse(force)
        XCTAssertNotNil(token)
        XCTAssertFalse(core.isPaused(pid: 42))
        XCTAssertTrue(core.pausedLedger.records.isEmpty)
        XCTAssertEqual(core.quitOutcome.record(for: 42)?.phase, .quitting)
    }

    func testPausedThermalOrGPUQuitAsksToContinueFirst() {
        var core = ready(pausable(42, "Mail", start: 100))
        XCTAssertEqual(core.pauseSelected(selfUid: 501), [.pauseProcess(pid: 42)])
        XCTAssertEqual(
            core.beginThermalTerminate(pid: 42),
            [.confirmResumeBeforeQuit(pid: 42, displayName: "Mail")]
        )
        XCTAssertEqual(core.resolveResumeBeforeQuit(pid: 42, confirmed: false), [])
        XCTAssertTrue(core.isPaused(pid: 42))
        XCTAssertNil(core.quitOutcome.record(for: 42))

        _ = core.selectPage(.gpu)
        XCTAssertEqual(
            core.beginThermalTerminate(pid: 42),
            [.confirmResumeBeforeQuit(pid: 42, displayName: "Mail")]
        )
        let confirmed = core.resolveResumeBeforeQuit(pid: 42, confirmed: true)
        XCTAssertEqual(confirmed.count, 2)
        XCTAssertEqual(confirmed.first, .resumeProcess(pid: 42))
        guard case .terminate(let pid, false, let token) = confirmed[1] else {
            return XCTFail("expected resume then terminate, got \(confirmed)")
        }
        XCTAssertEqual(pid, 42)
        XCTAssertNil(token)
        XCTAssertFalse(core.isPaused(pid: 42))
        XCTAssertTrue(core.pausedLedger.records.isEmpty)
    }

    func testUnpausedThermalRowTerminatesWithoutResumePrompt() {
        var core = ready(pausable(42, "Mail"))
        _ = core.selectPage(.gpu)
        let effects = core.beginThermalTerminate(pid: 42)
        XCTAssertEqual(effects.count, 1)
        guard case .terminate(let pid, false, nil) = effects[0] else {
            return XCTFail("expected terminate, got \(effects)")
        }
        XCTAssertEqual(pid, 42)
    }

    private func ready(_ row: ProcessRow) -> DashboardCore {
        var core = DashboardCore(ownPid: 1)
        accept(&core, rows: [row])
        _ = core.select(pid: row.pid)
        return core
    }

    private func ready(_ row: ProcessRow, userID: UInt32?) -> DashboardCore {
        ready(pausable(row.pid, row.name, path: row.executablePath, userID: userID, start: row.startTimeSeconds))
    }

    private func pausable(
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
            result: Result<SampledFrame, PauseDeliveryError>.success(
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

private enum PauseDeliveryError: Error {
    case unavailable
}
