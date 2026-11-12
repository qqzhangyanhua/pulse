import XCTest
@testable import SamplingCore

/// 1-minute energy window. Rates are cumulative counters over the effective span,
/// not the CPU page's already published two-frame fields.
final class EnergyWindowTests: XCTestCase {
    func testSingleTickIsMissingAndIsNotDisplayedAsZero() {
        var window = ProcessEnergyWindow()
        let rates = push(&window, energy: 0, wakeups: 0, at: 0)
        XCTAssertNotNil(rates)
        XCTAssertNil(rates?.watts)
        XCTAssertNil(rates?.wakeupsPerSecond)
        XCTAssertEqual(ProcessEnergyText.watts(rates?.watts), "—")
        XCTAssertEqual(ProcessEnergyText.wakeups(rates?.wakeupsPerSecond), "—")
        XCTAssertNotEqual(ProcessEnergyText.watts(rates?.watts), "0.0 W")
        XCTAssertNotEqual(ProcessEnergyText.wakeups(rates?.wakeupsPerSecond), "0.0 次/秒")
    }

    func testShortWindowUsesTheEffectiveDurationNotSixtySeconds() {
        var window = ProcessEnergyWindow()
        _ = push(&window, energy: 1_000, wakeups: 4, at: 0)
        let rates = push(&window, energy: 5_000_001_000, wakeups: 24, at: 10)
        XCTAssertEqual(rates?.watts ?? -1, 0.5, accuracy: 1e-9)
        XCTAssertEqual(rates?.wakeupsPerSecond ?? -1, 2, accuracy: 1e-9)
        XCTAssertNotEqual(rates?.watts ?? -1, 5_000_000_000.0 / 60.0 / 1e9)
        let oracle = ProcessEnergyLoad.rates(
            previous: tick(energy: 1_000, wakeups: 4, at: 0),
            current: tick(energy: 5_000_001_000, wakeups: 24, at: 10)
        )
        XCTAssertEqual(rates, oracle)
    }

    func testCumulativeWindowIsNotTheLastFrameAndNotTheAverageOfFrameWatts() {
        var window = ProcessEnergyWindow()
        _ = push(&window, energy: 0, wakeups: 0, at: 0)
        _ = push(&window, energy: 10_000_000_000, wakeups: 0, at: 10)
        let rates = push(&window, energy: 10_000_000_000, wakeups: 30, at: 30)
        XCTAssertEqual(rates?.watts ?? -1, 1.0 / 3.0, accuracy: 1e-9)
        XCTAssertEqual(rates?.wakeupsPerSecond ?? -1, 1, accuracy: 1e-9)
        XCTAssertNotEqual(rates?.watts ?? -1, 0.0)
        XCTAssertNotEqual(rates?.watts ?? -1, 0.5)
        XCTAssertNotEqual(rates?.wakeupsPerSecond ?? -1, 1.5)
        let anchor = ProcessEnergyLoad.rates(
            previous: tick(energy: 0, wakeups: 0, at: 0),
            current: tick(energy: 10_000_000_000, wakeups: 30, at: 30)
        )
        XCTAssertEqual(rates, anchor)
    }

    func testExactlySixtySecondsKeepsTheAnchor() {
        var window = ProcessEnergyWindow()
        _ = push(&window, energy: 0, wakeups: 0, at: 0)
        _ = push(&window, energy: 30_000_000_000, wakeups: 30, at: 30)
        let rates = push(&window, energy: 30_000_000_000, wakeups: 120, at: 60)
        XCTAssertEqual(rates?.watts ?? -1, 0.5, accuracy: 1e-9)
        XCTAssertEqual(rates?.wakeupsPerSecond ?? -1, 2, accuracy: 1e-9)
        XCTAssertNotEqual(rates?.watts ?? -1, 0.0)
        XCTAssertNotEqual(rates?.wakeupsPerSecond ?? -1, 3.0)
    }

    func testJustOverSixtySecondsDropsTheOldAnchorAndDoesNotPadTheDenominator() {
        var window = ProcessEnergyWindow()
        _ = push(&window, energy: 0, wakeups: 0, at: 0)
        let rates = push(&window, energy: 61_000_000_000, wakeups: 61, at: 61)
        XCTAssertNil(rates?.watts)
        XCTAssertNil(rates?.wakeupsPerSecond)
        XCTAssertNotEqual(rates?.watts ?? -1, 1.0)
        XCTAssertEqual(ProcessEnergyText.watts(rates?.watts), "—")
    }

    func testKeptSpanIsShorterThanSixtyWhenThePrefixFallsOutside() {
        var window = ProcessEnergyWindow()
        _ = push(&window, energy: 0, wakeups: 0, at: 0)
        _ = push(&window, energy: 100_000_000_000, wakeups: 10, at: 15)
        let rates = push(&window, energy: 150_000_000_000, wakeups: 120, at: 70)
        XCTAssertEqual(rates?.watts ?? -1, 50.0 / 55.0, accuracy: 1e-9)
        XCTAssertEqual(rates?.wakeupsPerSecond ?? -1, 110.0 / 55.0, accuracy: 1e-9)
        XCTAssertNotEqual(rates?.watts ?? -1, 50.0 / 60.0)
        XCTAssertNotEqual(rates?.watts ?? -1, 150.0 / 70.0)
    }

