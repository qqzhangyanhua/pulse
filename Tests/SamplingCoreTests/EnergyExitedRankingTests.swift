import XCTest
@testable import SamplingCore

/// 1-hour ranking keeps an exited generation until its last present minute ages out.
/// The 1-minute window is still `ProcessEnergyWindow` and is not covered here.
final class EnergyExitedRankingTests: XCTestCase {
    private let origin = Date(timeIntervalSince1970: 1_700_000_040)

    func testLeavingTheListKeepsTheSameWattsAsAnExitedProcess() {
        var ledger = ProcessEnergyMinuteLedger()
        _ = push(&ledger, energy: 0, wakeups: 0, at: 0, name: "Mail")
        _ = push(&ledger, energy: 10_000_000_000, wakeups: 10, at: 10, name: "Mail")
        let gone = ledger.advance(
            listed: [:],
            names: [:],
            now: origin.addingTimeInterval(15),
            listSucceeded: true
        )
        XCTAssertTrue(gone.isEmpty)
        let exited = ledger.exitedProcesses
        XCTAssertEqual(exited.count, 1)
        XCTAssertEqual(exited[0].pid, 7)
        XCTAssertEqual(exited[0].name, "Mail")
        XCTAssertEqual(exited[0].rates.watts ?? -1, 1, accuracy: 1e-9)
        XCTAssertEqual(exited[0].rates.wakeupsPerSecond ?? -1, 1, accuracy: 1e-9)
        XCTAssertNotEqual(exited[0].rates.watts ?? -1, 0)
        XCTAssertNotEqual(ProcessEnergyText.watts(exited[0].rates.watts), "—")
    }

    func testExitedProcessIsGoneOneSecondPastTheHourAndIsNotZero() {
        var ledger = ProcessEnergyMinuteLedger()
        _ = push(&ledger, energy: 0, wakeups: 0, at: 0, name: "Mail")
        _ = push(&ledger, energy: 10_000_000_000, wakeups: 10, at: 10, name: "Mail")
        _ = ledger.advance(listed: [:], now: origin.addingTimeInterval(15), listSucceeded: true)
        _ = ledger.advance(listed: [:], now: origin.addingTimeInterval(3_600), listSucceeded: true)
        XCTAssertEqual(ledger.exitedProcesses.count, 1)
        XCTAssertEqual(ledger.exitedProcesses[0].rates.watts ?? -1, 1, accuracy: 1e-9)
        _ = ledger.advance(listed: [:], now: origin.addingTimeInterval(3_601), listSucceeded: true)
        XCTAssertTrue(ledger.exitedProcesses.isEmpty)
        XCTAssertNil(ledger.exitedProcesses.first?.rates.watts)
        XCTAssertNotEqual(ledger.exitedProcesses.first?.rates.watts ?? -1, 0)
    }

    func testPidReuseDoesNotMergeOldNanojoulesIntoTheNewLiveRate() {
        var ledger = ProcessEnergyMinuteLedger()
        _ = push(&ledger, energy: 0, wakeups: 0, at: 0, name: "Mail")
        _ = push(&ledger, energy: 10_000_000_000, wakeups: 10, at: 10, name: "Mail")
        let gone = ledger.advance(listed: [:], now: origin.addingTimeInterval(15), listSucceeded: true)
        XCTAssertTrue(gone.isEmpty)
        let sealed = ledger.exitedProcesses
        XCTAssertEqual(sealed.count, 1)
        let oldGeneration = sealed[0].generation
        let returned = push(&ledger, energy: 50_000_000_000, wakeups: 50, at: 20, name: "Mail")
        XCTAssertNil(returned?.watts)
        XCTAssertNil(returned?.wakeupsPerSecond)
        XCTAssertEqual(ledger.exitedProcesses.map(\.generation), [oldGeneration])
        XCTAssertEqual(ledger.exitedProcesses[0].rates.watts ?? -1, 1, accuracy: 1e-9)
        let live = push(&ledger, energy: 70_000_000_000, wakeups: 70, at: 30, name: "Mail")
        XCTAssertEqual(live?.watts ?? -1, 2, accuracy: 1e-9)
        XCTAssertEqual(live?.wakeupsPerSecond ?? -1, 2, accuracy: 1e-9)
        XCTAssertNotEqual(live?.watts ?? -1, 1.5)
        XCTAssertNotEqual(live?.watts ?? -1, 3)
        XCTAssertEqual(ledger.exitedProcesses.count, 1)
        XCTAssertEqual(ledger.exitedProcesses[0].generation, oldGeneration)
        XCTAssertEqual(ledger.exitedProcesses[0].rates.watts ?? -1, 1, accuracy: 1e-9)
    }

