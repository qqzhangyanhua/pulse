import XCTest
@testable import SamplingCore

/// Quit, energy-page selection, Top App locate, and Top3 tap on `DashboardCore`.
/// Action results are inputs. These tests do not call `ProcessActions`.
final class DashboardCoreQuitTests: XCTestCase {
    func testQuitSuccessDropsTheProcessOnTheNextSample() {
        var core = DashboardCore(ownPid: 1)
        accept(&core, rows: [row(7, "Mail", memory: 80), row(8, "Notes", memory: 40)])
        _ = core.select(pid: 7)

        let effects = core.quitSelected()
        guard case .terminate(let pid, let force, let token) = effects.first else {
            return XCTFail("expected a terminate effect, got \(effects)")
        }
        XCTAssertEqual(effects.count, 1)
        XCTAssertEqual(pid, 7)
        XCTAssertFalse(force)
        let issued = tryUnwrap(token)

        core.finishQuit(pid: pid, token: issued, result: .exited, taskCancelled: false)
        XCTAssertEqual(core.selectedPid, 7)
        XCTAssertEqual(core.quitOutcome.record(for: 7)?.opportunity, .closed)
        XCTAssertEqual(core.rows.map(\.pid), [7, 8])

        let followed = accept(&core, rows: [row(8, "Notes", memory: 40)])
        XCTAssertEqual(core.rows.map(\.pid), [8])
        XCTAssertNil(core.selectedPid)
        XCTAssertFalse(core.rows.contains { $0.pid == 7 })
        XCTAssertEqual(core.quitOutcome.record(for: 7)?.presence, .absentAndUnknown)
        XCTAssertTrue(followed.contains(.forwardSelectedPid(nil)))
        XCTAssertFalse(followed.contains(.terminate(pid: 7, force: false, token: issued)))
    }

    func testQuitFailureKeepsTheProcessAndShowsTheFailureCard() {
        var core = DashboardCore(ownPid: 1)
        accept(&core, rows: [row(7, "Mail", memory: 80)])
        _ = core.select(pid: 7)
        let effects = core.quitSelected()
        guard case .terminate(let pid, let force, let token) = effects.first else {
            return XCTFail("expected a terminate effect, got \(effects)")
        }
        XCTAssertFalse(force)
        core.finishQuit(pid: pid, token: tryUnwrap(token), result: .requestFailed, taskCancelled: false)

        let side = sidebar(core)
        XCTAssertTrue(side.showsFailureCard)
        XCTAssertEqual(side.quitPhase, .failed)
        XCTAssertEqual(side.quitMessage, ProcessQuitSessionCopy.terminateFailed)
        XCTAssertEqual(core.selectedPid, 7)
        XCTAssertEqual(core.rows.map(\.pid), [7])
        XCTAssertEqual(core.quitOutcome.record(for: 7)?.phase, .failed)
        XCTAssertEqual(core.quitOutcome.record(for: 7)?.opportunity, .open)
    }

    func testSampleDuringQuitDoesNotFinishTheAttempt() {
        var core = DashboardCore(ownPid: 1)
        accept(&core, rows: [row(7, "Mail", memory: 80)])
        _ = core.select(pid: 7)
        let effects = core.quitSelected()
        guard case .terminate(let pid, _, let token) = effects.first else {
            return XCTFail("expected a terminate effect, got \(effects)")
        }
        let issued = tryUnwrap(token)

        let stale = accept(&core, rows: [row(9, "Other", memory: 10)], accepted: false)
        XCTAssertEqual(core.rows.map(\.pid), [7])
        XCTAssertEqual(core.selectedPid, 7)
        XCTAssertEqual(core.quitOutcome.record(for: pid)?.phase, .quitting)
        XCTAssertEqual(core.quitOutcome.record(for: pid)?.opportunity, .open)
        XCTAssertEqual(core.quitOutcome.record(for: pid)?.presence, .inRows)
        XCTAssertEqual(core.quitOutcome.record(for: pid)?.token, issued)
        XCTAssertFalse(stale.contains { if case .terminate = $0 { return true }; return false })

        let live = accept(&core, rows: [row(7, "Mail", memory: 90)])
        XCTAssertEqual(core.selectedPid, 7)
        XCTAssertEqual(core.rows.map(\.pid), [7])
        XCTAssertEqual(core.quitOutcome.record(for: pid)?.phase, .quitting)
        XCTAssertEqual(core.quitOutcome.record(for: pid)?.opportunity, .open)
        XCTAssertEqual(core.quitOutcome.record(for: pid)?.token, issued)
        XCTAssertEqual(sidebar(core).quitPhase, .quitting)
        XCTAssertFalse(live.contains { if case .terminate = $0 { return true }; return false })
    }