    func testZeroDeltaStaysZeroOnEitherSide() {
        var window = ProcessEnergyWindow()
        _ = push(&window, energy: 80_000_000_000, wakeups: 8, at: 0)
        let idle = push(&window, energy: 80_000_000_000, wakeups: 8, at: 15)
        XCTAssertEqual(idle?.watts ?? -1, 0, accuracy: 1e-9)
        XCTAssertEqual(idle?.wakeupsPerSecond ?? -1, 0, accuracy: 1e-9)
        XCTAssertNotNil(idle?.watts)
        XCTAssertNotNil(idle?.wakeupsPerSecond)
        XCTAssertEqual(ProcessEnergyText.watts(idle?.watts), "0.0 W")
        XCTAssertEqual(ProcessEnergyText.wakeups(idle?.wakeupsPerSecond), "0.0 次/秒")
        XCTAssertNotEqual(ProcessEnergyText.watts(idle?.watts), "—")

        var mixed = ProcessEnergyWindow()
        _ = push(&mixed, pid: 3, energy: 0, wakeups: 5, at: 0)
        let oneSide = push(&mixed, pid: 3, energy: 0, wakeups: 15, at: 10)
        XCTAssertEqual(oneSide?.watts ?? -1, 0, accuracy: 1e-9)
        XCTAssertEqual(oneSide?.wakeupsPerSecond ?? -1, 1, accuracy: 1e-9)
        XCTAssertNotNil(oneSide?.watts)
    }

    func testMissingReadingKeepsTheSegmentAndTheNextSuccessIncludesTheGap() {
        var window = ProcessEnergyWindow()
        _ = push(&window, energy: 0, wakeups: 0, at: 0)
        _ = push(&window, energy: 10_000_000_000, wakeups: 10, at: 10)
        let missed = pushMissing(&window, at: 20)
        XCTAssertNotNil(missed)
        XCTAssertNil(missed?.watts)
        XCTAssertNil(missed?.wakeupsPerSecond)
        let recovered = push(&window, energy: 40_000_000_000, wakeups: 40, at: 40)
        XCTAssertEqual(recovered?.watts ?? -1, 1, accuracy: 1e-9)
        XCTAssertEqual(recovered?.wakeupsPerSecond ?? -1, 1, accuracy: 1e-9)
        XCTAssertNotEqual(recovered?.watts ?? -1, 30.0 / 20.0)
    }

    func testAGapLongerThanSixtySecondsLeavesOnlyTheNewTick() {
        var window = ProcessEnergyWindow()
        _ = push(&window, energy: 0, wakeups: 0, at: 0)
        _ = push(&window, energy: 10_000_000_000, wakeups: 10, at: 10)
        _ = pushMissing(&window, at: 20)
        let late = push(&window, energy: 90_000_000_000, wakeups: 90, at: 90)
        XCTAssertNil(late?.watts)
        XCTAssertNil(late?.wakeupsPerSecond)
        XCTAssertNotEqual(late?.watts ?? -1, 1.0)
        XCTAssertEqual(ProcessEnergyText.watts(late?.watts), "—")
    }

    func testEnergyDecreaseRebuildsTheSegmentBeforeTheNextShortWindow() {
        var window = ProcessEnergyWindow()
        _ = push(&window, energy: 100_000_000_000, wakeups: 10, at: 0)
        let dropped = push(&window, energy: 50_000_000_000, wakeups: 20, at: 10)
        XCTAssertNil(dropped?.watts)
        XCTAssertNil(dropped?.wakeupsPerSecond)
        let rebuilt = push(&window, energy: 80_000_000_000, wakeups: 35, at: 25)
        XCTAssertEqual(rebuilt?.watts ?? -1, 2, accuracy: 1e-9)
        XCTAssertEqual(rebuilt?.wakeupsPerSecond ?? -1, 1, accuracy: 1e-9)
        XCTAssertNotNil(rebuilt?.watts)
    }

    func testWakeupDecreaseAloneRebuildsBothRates() {
        var window = ProcessEnergyWindow()
        _ = push(&window, energy: 0, wakeups: 100, at: 0)
        let dropped = push(&window, energy: 10_000_000_000, wakeups: 40, at: 10)
        XCTAssertNil(dropped?.watts)
        XCTAssertNil(dropped?.wakeupsPerSecond)
        let rebuilt = push(&window, energy: 20_000_000_000, wakeups: 50, at: 20)
        XCTAssertEqual(rebuilt?.watts ?? -1, 1, accuracy: 1e-9)
        XCTAssertEqual(rebuilt?.wakeupsPerSecond ?? -1, 1, accuracy: 1e-9)
        XCTAssertNotEqual(rebuilt?.watts ?? -1, 2.0)
    }

    func testNonPositiveDurationRebuildsTheSegment() {
        var window = ProcessEnergyWindow()
        _ = push(&window, energy: 0, wakeups: 0, at: 10)
        let sameInstant = push(&window, energy: 5_000_000_000, wakeups: 1, at: 10)
        XCTAssertNil(sameInstant?.watts)
        XCTAssertNil(sameInstant?.wakeupsPerSecond)
        let next = push(&window, energy: 9_000_000_000, wakeups: 5, at: 14)
        XCTAssertEqual(next?.watts ?? -1, 1, accuracy: 1e-9)
        XCTAssertEqual(next?.wakeupsPerSecond ?? -1, 1, accuracy: 1e-9)
        XCTAssertNotEqual(next?.watts ?? -1, 2.25)
    }