    func testCounterDecreaseWhileListedSplitsTheGeneration() {
        var ledger = ProcessEnergyMinuteLedger()
        _ = push(&ledger, energy: 0, wakeups: 0, at: 0, name: "Mail")
        _ = push(&ledger, energy: 10_000_000_000, wakeups: 10, at: 10, name: "Mail")
        let dropped = push(&ledger, energy: 1, wakeups: 1, at: 20, name: "Mail")
        XCTAssertNil(dropped?.watts)
        XCTAssertEqual(ledger.exitedProcesses.count, 1)
        XCTAssertEqual(ledger.exitedProcesses[0].name, "Mail")
        XCTAssertEqual(ledger.exitedProcesses[0].rates.watts ?? -1, 1, accuracy: 1e-9)
        let oldGeneration = ledger.exitedProcesses[0].generation
        let live = push(&ledger, energy: 30_000_000_001, wakeups: 31, at: 30, name: "Mail")
        XCTAssertEqual(live?.watts ?? -1, 3, accuracy: 1e-9)
        XCTAssertNotEqual(live?.watts ?? -1, 2)
        XCTAssertEqual(ledger.exitedProcesses.count, 1)
        XCTAssertEqual(ledger.exitedProcesses[0].generation, oldGeneration)
        XCTAssertEqual(ledger.exitedProcesses[0].rates.watts ?? -1, 1, accuracy: 1e-9)
    }

    func testResetWithNoPresentBucketCreatesNoExitedRow() {
        var ledger = ProcessEnergyMinuteLedger()
        _ = push(&ledger, energy: 5, wakeups: 5, at: 0, name: "Mail")
        let reset = push(&ledger, energy: 1, wakeups: 1, at: 10, name: "Mail")
        XCTAssertNil(reset?.watts)
        XCTAssertTrue(ledger.exitedProcesses.isEmpty)
        XCTAssertNotEqual(reset?.watts ?? -1, 0)
    }

    func testMissingNameIsTheDecimalPid() {
        var ledger = ProcessEnergyMinuteLedger()
        _ = push(&ledger, energy: 0, wakeups: 0, at: 0, name: "   ")
        _ = push(&ledger, energy: 10_000_000_000, wakeups: 10, at: 10, name: "")
        _ = ledger.advance(listed: [:], now: origin.addingTimeInterval(15), listSucceeded: true)
        XCTAssertEqual(ledger.exitedProcesses.map(\.name), ["7"])
    }

    func testOneMinuteRankingOmitsExitedProcesses() {
        let exited = ExitedEnergyProcess(
            pid: 7,
            generation: 1,
            name: "Mail",
            rates: ProcessEnergyRates(watts: 1, wakeupsPerSecond: 1)
        )
        let rows = ranked(span: .oneMinute, rows: [row(4, "Safari", memory: 10)], exited: [exited], grouped: false)
        XCTAssertEqual(rows.map(\.pid), [4])
        XCTAssertFalse(rows.contains { $0.exited })
        XCTAssertFalse(rows.contains { $0.name == "Mail" })
    }