    func testForceQuitCancelDoesNotTerminate() {
        var core = readyMail()
        let effects = core.beginForceQuit()
        guard case .confirmForceQuit(let name, let generation) = effects.first else {
            return XCTFail("expected a confirm effect, got \(effects)")
        }
        XCTAssertEqual(effects.count, 1)
        XCTAssertEqual(name, "Mail")
        XCTAssertFalse(effects.contains { if case .terminate = $0 { return true }; return false })

        let cancelled = core.resolveForceQuit(generation: generation, confirmed: false)
        XCTAssertEqual(cancelled, [])
        XCTAssertNil(core.quitOutcome.pendingForceConfirmation)
        XCTAssertNil(core.quitOutcome.record(for: 7))
        XCTAssertEqual(core.selectedPid, 7)
    }

    func testForceQuitConfirmTerminates() {
        var core = readyMail()
        let effects = core.beginForceQuit()
        guard case .confirmForceQuit(_, let generation) = effects.first else {
            return XCTFail("expected a confirm effect, got \(effects)")
        }
        let confirmed = core.resolveForceQuit(generation: generation, confirmed: true)
        guard case .terminate(let pid, let force, let token) = confirmed.first else {
            return XCTFail("expected a terminate effect, got \(confirmed)")
        }
        XCTAssertEqual(confirmed.count, 1)
        XCTAssertEqual(pid, 7)
        XCTAssertTrue(force)
        XCTAssertNotNil(token)
        XCTAssertEqual(core.quitOutcome.record(for: 7)?.phase, .quitting)
        XCTAssertNil(core.quitOutcome.pendingForceConfirmation)
    }

    func testExitedEnergySelectionCannotQuit() {
        var core = DashboardCore(ownPid: 1)
        _ = core.selectPage(.energy)
        accept(&core, rows: [row(4, "Mail", memory: 80)], generations: [4: 3])
        _ = core.select(pid: 4)
        XCTAssertEqual(core.selectedEnergyGeneration, 3)

        let kept = accept(
            &core,
            rows: [row(8, "Notes", memory: 20)],
            generations: [8: 1],
            exited: [ExitedEnergyProcess(pid: 4, generation: 3, name: "Mail", rates: ProcessEnergyRates(watts: 1.5, wakeupsPerSecond: 0.2))]
        )
        XCTAssertEqual(core.selectedPid, 4)
        XCTAssertEqual(core.selectedEnergyGeneration, 3)
        XCTAssertTrue(core.selectedEnergyExitedOnly)
        XCTAssertFalse(kept.contains { if case .forwardSelectedPid(nil) = $0 { return true }; return false })
        XCTAssertEqual(core.quitSelected(), [])
        XCTAssertEqual(core.beginForceQuit(), [])
        XCTAssertNil(core.quitOutcome.record(for: 4))
        XCTAssertNil(core.quitOutcome.pendingForceConfirmation)
    }

    func testMismatchedEnergyGenerationCannotQuit() {
        var core = DashboardCore(ownPid: 1)
        _ = core.selectPage(.energy)
        accept(&core, rows: [row(4, "Mail", memory: 80)], generations: [4: 9])
        _ = core.select(pid: 4)
        core.selectedEnergyGeneration = 1

        XCTAssertTrue(core.selectedEnergyExitedOnly)
        XCTAssertEqual(core.selectedPid, 4)
        XCTAssertEqual(core.quitSelected(), [])
        XCTAssertEqual(core.beginForceQuit(), [])
        XCTAssertNil(core.quitOutcome.record(for: 4))
        XCTAssertNil(core.quitOutcome.pendingForceConfirmation)
    }

    func testReusedEnergyGenerationClearsTheSelection() {
        var core = DashboardCore(ownPid: 1)
        _ = core.selectPage(.energy)
        accept(&core, rows: [row(4, "Mail", memory: 80)], generations: [4: 1])
        _ = core.select(pid: 4)

        _ = accept(&core, rows: [row(4, "Mail", memory: 70)], generations: [4: 2])
        XCTAssertNil(core.selectedPid)
        XCTAssertNil(core.selectedEnergyGeneration)
        XCTAssertFalse(core.selectedEnergyExitedOnly)
        XCTAssertEqual(core.quitSelected(), [])
    }

    func testLocatingTheTopAppClearsFiltersThatHideIt() {
        var core = DashboardCore(ownPid: 1)
        accept(&core, rows: [row(4, "Mail", memory: 200), row(8, "Notes", memory: 40)])
        _ = core.setFilter("Notes")
        _ = core.setRisingOnly(true)
        _ = core.setWindowedOnly(true, windowedPids: [8])
        _ = core.select(pid: 8)
        XCTAssertFalse(core.visibleRows.contains { $0.pid == 4 })

        let effects = core.locateMemoryTopApp(name: "Mail", pid: 4)
        XCTAssertEqual(core.filter, "Mail")
        XCTAssertFalse(core.risingOnlyFilter)
        XCTAssertFalse(core.windowedOnlyFilter)
        XCTAssertTrue(core.groupedByApp == false)
        XCTAssertEqual(core.selectedPid, 4)
        XCTAssertEqual(core.topAppLocateReveal, TopAppLocation.Reveal(pid: 4, generation: 1))
        XCTAssertTrue(core.visibleRows.contains { $0.pid == 4 })
        XCTAssertTrue(effects.contains(.forwardSelectedPid(4)))

        let hidden = core.filter
        _ = core.selectPage(.cpu)
        let ignored = core.locateMemoryTopApp(name: "Mail", pid: 4)
        XCTAssertEqual(ignored, [])
        XCTAssertEqual(core.filter, hidden)
        XCTAssertEqual(core.topAppLocateReveal?.generation, 1)
        XCTAssertEqual(core.selectedPid, 4)
    }