    func testFailedFrameDoesNotTreatEmptyRowsAsEveryProcessExiting() {
        var window = ProcessEnergyWindow()
        _ = push(&window, energy: 0, wakeups: 0, at: 0)
        _ = push(&window, energy: 10_000_000_000, wakeups: 10, at: 10)
        let failed = window.advance(listed: [:], listSucceeded: false)
        XCTAssertTrue(failed.isEmpty)
        let continued = push(&window, energy: 30_000_000_000, wakeups: 30, at: 30)
        XCTAssertEqual(continued?.watts ?? -1, 1, accuracy: 1e-9)
        XCTAssertEqual(continued?.wakeupsPerSecond ?? -1, 1, accuracy: 1e-9)
        XCTAssertNotNil(continued?.watts)
    }

    func testFailedFrameDoesNotApplyADecreasedReadingEither() {
        var window = ProcessEnergyWindow()
        _ = push(&window, energy: 0, wakeups: 0, at: 0)
        _ = push(&window, energy: 10_000_000_000, wakeups: 10, at: 10)
        let failed = window.advance(
            listed: [7: tick(energy: 1, wakeups: 1, at: 15)],
            listSucceeded: false
        )
        XCTAssertTrue(failed.isEmpty)
        let continued = push(&window, energy: 20_000_000_000, wakeups: 20, at: 20)
        XCTAssertEqual(continued?.watts ?? -1, 1, accuracy: 1e-9)
        XCTAssertEqual(continued?.wakeupsPerSecond ?? -1, 1, accuracy: 1e-9)
    }

    func testLeavingTheListDeletesTheSegmentAndThePidReturnsWithoutABaseline() {
        var window = ProcessEnergyWindow()
        _ = push(&window, energy: 0, wakeups: 0, at: 0)
        _ = push(&window, energy: 10_000_000_000, wakeups: 10, at: 10)
        let gone = window.advance(listed: [:], listSucceeded: true)
        XCTAssertTrue(gone.isEmpty)
        let returned = push(&window, energy: 10_000_000_000, wakeups: 10, at: 20)
        XCTAssertNil(returned?.watts)
        XCTAssertNil(returned?.wakeupsPerSecond)
        XCTAssertNotEqual(returned?.watts ?? -1, 0.5)
        let fresh = push(&window, energy: 20_000_000_000, wakeups: 20, at: 30)
        XCTAssertEqual(fresh?.watts ?? -1, 1, accuracy: 1e-9)
        XCTAssertNotEqual(fresh?.watts ?? -1, 20.0 / 30.0)
    }

    func testTwoPidsKeepSeparateSegments() {
        var window = ProcessEnergyWindow()
        let first = window.advance(
            listed: [
                1: tick(energy: 0, wakeups: 0, at: 0),
                2: tick(energy: 4_000_000_000, wakeups: 1, at: 0),
            ],
            listSucceeded: true
        )
        XCTAssertNil(first[1]?.watts)
        XCTAssertNil(first[2]?.watts)
        let second = window.advance(
            listed: [
                1: tick(energy: 10_000_000_000, wakeups: 10, at: 10),
                2: tick(energy: 4_000_000_000, wakeups: 1, at: 10),
            ],
            listSucceeded: true
        )
        XCTAssertEqual(second[1]?.watts ?? -1, 1, accuracy: 1e-9)
        XCTAssertEqual(second[1]?.wakeupsPerSecond ?? -1, 1, accuracy: 1e-9)
        XCTAssertEqual(second[2]?.watts ?? -1, 0, accuracy: 1e-9)
        XCTAssertEqual(second[2]?.wakeupsPerSecond ?? -1, 0, accuracy: 1e-9)
        XCTAssertNotNil(second[2]?.watts)
    }

    func testCPUTwoFrameAdvanceStillMissesThenKeepsARealZeroAndAFailedRead() {
        let start = tick(energy: 5_000_000_000, wakeups: 2, at: 0)
        let first = ProcessEnergyLoad.advance(previous: nil, reading: start)
        XCTAssertNil(first.rates.watts)
        XCTAssertNil(first.rates.wakeupsPerSecond)
        XCTAssertEqual(first.baseline, start)
        let idle = ProcessEnergyLoad.advance(
            previous: first.baseline,
            reading: tick(energy: 5_000_000_000, wakeups: 2, at: 10)
        )
        XCTAssertEqual(idle.rates.watts ?? -1, 0, accuracy: 1e-9)
        XCTAssertEqual(idle.rates.wakeupsPerSecond ?? -1, 0, accuracy: 1e-9)
        XCTAssertNotNil(idle.rates.watts)
        let missed = ProcessEnergyLoad.advance(previous: start, reading: nil)
        XCTAssertNil(missed.rates.watts)
        XCTAssertEqual(missed.baseline, start)
        let decreased = ProcessEnergyLoad.rates(
            previous: start,
            current: tick(energy: 1, wakeups: 9, at: 10)
        )
        XCTAssertNil(decreased.watts)
        XCTAssertNil(decreased.wakeupsPerSecond)
    }