    func testOneHourRankingShowsExitedBesideLiveAndDoesNotFoldItIntoTheAppGroup() throws {
        let exited = ExitedEnergyProcess(
            pid: 30,
            generation: 2,
            name: "Mail",
            rates: ProcessEnergyRates(watts: 1, wakeupsPerSecond: 4)
        )
        let live = [
            row(20, "Mail", memory: 200),
            row(10, "Mail", memory: 100),
        ]
        let rates: [Int32: ProcessEnergyRates] = [
            20: ProcessEnergyRates(watts: 0.2, wakeupsPerSecond: 0.4),
            10: .missing,
        ]
        let hour = ranked(
            span: .oneHour,
            rows: live,
            rates: rates,
            exited: [exited],
            grouped: true,
            sort: ProcessTableSort(column: .energy, descending: true)
        )
        XCTAssertEqual(Set(hour.map(\.id)).count, hour.count)
        let group = try XCTUnwrap(hour.first { $0.pid == 20 && !$0.exited })
        XCTAssertEqual(group.rates.watts ?? -1, 0.2, accuracy: 1e-9)
        XCTAssertTrue(group.energyReadingIsPartial)
        XCTAssertTrue(group.isQuitTarget)
        XCTAssertFalse(group.exited)
        let sealed = try XCTUnwrap(hour.first { $0.exited })
        XCTAssertEqual(sealed.pid, 30)
        XCTAssertEqual(sealed.generation, 2)
        XCTAssertEqual(sealed.id, "exited-30-2")
        XCTAssertNotEqual(sealed.id, "live-30")
        XCTAssertEqual(sealed.rates.watts ?? -1, 1, accuracy: 1e-9)
        XCTAssertFalse(sealed.energyReadingIsPartial)
        XCTAssertFalse(sealed.isQuitTarget)
        XCTAssertEqual(EnergyPage.exitedStatus, "已退出")
        XCTAssertNotEqual(group.rates.watts ?? -1, 1.2)
        XCTAssertEqual(hour.map(\.pid), [30, 20])
    }

    func testReusedPidKeepsASeparateExitedIdentityAndDoesNotJoinTheLiveSum() throws {
        let exited = ExitedEnergyProcess(
            pid: 7,
            generation: 1,
            name: "Mail",
            rates: ProcessEnergyRates(watts: 1, wakeupsPerSecond: 1)
        )
        let hour = ranked(
            span: .oneHour,
            rows: [row(7, "Mail", memory: 50)],
            rates: [7: ProcessEnergyRates(watts: 0.2, wakeupsPerSecond: 0.2)],
            exited: [exited],
            grouped: true
        )
        XCTAssertEqual(hour.count, 2)
        XCTAssertEqual(Set(hour.map(\.id)).count, 2)
        let live = try XCTUnwrap(hour.first { !$0.exited })
        let sealed = try XCTUnwrap(hour.first { $0.exited })
        XCTAssertEqual(live.pid, sealed.pid)
        XCTAssertNotEqual(live.id, sealed.id)
        XCTAssertEqual(live.rates.watts ?? -1, 0.2, accuracy: 1e-9)
        XCTAssertEqual(sealed.rates.watts ?? -1, 1, accuracy: 1e-9)
        XCTAssertNotEqual(live.rates.watts ?? -1, 1.2)
        XCTAssertTrue(live.isQuitTarget)
        XCTAssertFalse(sealed.isQuitTarget)
    }