    func testTop3TapKeepsTheTappedPidSelected() {
        var core = DashboardCore(ownPid: 1)
        accept(&core, rows: [row(4, "Notes", memory: 100), row(9, "Mail", memory: 50)])
        _ = core.setRisingOnly(true)
        _ = core.setWindowedOnly(true, windowedPids: [9])
        _ = core.setFilter("Mail")
        XCTAssertNil(core.selectedPid)

        let host = DashboardCoreTapHost(core)
        let schedule = Top3ProcessTap.perform(pid: 4, host: host, dismiss: {}, activate: {})
        XCTAssertEqual(host.core.selectedPid, 4)
        XCTAssertEqual(host.core.selectedPage, .memory)
        XCTAssertEqual(host.core.filter, "")
        XCTAssertFalse(host.core.risingOnlyFilter)
        XCTAssertFalse(host.core.windowedOnlyFilter)
        XCTAssertEqual(schedule.pageSwitches, 1)
        XCTAssertEqual(schedule.activations, 1)
        XCTAssertEqual(schedule.openPulseCalls, 0)
    }

    private func readyMail() -> DashboardCore {
        var core = DashboardCore(ownPid: 1)
        accept(&core, rows: [row(7, "Mail", memory: 80)])
        _ = core.select(pid: 7)
        return core
    }

    private func sidebar(_ core: DashboardCore) -> ProcessQuitSession.Sidebar {
        ProcessQuitSession.sidebar(
            core.quitOutcome,
            ProcessQuitSession.Context(
                listSelectedPid: core.selectedPid,
                sidebarSubjectPid: core.sidebarSubjectPid,
                rows: core.rows,
                liveDetail: core.detail
            )
        )
    }

    private func tryUnwrap<T>(_ value: T?) -> T {
        guard let value else {
            XCTFail("missing value")
            preconditionFailure("missing value")
        }
        return value
    }

    @discardableResult
    private func accept(
        _ core: inout DashboardCore,
        rows: [ProcessRow],
        accepted: Bool = true,
        generations: [Int32: Int] = [:],
        exited: [ExitedEnergyProcess] = []
    ) -> [DashboardEffect] {
        core.apply(
            result: Result<SampledFrame, QuitDeliveryError>.success(
                frame(rows: rows, generations: generations, exited: exited)
            ),
            accepted: accepted,
            page: core.selectedPage,

        )
    }

    private func frame(
        rows: [ProcessRow],
        generations: [Int32: Int],
        exited: [ExitedEnergyProcess]
    ) -> SampledFrame {
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
        return SampledFrame(
            snapshot: snapshot,
            rows: rows,
            detail: nil,
            processListFailed: false,
            systemCpuPercent: 1,
            hostNetworkRates: .missing,
            hostDiskRates: .missing,
            exitedEnergyProcesses: exited,
            energyLiveGenerations: generations
        )
    }

    private func row(_ pid: Int32, _ name: String, memory: UInt64) -> ProcessRow {
        ProcessRow(
            pid: pid,
            name: name,
            bundleIdentifier: nil,
            executablePath: nil,
            cpuPercent: 1,
            memoryBytes: memory,
            threadCount: 1
        )
    }
}

private enum QuitDeliveryError: Error {
    case unavailable
}

private final class DashboardCoreTapHost: Top3TapHost {
    var core: DashboardCore

    init(_ core: DashboardCore) {
        self.core = core
    }

    var selectedPid: Int32? {
        get { core.selectedPid }
        set { _ = core.select(pid: newValue) }
    }

    var rows: [ProcessRow] { core.rows }
    var filter: String {
        get { core.filter }
        set { _ = core.setFilter(newValue) }
    }
    var risingOnlyFilter: Bool {
        get { core.risingOnlyFilter }
        set { _ = core.setRisingOnly(newValue) }
    }
    var windowedOnlyFilter: Bool {
        get { core.windowedOnlyFilter }
        set { _ = core.setWindowedOnly(newValue, windowedPids: core.windowedPids) }
    }
    var groupedByApp: Bool { core.groupedByApp }
    var navigation: DashboardNavigation { core.navigation }
    var topMemorySeries: [Int32: [ChartSample]] { core.topMemorySeries }
    var windowedPids: Set<Int32> { core.windowedPids }

    func selectPidIfPresent(_ pid: Int32) {
        guard let accepted = ProcessSelection.acceptedPid(pid, in: core.rows) else { return }
        _ = core.select(pid: accepted)
    }

    func focusMemoryPage() {
        _ = core.focusMemoryPage()
    }
}