    private func tick(energy: UInt64, wakeups: UInt64, at seconds: TimeInterval) -> EnergyTick {
        EnergyTick(
            energyNanojoules: energy,
            interruptWakeups: wakeups,
            date: Date(timeIntervalSince1970: 1_700_000_000).addingTimeInterval(seconds)
        )
    }

    @discardableResult
    private func push(
        _ window: inout ProcessEnergyWindow,
        pid: Int32 = 7,
        energy: UInt64,
        wakeups: UInt64,
        at seconds: TimeInterval,
        listSucceeded: Bool = true
    ) -> ProcessEnergyRates? {
        window.advance(
            listed: [pid: tick(energy: energy, wakeups: wakeups, at: seconds)],
            listSucceeded: listSucceeded
        )[pid]
    }

    private func pushMissing(
        _ window: inout ProcessEnergyWindow,
        pid: Int32 = 7,
        at seconds: TimeInterval
    ) -> ProcessEnergyRates? {
        _ = seconds
        return window.advance(listed: [pid: nil], listSucceeded: true)[pid]
    }
}

final class EnergyPageSortTests: XCTestCase {
    func testNilWindowRatesSortLastInBothDirectionsAndIgnoreDecoyWatts() {
        let rows = [
            row(1, "M", decoyWatts: 100),
            row(2, "Z", decoyWatts: 0),
            row(3, "A", decoyWatts: nil),
        ]
        let rates: [Int32: ProcessEnergyRates] = [
            1: .missing,
            2: ProcessEnergyRates(watts: 0, wakeupsPerSecond: 0),
            3: ProcessEnergyRates(watts: 1.5, wakeupsPerSecond: 4),
        ]
        let ascending = EnergyPage.ordered(rows, rates: rates, sort: ProcessTableSort(column: .energy, descending: false))
        let descending = EnergyPage.ordered(rows, rates: rates, sort: ProcessTableSort(column: .energy, descending: true))
        XCTAssertEqual(ascending.map(\.pid), [2, 3, 1])
        XCTAssertEqual(descending.map(\.pid), [3, 2, 1])
        let wakeAscending = EnergyPage.ordered(rows, rates: rates, sort: ProcessTableSort(column: .wakeups, descending: false))
        let wakeDescending = EnergyPage.ordered(rows, rates: rates, sort: ProcessTableSort(column: .wakeups, descending: true))
        XCTAssertEqual(wakeAscending.map(\.pid), [2, 3, 1])
        XCTAssertEqual(wakeDescending.map(\.pid), [3, 2, 1])
        XCTAssertEqual(ProcessTableSort(column: .energy, descending: false).ordered(rows).map(\.pid), [1, 2, 3])
    }

    func testEqualWindowRatesAndSharedNilsBreakTiesByPidAscending() {
        let rows = [
            row(30, "Same", decoyWatts: 1),
            row(10, "Same", decoyWatts: 9),
            row(20, "Other", decoyWatts: nil),
        ]
        let valued: [Int32: ProcessEnergyRates] = [
            30: ProcessEnergyRates(watts: 1.5, wakeupsPerSecond: 2),
            10: ProcessEnergyRates(watts: 1.5, wakeupsPerSecond: 2),
            20: .missing,
        ]
        let descending = EnergyPage.ordered(rows, rates: valued, sort: ProcessTableSort(column: .energy, descending: true))
        let ascending = EnergyPage.ordered(rows, rates: valued, sort: ProcessTableSort(column: .wakeups, descending: false))
        XCTAssertEqual(descending.map(\.pid), [10, 30, 20])
        XCTAssertEqual(ascending.map(\.pid), [10, 30, 20])

        let nils: [Int32: ProcessEnergyRates] = [
            30: .missing,
            10: .missing,
        ]
        let nilRows = [row(30, "B", decoyWatts: 4), row(10, "A", decoyWatts: 0)]
        let nilDescending = EnergyPage.ordered(nilRows, rates: nils, sort: ProcessTableSort(column: .energy, descending: true))
        let nilAscending = EnergyPage.ordered(nilRows, rates: nils, sort: ProcessTableSort(column: .energy, descending: false))
        XCTAssertEqual(nilDescending.map(\.pid), [10, 30])
        XCTAssertEqual(nilAscending.map(\.pid), [10, 30])
    }

    func testNameSortUsesStringOrderAndDoesNotSinkNilRates() {
        let rows = [
            row(2, "Beta", decoyWatts: 0),
            row(1, "Alpha", decoyWatts: 50),
        ]
        let rates: [Int32: ProcessEnergyRates] = [
            2: ProcessEnergyRates(watts: 9, wakeupsPerSecond: 9),
            1: .missing,
        ]
        let ascending = EnergyPage.ordered(rows, rates: rates, sort: ProcessTableSort(column: .name, descending: false))
        let descending = EnergyPage.ordered(rows, rates: rates, sort: ProcessTableSort(column: .name, descending: true))
        XCTAssertEqual(ascending.map(\.name), ["Alpha", "Beta"])
        XCTAssertEqual(descending.map(\.name), ["Beta", "Alpha"])
        let sameName = [
            row(8, "Mail", decoyWatts: nil),
            row(3, "Mail", decoyWatts: 1),
        ]
        let byName = EnergyPage.ordered(
            sameName,
            rates: [8: .missing, 3: ProcessEnergyRates(watts: 4, wakeupsPerSecond: nil)],
            sort: ProcessTableSort(column: .name, descending: true)
        )
        XCTAssertEqual(byName.map(\.pid), [3, 8])
    }