    func testReusedPidDoesNotKeepTheSelectedGeneration() {
        let exited = ExitedEnergyProcess(
            pid: 7,
            generation: 1,
            name: "Mail",
            rates: ProcessEnergyRates(watts: 1, wakeupsPerSecond: 1)
        )
        let liveRows = [row(7, "Mail", memory: 50)]
        let reused: [Int32: Int] = [7: 2]
        XCTAssertTrue(
            blocksQuit(pid: 7, generation: 1, liveRows: liveRows, liveGenerations: reused, exited: [exited])
        )
        XCTAssertFalse(
            blocksQuit(pid: 7, generation: nil, liveRows: liveRows, liveGenerations: reused, exited: [exited])
        )
        XCTAssertFalse(
            blocksQuit(pid: 7, generation: 2, liveRows: liveRows, liveGenerations: reused, exited: [exited])
        )
        XCTAssertTrue(blocksQuit(pid: 7, generation: 1, liveRows: [], liveGenerations: [7: 1], exited: [exited]))
        XCTAssertFalse(blocksQuit(pid: nil, generation: nil, liveRows: [], liveGenerations: [:], exited: [exited]))
        XCTAssertFalse(blocksQuit(pid: 9, generation: nil, liveRows: [], liveGenerations: [:], exited: [exited]))

        let cleared = resolve(onEnergyPage: true, pid: 7, generation: 1, liveRows: liveRows, liveGenerations: reused)
        XCTAssertNil(cleared.pid)
        XCTAssertNil(cleared.generation)
        let bound = resolve(onEnergyPage: true, pid: 7, generation: nil, liveRows: liveRows, liveGenerations: reused)
        XCTAssertEqual(bound.pid, 7)
        XCTAssertEqual(bound.generation, 2)
        let kept = resolve(onEnergyPage: true, pid: 7, generation: 1, liveRows: [], liveGenerations: [7: 1])
        XCTAssertEqual(kept.pid, 7)
        XCTAssertEqual(kept.generation, 1)
        let same = resolve(onEnergyPage: true, pid: 7, generation: 2, liveRows: liveRows, liveGenerations: reused)
        XCTAssertEqual(same.pid, 7)
        XCTAssertEqual(same.generation, 2)
        let away = resolve(onEnergyPage: false, pid: 7, generation: 1, liveRows: liveRows, liveGenerations: reused)
        XCTAssertEqual(away.pid, 7)
        XCTAssertEqual(away.generation, 1)
    }

    func testLiveGenerationStaysAfterExitAndIncreasesWhenThePidReturns() {
        var ledger = ProcessEnergyMinuteLedger()
        _ = push(&ledger, energy: 0, wakeups: 0, at: 0, name: "Mail")
        XCTAssertEqual(ledger.liveGenerations[7], 1)
        _ = push(&ledger, energy: 10_000_000_000, wakeups: 10, at: 10, name: "Mail")
        _ = ledger.advance(listed: [:], now: origin.addingTimeInterval(15), listSucceeded: true)
        XCTAssertEqual(ledger.exitedProcesses.map(\.generation), [1])
        XCTAssertEqual(ledger.liveGenerations[7], 1)
        _ = push(&ledger, energy: 50_000_000_000, wakeups: 50, at: 20, name: "Mail")
        XCTAssertEqual(ledger.liveGenerations[7], 2)
        XCTAssertEqual(ledger.exitedProcesses.map(\.generation), [1])
    }

    func testExitedRowsMatchTheNameFilterAndNilRatesSortLast() {
        let exited = [
            ExitedEnergyProcess(pid: 3, generation: 1, name: "Mail", rates: ProcessEnergyRates(watts: 1, wakeupsPerSecond: 1)),
            ExitedEnergyProcess(pid: 8, generation: 1, name: "Safari", rates: .missing),
        ]
        let matched = ranked(
            span: .oneHour,
            rows: [row(4, "Notes", memory: 1)],
            rates: [4: .missing],
            exited: exited,
            nameQuery: "  MAI ",
            grouped: false,
            sort: ProcessTableSort(column: .energy, descending: false)
        )
        XCTAssertEqual(matched.map(\.name), ["Mail"])
        XCTAssertFalse(matched.contains { $0.pid == 8 })
        let ordered = ranked(
            span: .oneHour,
            rows: [row(4, "Notes", memory: 1)],
            rates: [4: .missing],
            exited: [exited[0]],
            grouped: false,
            sort: ProcessTableSort(column: .energy, descending: false)
        )
        XCTAssertEqual(ordered.map(\.pid), [3, 4])
        let descending = ranked(
            span: .oneHour,
            rows: [row(4, "Notes", memory: 1)],
            rates: [4: .missing],
            exited: [exited[0]],
            grouped: false,
            sort: ProcessTableSort(column: .energy, descending: true)
        )
        XCTAssertEqual(descending.map(\.pid), [3, 4])
    }

    func testHourPhaseStillHasRowsWhenOnlyExitedProcessesRemain() {
        let hour = EnergyPage.phaseCounts(span: .oneHour, liveRowCount: 0, exitedCount: 1, rankedCount: 1)
        XCTAssertEqual(hour.processCount, 1)
        XCTAssertEqual(hour.visibleCount, 1)
        XCTAssertEqual(
            EnergyPage.phase(
                loadState: .ready,
                processCount: hour.processCount,
                visibleCount: hour.visibleCount,
                hasActiveNameFilter: false,
                processListFailed: false
            ),
            .ready
        )
        let minute = EnergyPage.phaseCounts(span: .oneMinute, liveRowCount: 0, exitedCount: 1, rankedCount: 0)
        XCTAssertEqual(minute.processCount, 0)
        XCTAssertEqual(minute.visibleCount, 0)
        XCTAssertEqual(
            EnergyPage.phase(
                loadState: .ready,
                processCount: minute.processCount,
                visibleCount: minute.visibleCount,
                hasActiveNameFilter: false,
                processListFailed: false
            ),
            .empty
        )
    }

    private func blocksQuit(
        pid: Int32?,
        generation: Int?,
        liveRows: [ProcessRow],
        liveGenerations: [Int32: Int],
        exited: [ExitedEnergyProcess]
    ) -> Bool {
        EnergyPage.blocksQuit(
            selectedPid: pid,
            rememberedGeneration: generation,
            liveRows: liveRows,
            liveGenerations: liveGenerations,
            exited: exited
        )
    }

    private func resolve(
        onEnergyPage: Bool,
        pid: Int32?,
        generation: Int?,
        liveRows: [ProcessRow],
        liveGenerations: [Int32: Int]
    ) -> EnergySelectionResolution {
        EnergyPage.resolvedSelection(
            onEnergyPage: onEnergyPage,
            selectedPid: pid,
            rememberedGeneration: generation,
            liveRows: liveRows,
            liveGenerations: liveGenerations
        )
    }

    private func ranked(
        span: EnergyRankingSpan,
        rows: [ProcessRow],
        rates: [Int32: ProcessEnergyRates] = [:],
        exited: [ExitedEnergyProcess],
        nameQuery: String = "",
        grouped: Bool,
        sort: ProcessTableSort = ProcessTableSort(column: .energy, descending: true)
    ) -> [EnergyRankRow] {
        EnergyPage.ranked(
            span: span,
            rows: rows,
            rates: rates,
            exited: exited,
            nameQuery: nameQuery,
            grouped: grouped,
            sort: sort
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

    private func tick(energy: UInt64, wakeups: UInt64, at seconds: TimeInterval) -> EnergyTick {
        EnergyTick(
            energyNanojoules: energy,
            interruptWakeups: wakeups,
            date: origin.addingTimeInterval(seconds)
        )
    }

    @discardableResult
    private func push(
        _ ledger: inout ProcessEnergyMinuteLedger,
        pid: Int32 = 7,
        energy: UInt64,
        wakeups: UInt64,
        at seconds: TimeInterval,
        now: TimeInterval? = nil,
        name: String? = nil
    ) -> ProcessEnergyRates? {
        var names: [Int32: String] = [:]
        if let name { names[pid] = name }
        return ledger.advance(
            listed: [pid: tick(energy: energy, wakeups: wakeups, at: seconds)],
            names: names,
            now: origin.addingTimeInterval(now ?? seconds),
            listSucceeded: true
        )[pid]
    }
}