    func testSearchMatchesTheNameOnlyAndKeepsANilRateRow() {
        let rows = [
            row(42, "Safari", decoyWatts: nil),
            row(7, "Mail", decoyWatts: 1),
        ]
        let matched = EnergyPage.filtered(rows, query: "  saFa ")
        XCTAssertEqual(matched.map(\.pid), [42])
        XCTAssertEqual(EnergyPage.filtered(rows, query: "42").map(\.pid), [])
        XCTAssertEqual(EnergyPage.filtered(rows, query: "   ").map(\.pid), [42, 7])
        XCTAssertEqual(EnergyPage.filtered(rows, query: "").map(\.pid), [42, 7])
    }

    func testCPUAscendingStillSortsNilEnergyBeforeARealZero() {
        let rows = [
            row(3, "M", decoyWatts: nil),
            row(1, "Z", decoyWatts: 0),
            row(2, "A", decoyWatts: 1.5),
        ]
        let ascending = ProcessTableSort(column: .energy, descending: false).ordered(rows)
        let descending = ProcessTableSort(column: .energy, descending: true).ordered(rows)
        XCTAssertEqual(ascending.map(\.pid), [3, 1, 2])
        XCTAssertEqual(descending.map(\.pid), [2, 1, 3])
        XCTAssertEqual(
            ProcessColumnTitle.cpuPage,
            ["名称", "CPU", "内存", "能耗影响", "唤醒", "线程"]
        )
        XCTAssertEqual(ProcessTableSort.defaultSort(for: .cpu).column, .cpu)
        XCTAssertTrue(ProcessTableSort.defaultSort(for: .cpu).descending)
    }

    private func row(_ pid: Int32, _ name: String, decoyWatts: Double?) -> ProcessRow {
        ProcessRow(
            pid: pid,
            name: name,
            bundleIdentifier: nil,
            executablePath: nil,
            cpuPercent: 80,
            memoryBytes: 5_000_000,
            threadCount: 3,
            energyWatts: decoyWatts,
            wakeupsPerSecond: decoyWatts,
            groupedMemberCount: nil
        )
    }
}

final class EnergyPagePhaseTests: XCTestCase {
    func testEmptyListStatesStayDistinctFromSearch() {
        XCTAssertEqual(phase(loadState: .sampling, processCount: 0, visibleCount: 0, filtering: true, listFailed: false), .sampling)
        XCTAssertEqual(phase(loadState: .ready, processCount: 0, visibleCount: 0, filtering: true, listFailed: true), .processListFailed)
        XCTAssertEqual(phase(loadState: .failed, processCount: 0, visibleCount: 0, filtering: true, listFailed: false), .sampleFailed)
        XCTAssertEqual(phase(loadState: .ready, processCount: 0, visibleCount: 0, filtering: true, listFailed: false), .empty)
        XCTAssertNotEqual(
            phase(loadState: .ready, processCount: 0, visibleCount: 0, filtering: true, listFailed: false),
            .filteredEmpty
        )
    }

    func testSearchEmptyRequiresRowsThatTheNameFilterRemoved() {
        XCTAssertEqual(phase(loadState: .ready, processCount: 4, visibleCount: 0, filtering: true, listFailed: false), .filteredEmpty)
        XCTAssertEqual(phase(loadState: .ready, processCount: 4, visibleCount: 2, filtering: true, listFailed: false), .ready)
        XCTAssertEqual(phase(loadState: .failed, processCount: 4, visibleCount: 4, filtering: false, listFailed: false), .ready)
        XCTAssertEqual(EnergyPageCopy.emptyTitle, "还没有进程数据")
        XCTAssertEqual(EnergyPageCopy.emptyMessage, "这一帧没有进程可显示。")
        XCTAssertEqual(EnergyPageCopy.filteredEmptyTitle, "没有匹配的 App")
        XCTAssertEqual(EnergyPageCopy.filteredEmptyMessage, "换个名称试试，或清空过滤。")
        XCTAssertEqual(EnergyPageCopy.filteredEmptyButton, "清空过滤")
        XCTAssertNotEqual(EnergyPageCopy.emptyTitle, EnergyPageCopy.filteredEmptyTitle)
        XCTAssertEqual(EnergyPageCopy.processListFailedTitle, "暂时无法列出进程")
        XCTAssertEqual(EnergyPageCopy.processListFailedMessage, SamplingRetryChrome.processListFailedMessage)
        XCTAssertEqual(EnergyPageCopy.sampleFailedTitle, "进程列表还没有数据")
        XCTAssertEqual(EnergyPageCopy.sampleFailedMessage, SamplingRetryChrome.overviewFailureMessage)
        XCTAssertFalse(EnergyPageCopy.sampleFailedTitle.contains("CPU"))
        XCTAssertFalse(EnergyPageCopy.processListFailedTitle.contains("CPU"))
        XCTAssertEqual(EnergyPageCopy.samplingTitle, "正在采样…")
        XCTAssertEqual(EnergyPageCopy.retry, SamplingRetryChrome.buttonTitle)
    }

    private func phase(
        loadState: LoadState,
        processCount: Int,
        visibleCount: Int,
        filtering: Bool,
        listFailed: Bool
    ) -> EnergyPagePhase {
        EnergyPage.phase(
            loadState: loadState,
            processCount: processCount,
            visibleCount: visibleCount,
            hasActiveNameFilter: filtering,
            processListFailed: listFailed
        )
    }
}

final class EnergyPageCopyTests: XCTestCase {
    func testStaticCopyUsesTheLockedTitlesAndCellUnits() {
        XCTAssertEqual(EnergyPageCopy.headline, "最近 1 分钟平均功率")
        XCTAssertEqual(
            EnergyPageCopy.explanation,
            "用这段时间里累计的能耗除以实际时长。不足 1 分钟时用已经采到的时长。读不到显示「—」，不显示 0。这不是活动监视器的能耗影响分数。"
        )
        XCTAssertEqual(EnergyPageCopy.columns, ["名称", "能耗影响", "唤醒"])
        XCTAssertEqual(EnergyPageCopy.impactTitle, ProcessEnergyText.impactTitle)
        XCTAssertEqual(EnergyPageCopy.wakeTitle, ProcessEnergyText.wakeTitle)
        XCTAssertFalse(EnergyPageCopy.columns.contains("能耗影响(W)"))
        XCTAssertFalse(EnergyPageCopy.columns.contains("唤醒/秒"))
        XCTAssertFalse(EnergyPageCopy.explanation.contains("分数相等"))
    }

    func testEnergyLineUsesTheWindowRatesAndThePid() {
        let row = ProcessRow(
            pid: 42,
            name: "Safari",
            bundleIdentifier: nil,
            executablePath: nil,
            cpuPercent: 12.5,
            memoryBytes: 1_048_576,
            threadCount: 4,
            energyWatts: 9,
            wakeupsPerSecond: 9,
            groupedMemberCount: 4
        )
        let line = ProcessRowCopy.line(
            page: .energy,
            row: row,
            energyWindow: ProcessEnergyRates(watts: 1.5, wakeupsPerSecond: 3)
        )
        XCTAssertEqual(line, "Safari\t42\t1.5 W\t3.0 次/秒")
        XCTAssertFalse(line.contains("9.0"))
        XCTAssertFalse(line.contains("%"))
        XCTAssertFalse(line.contains("MB"))
        XCTAssertFalse(line.contains("\t4\t"))
        let missing = ProcessRowCopy.line(page: .energy, row: row, energyWindow: nil)
        XCTAssertEqual(missing, "Safari\t42\t—\t—")
        let zero = ProcessRowCopy.line(
            page: .energy,
            row: row,
            energyWindow: ProcessEnergyRates(watts: 0, wakeupsPerSecond: 0)
        )
        XCTAssertEqual(zero, "Safari\t42\t0.0 W\t0.0 次/秒")
        XCTAssertNotEqual(missing, zero)
    }

    func testCPULineStillUsesTheTwoFrameFieldsWhenAWindowIsPassed() {
        let row = ProcessRow(
            pid: 42,
            name: "Safari",
            bundleIdentifier: nil,
            executablePath: nil,
            cpuPercent: 12.5,
            memoryBytes: 1_048_576,
            threadCount: 4,
            energyWatts: 1.5,
            wakeupsPerSecond: 3
        )
        let line = ProcessRowCopy.line(
            page: .cpu,
            row: row,
            energyWindow: ProcessEnergyRates(watts: 9, wakeupsPerSecond: 9)
        )
        XCTAssertEqual(line, "Safari\t42\t12.5%\t1 MB\t1.5 W\t3.0 次/秒\t4")
        XCTAssertFalse(line.contains("9.0"))
    }
}

final class EnergyPageNavigationTests: XCTestCase {
    func testEnteringEnergyResetsToEnergyDescending() {
        var navigation = DashboardNavigation()
        navigation.select(.energy)
        XCTAssertEqual(navigation.selectedPage, .energy)
        XCTAssertEqual(navigation.sort, ProcessTableSort(column: .energy, descending: true))
        navigation.updateSort(navigation.sort.selecting(.name))
        XCTAssertEqual(navigation.sort, ProcessTableSort(column: .name, descending: false))
        navigation.updateSort(navigation.sort.selecting(.wakeups))
        XCTAssertEqual(navigation.sort, ProcessTableSort(column: .wakeups, descending: true))
        navigation.updateSort(navigation.sort.selecting(.energy))
        XCTAssertEqual(navigation.sort, ProcessTableSort(column: .energy, descending: true))
        navigation.updateSort(navigation.sort.selecting(.energy))
        XCTAssertEqual(navigation.sort, ProcessTableSort(column: .energy, descending: false))
        navigation.select(.cpu)
        navigation.select(.energy)
        XCTAssertEqual(navigation.sort, ProcessTableSort(column: .energy, descending: true))
        XCTAssertEqual(ProcessTableSort.defaultSort(for: .cpu).column, .cpu)
        XCTAssertEqual(ProcessTableSort.defaultSort(for: .memory).column, .memory)
    }

    func testEnergyIsSelectableAndDisablesQuitWithoutChangingTheOtherPages() {
        XCTAssertTrue(DashboardPage.energy.isSelectable)
        XCTAssertFalse(DashboardPage.energy.allowsProcessQuit)
        XCTAssertTrue(DashboardPage.memory.allowsProcessQuit)
        XCTAssertTrue(DashboardPage.cpu.allowsProcessQuit)
        XCTAssertTrue(DashboardPage.disk.allowsProcessQuit)
        XCTAssertTrue(DashboardPage.network.allowsProcessQuit)
        XCTAssertFalse(DashboardPage.machine.allowsProcessQuit)
        XCTAssertTrue(DashboardPage.gpu.allowsProcessQuit)
        XCTAssertFalse(DashboardPage.gpu.isSelectable)
        XCTAssertFalse(AppGroupChrome.showsToggle(page: .energy))
        XCTAssertFalse(AppGroupChrome.applies(on: .energy))
        XCTAssertFalse(MemoryRisingOnlyChrome.showsToggle(page: .energy))
        XCTAssertFalse(WindowedAppChrome.showsToggle(page: .energy))
        XCTAssertTrue(AppGroupChrome.showsToggle(page: .cpu))
        XCTAssertTrue(MemoryRisingOnlyChrome.showsToggle(page: .memory))
    }
}

/// Source locks for the production wiring. They do not open the Mac window.
final class EnergyPageWiringSourceTests: XCTestCase {
    func testSamplerConsumesTheEnumeratorReadingOnceAndSkipsTheListFailureBranch() throws {
        let enumerator = try repoText("Pulse/Sampling/ProcessEnumerator.swift")
        let sampler = try repoText("Pulse/Sampling/MemorySampler.swift")
        XCTAssertTrue(enumerator.contains("energyNanojoules: info.ri_energy_nj"))
        XCTAssertTrue(enumerator.contains("interruptWakeups: info.ri_interrupt_wkups"))
        XCTAssertEqual(occurrenceCount(of: "pulse_proc_pid_rusage(", in: enumerator), 2)
        XCTAssertFalse(enumerator.contains("info.ri_billed_energy"))
        XCTAssertFalse(sampler.contains("ri_energy_nj"))
        XCTAssertFalse(sampler.contains("ri_billed_energy"))
        XCTAssertFalse(sampler.contains("IOPSGetTimeRemainingEstimate"))
        XCTAssertEqual(occurrenceCount(of: "proc_pid_rusage", in: sampler), 0)
        XCTAssertTrue(sampler.contains("ProcessEnergyLoad.advance"))
        XCTAssertTrue(sampler.contains("energyWatts: energy.rates.watts"))
        XCTAssertTrue(sampler.contains("wakeupsPerSecond: energy.rates.wakeupsPerSecond"))
        XCTAssertTrue(sampler.contains("energyWindow.advance(listed:"))
        XCTAssertTrue(sampler.contains("listSucceeded: true"))
        XCTAssertFalse(sampler.contains("listSucceeded: false"))
        XCTAssertEqual(occurrenceCount(of: "energyWindow.advance(", in: sampler), 1)
        let failure = try braceBody(after: "ProcessEnumerator.list() else", in: sampler)
        XCTAssertFalse(failure.contains("energyWindow"))
        XCTAssertFalse(failure.contains("ProcessEnergyWindow"))
        XCTAssertTrue(failure.contains("processListFailed: true"))
        let package = try repoText("Package.swift")
        XCTAssertTrue(package.contains("\"Sampling/ProcessEnergyWindow.swift\""))
        XCTAssertTrue(package.contains("\"Models/EnergyPage.swift\""))
        let project = try repoText("Pulse.xcodeproj/project.pbxproj")
        XCTAssertTrue(project.contains("ProcessEnergyWindow.swift in Sources"))
        XCTAssertTrue(project.contains("EnergyPage.swift in Sources"))
        XCTAssertTrue(project.contains("EnergyProcessTable.swift in Sources"))
        XCTAssertEqual(
            occurrenceCount(of: "isa = PBXBuildFile;", in: project),
            95
        )
    }

    func testEnergyTableReadsWindowRatesAndTheCPUTableKeepsTwoFrameWatts() throws {
        let tableURL = repoRoot().appendingPathComponent("Pulse/Views/EnergyProcessTable.swift")
        XCTAssertTrue(FileManager.default.fileExists(atPath: tableURL.path))
        guard FileManager.default.fileExists(atPath: tableURL.path) else { return }
        let table = try String(contentsOf: tableURL, encoding: .utf8)
        XCTAssertFalse(table.contains("?? -1"))
        XCTAssertFalse(table.contains("energyWatts ??"))
        XCTAssertFalse(table.contains("row.energyWatts"))
        XCTAssertFalse(table.contains("row.wakeupsPerSecond"))
        XCTAssertTrue(table.contains("energyWindowRates"))
        XCTAssertTrue(table.contains("ProcessEnergyText.watts"))
        XCTAssertTrue(table.contains("ProcessEnergyText.wakeups"))
        XCTAssertTrue(table.contains("EnergyPageCopy.headline"))
        XCTAssertTrue(table.contains("EnergyPageCopy.explanation"))
        XCTAssertTrue(table.contains("EnergyPageCopy.emptyTitle"))
        XCTAssertTrue(table.contains("EnergyPageCopy.filteredEmptyTitle"))
        XCTAssertFalse(table.contains("1 小时"))
        XCTAssertFalse(table.contains("按 App"))
        XCTAssertFalse(table.contains("ProcessDetailSidebar"))
        XCTAssertFalse(table.contains("IOPSGetTimeRemainingEstimate"))

        let pane = try repoText("Pulse/Views/ProcessTablePane.swift")
        XCTAssertTrue(pane.contains("vm.selectedPage == .cpu"))
        XCTAssertTrue(pane.contains("ProcessEnergyText.watts(row.energyWatts)"))
        XCTAssertTrue(pane.contains("EnergyProcessTable()"))
        XCTAssertEqual(occurrenceCount(of: "Button(\"复制\")", in: pane), 1)

        let dashboard = try repoText("Pulse/Views/MemoryDashboardView.swift")
        let energyColumn = try braceBody(after: "var energyResourceColumn", in: dashboard)
        XCTAssertTrue(energyColumn.contains("ProcessTablePane()"))
        XCTAssertFalse(energyColumn.contains("ProcessDetailSidebar"))
        XCTAssertFalse(energyColumn.contains("OverviewSection"))
        XCTAssertTrue(dashboard.contains("ProcessDetailSidebar()"))

        let shared = try repoText("Pulse/Views/SharedUI.swift")
        let cpu = try index(of: "case cpu", in: shared)
        let energy = try index(of: "case energy = \"能耗\"", in: shared)
        let disk = try index(of: "case disk", in: shared)
        XCTAssertLessThan(cpu, energy)
        XCTAssertLessThan(energy, disk)
        XCTAssertTrue(shared.contains("case .energy: return \"bolt\""))
        XCTAssertFalse(shared.contains("keyboardShortcut"))

        let app = try repoText("Pulse/PulseApp.swift")
        XCTAssertFalse(app.contains("selectPage(.energy)"))
        XCTAssertFalse(app.contains("Button(\"能耗\")"))
        XCTAssertTrue(app.contains("case .memory, .cpu, .disk, .network, .energy:"))
        XCTAssertTrue(app.contains("energyWindowRates"))
        let status = try repoText("Pulse/MenuBar/MenuBarStatus.swift")
        XCTAssertTrue(status.contains("self != .machine && self != .energy"))
        let vm = try repoText("Pulse/ViewModels/MemoryDashboardVM.swift")
        let sorted = try functionBody(named: "sortedRows", in: vm)
        XCTAssertTrue(sorted.contains("EnergyPage.ordered"))
        XCTAssertTrue(sorted.contains("energyWindowRates"))
        XCTAssertFalse(sorted.contains("?? -1"))
        XCTAssertFalse(sorted.contains("energyWatts"))
        let failure = try braceBody(after: "case .failure:", in: vm)
        XCTAssertFalse(failure.contains("energyWindowRates"))
        let snapshot = try repoText("Pulse/Models/SnapshotExport.swift")
        XCTAssertFalse(snapshot.contains("energyWindow"))
        XCTAssertFalse(snapshot.contains("ri_energy_nj"))
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

    private func index(of needle: String, in source: String) throws -> String.Index {
        guard let found = source.range(of: needle)?.lowerBound else {
            throw EnergySourceError.missing(needle)
        }
        return found
    }

    private func functionBody(named name: String, in source: String) throws -> String {
        let patterns = ["func \(name)(", "private func \(name)(", "var \(name):"]
        for pattern in patterns {
            guard let range = source.range(of: pattern),
                  let brace = source[range.lowerBound...].firstIndex(of: "{")
            else { continue }
            return try balancedSlice(from: brace, in: source, label: name)
        }
        throw EnergySourceError.missing(name)
    }

    private func braceBody(after needle: String, in source: String) throws -> String {
        guard let start = source.range(of: needle)?.upperBound,
              let brace = source[start...].firstIndex(of: "{")
        else { throw EnergySourceError.missing(needle) }
        return try balancedSlice(from: brace, in: source, label: needle)
    }

    private func balancedSlice(from start: String.Index, in source: String, label: String) throws -> String {
        var depth = 0
        var cursor = start
        while cursor < source.endIndex {
            let character = source[cursor]
            if character == "{" { depth += 1 }
            if character == "}" {
                depth -= 1
                if depth == 0 { return String(source[start...cursor]) }
            }
            cursor = source.index(after: cursor)
        }
        throw EnergySourceError.missing("balanced brace for \(label)")
    }

    private func occurrenceCount(of needle: String, in haystack: String) -> Int {
        haystack.components(separatedBy: needle).count - 1
    }
}

private enum EnergySourceError: Error, CustomStringConvertible {
    case missing(String)
    var description: String {
        switch self {
        case .missing(let detail):
            return "missing \(detail)"
        }
    }
}
