import XCTest
@testable import SamplingCore

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
        XCTAssertEqual(ProcessTableSort(column: .energy, descending: false).ordered(rows).map(\.pid), [3, 2, 1])
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

    func testEnergyLineUsesTheWindowRatesAndTheVisibleSecondColumn() {
        let grouped = ProcessRow(
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
            row: grouped,
            energyWindow: ProcessEnergyRates(watts: 1.5, wakeupsPerSecond: 3)
        )
        XCTAssertEqual(line, "Safari\t4\t1.5 W\t3.0 次/秒")
        XCTAssertFalse(line.contains("9.0"))
        XCTAssertFalse(line.contains("%"))
        XCTAssertFalse(line.contains("MB"))
        XCTAssertFalse(line.contains("\t42\t"))
        let missing = ProcessRowCopy.line(page: .energy, row: grouped, energyWindow: nil)
        XCTAssertEqual(missing, "Safari\t4\t—\t—")
        let zero = ProcessRowCopy.line(
            page: .energy,
            row: grouped,
            energyWindow: ProcessEnergyRates(watts: 0, wakeupsPerSecond: 0)
        )
        XCTAssertEqual(zero, "Safari\t4\t0.0 W\t0.0 次/秒")
        XCTAssertNotEqual(missing, zero)

        let alone = ProcessRow(
            pid: 42,
            name: "Safari",
            bundleIdentifier: nil,
            executablePath: nil,
            cpuPercent: 12.5,
            memoryBytes: 1_048_576,
            threadCount: 4,
            energyWatts: 9,
            wakeupsPerSecond: 9,
            groupedMemberCount: 1
        )
        XCTAssertEqual(
            ProcessRowCopy.line(page: .energy, row: alone, energyWindow: ProcessEnergyRates(watts: 1.5, wakeupsPerSecond: 3)),
            "Safari\t1\t1.5 W\t3.0 次/秒"
        )
        let ungrouped = ProcessRow(
            pid: 42,
            name: "Safari",
            bundleIdentifier: nil,
            executablePath: nil,
            cpuPercent: 12.5,
            memoryBytes: 1_048_576,
            threadCount: 4,
            energyWatts: 9,
            wakeupsPerSecond: 9
        )
        XCTAssertEqual(
            ProcessRowCopy.line(page: .energy, row: ungrouped, energyWindow: ProcessEnergyRates(watts: 1.5, wakeupsPerSecond: 3)),
            "Safari\t42\t1.5 W\t3.0 次/秒"
        )
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

    func testEnergyIsSelectableAndQuitsLikeTheOtherProcessPages() {
        XCTAssertTrue(DashboardPage.energy.isSelectable)
        XCTAssertTrue(DashboardPage.energy.allowsProcessQuit)
        XCTAssertTrue(DashboardPage.memory.allowsProcessQuit)
        XCTAssertTrue(DashboardPage.cpu.allowsProcessQuit)
        XCTAssertTrue(DashboardPage.disk.allowsProcessQuit)
        XCTAssertTrue(DashboardPage.network.allowsProcessQuit)
        XCTAssertFalse(DashboardPage.machine.allowsProcessQuit)
        XCTAssertTrue(DashboardPage.gpu.allowsProcessQuit)
        XCTAssertFalse(DashboardPage.gpu.isSelectable)
        XCTAssertTrue(AppGroupChrome.showsToggle(page: .energy))
        XCTAssertTrue(AppGroupChrome.applies(on: .energy))
        XCTAssertFalse(AppGroupChrome.showsProcessTreeButton(groupedByApp: true, page: .energy))
        XCTAssertTrue(AppGroupChrome.showsProcessTreeButton(groupedByApp: false, page: .energy))
        XCTAssertFalse(MemoryRisingOnlyChrome.showsToggle(page: .energy))
        XCTAssertFalse(WindowedAppChrome.showsToggle(page: .energy))
        XCTAssertTrue(AppGroupChrome.showsToggle(page: .cpu))
        XCTAssertTrue(MemoryRisingOnlyChrome.showsToggle(page: .memory))
    }
}

/// Energy-page groups sum the 1-minute window, not the two-frame row fields.
final class EnergyPageGroupTests: XCTestCase {
    func testGroupedWindowSumsKeepARealZeroAndLeaveSampledWattsUntouched() throws {
        let mailHeavy = row(30, "Mail", memory: 200, decoyWatts: 50, decoyWakeups: 9)
        let mailLead = row(20, "Mail", memory: 200, decoyWatts: 7, decoyWakeups: 8)
        let mailLight = row(10, "Mail", memory: 100, decoyWatts: 99, decoyWakeups: nil)
        let idleLead = row(4, "Idle", memory: 10, decoyWatts: 40, decoyWakeups: 6)
        let idleOther = row(6, "Idle", memory: 1, decoyWatts: 0, decoyWakeups: 1)
        let goneLead = row(1, "Gone", memory: 9, decoyWatts: 3, decoyWakeups: 3)
        let goneOther = row(8, "Gone", memory: 5, decoyWatts: nil, decoyWakeups: nil)
        let solo = row(5, "Solo", memory: 2, decoyWatts: 0, decoyWakeups: 11)
        let rows = [mailHeavy, mailLead, mailLight, idleLead, idleOther, goneLead, goneOther, solo]
        let rates: [Int32: ProcessEnergyRates] = [
            30: ProcessEnergyRates(watts: nil, wakeupsPerSecond: 4),
            20: ProcessEnergyRates(watts: 0, wakeupsPerSecond: 0),
            10: ProcessEnergyRates(watts: 1.5, wakeupsPerSecond: nil),
            4: ProcessEnergyRates(watts: 0, wakeupsPerSecond: 0),
            6: ProcessEnergyRates(watts: nil, wakeupsPerSecond: nil),
            1: .missing,
            5: ProcessEnergyRates(watts: 2, wakeupsPerSecond: 1),
        ]

        let display = EnergyPage.display(rows: rows, windowRates: rates, grouped: true)

        let mail = try XCTUnwrap(display.rows.first { $0.name == "Mail" })
        XCTAssertEqual(mail.pid, 20)
        XCTAssertEqual(mail.groupedMemberCount, 3)
        XCTAssertEqual(mail.energyWatts, 7)
        XCTAssertEqual(mail.wakeupsPerSecond, 8)
        let mailReading = try XCTUnwrap(display.readings[20])
        XCTAssertEqual(mailReading.watts ?? -1, 1.5, accuracy: 0.000_001)
        XCTAssertEqual(mailReading.wakeupsPerSecond ?? -1, 4, accuracy: 0.000_001)
        XCTAssertTrue(mailReading.energyReadingIsPartial)
        XCTAssertTrue(mailReading.wakeupReadingIsPartial)
        XCTAssertEqual(ProcessEnergyText.watts(mailReading.watts), "1.5 W")
        XCTAssertEqual(ProcessEnergyText.caption(isPartial: mailReading.energyReadingIsPartial), "部分读数")

        let idle = try XCTUnwrap(display.rows.first { $0.name == "Idle" })
        XCTAssertEqual(idle.pid, 4)
        XCTAssertEqual(idle.groupedMemberCount, 2)
        XCTAssertEqual(idle.energyWatts, 40)
        let idleReading = try XCTUnwrap(display.readings[4])
        XCTAssertEqual(idleReading.watts, 0)
        XCTAssertEqual(idleReading.wakeupsPerSecond, 0)
        XCTAssertTrue(idleReading.energyReadingIsPartial)
        XCTAssertTrue(idleReading.wakeupReadingIsPartial)
        XCTAssertEqual(ProcessEnergyText.watts(idleReading.watts), "0.0 W")
        XCTAssertNotEqual(ProcessEnergyText.watts(idleReading.watts), "—")

        let gone = try XCTUnwrap(display.rows.first { $0.name == "Gone" })
        XCTAssertEqual(gone.pid, 1)
        XCTAssertEqual(gone.groupedMemberCount, 2)
        let goneReading = try XCTUnwrap(display.readings[1])
        XCTAssertNil(goneReading.watts)
        XCTAssertNil(goneReading.wakeupsPerSecond)
        XCTAssertFalse(goneReading.energyReadingIsPartial)
        XCTAssertFalse(goneReading.wakeupReadingIsPartial)
        XCTAssertEqual(ProcessEnergyText.watts(goneReading.watts), "—")
        XCTAssertNotEqual(ProcessEnergyText.watts(goneReading.watts), "0.0 W")

        let alone = try XCTUnwrap(display.rows.first { $0.name == "Solo" })
        XCTAssertEqual(alone.pid, 5)
        XCTAssertEqual(alone.groupedMemberCount, 1)
        XCTAssertEqual(alone.energyWatts, 0)
        let soloReading = try XCTUnwrap(display.readings[5])
        XCTAssertEqual(soloReading.watts, 2)
        XCTAssertEqual(soloReading.wakeupsPerSecond, 1)
        XCTAssertFalse(soloReading.energyReadingIsPartial)
        XCTAssertFalse(soloReading.wakeupReadingIsPartial)

        XCTAssertEqual(display.rows.map(\.pid), [20, 4, 1, 5])
        XCTAssertNil(display.readings[30])
        XCTAssertNil(display.readings[10])
        XCTAssertEqual(rows.map(\.energyWatts), [50, 7, 99, 40, 0, 3, nil, 0])
        XCTAssertEqual(rows.map(\.wakeupsPerSecond), [9, 8, nil, 6, 1, 3, nil, 11])
        XCTAssertTrue(rows.allSatisfy { $0.groupedMemberCount == nil })
    }

    func testGroupedNilWindowRatesSortLastAndIgnoreDecoyWatts() {
        let rows = [
            row(30, "Mail", memory: 200, decoyWatts: 100, decoyWakeups: 100),
            row(20, "Mail", memory: 200, decoyWatts: 7, decoyWakeups: 8),
            row(4, "Idle", memory: 10, decoyWatts: 50, decoyWakeups: 50),
            row(1, "Gone", memory: 9, decoyWatts: 9, decoyWakeups: 9),
            row(5, "Solo", memory: 2, decoyWatts: 0, decoyWakeups: 0),
        ]
        let rates: [Int32: ProcessEnergyRates] = [
            30: ProcessEnergyRates(watts: nil, wakeupsPerSecond: 4),
            20: ProcessEnergyRates(watts: 1.5, wakeupsPerSecond: 0),
            4: ProcessEnergyRates(watts: 0, wakeupsPerSecond: 0),
            1: .missing,
            5: ProcessEnergyRates(watts: 2, wakeupsPerSecond: 1),
        ]
        let descending = EnergyPage.sorted(
            rows,
            windowRates: rates,
            grouped: true,
            sort: ProcessTableSort(column: .energy, descending: true)
        )
        let ascending = EnergyPage.sorted(
            rows,
            windowRates: rates,
            grouped: true,
            sort: ProcessTableSort(column: .energy, descending: false)
        )
        XCTAssertEqual(descending.map(\.name), ["Solo", "Mail", "Idle", "Gone"])
        XCTAssertEqual(ascending.map(\.name), ["Idle", "Mail", "Solo", "Gone"])
        let wakeDescending = EnergyPage.sorted(
            rows,
            windowRates: rates,
            grouped: true,
            sort: ProcessTableSort(column: .wakeups, descending: true)
        )
        XCTAssertEqual(wakeDescending.map(\.name), ["Mail", "Solo", "Idle", "Gone"])
    }

    func testUngroupedDisplayKeepsEachPidWindowRate() throws {
        let rows = [
            row(2, "Mail", memory: 4, decoyWatts: 9, decoyWakeups: 9),
            row(1, "Solo", memory: 1, decoyWatts: nil, decoyWakeups: nil),
        ]
        let rates: [Int32: ProcessEnergyRates] = [
            2: ProcessEnergyRates(watts: 0, wakeupsPerSecond: 3),
            1: .missing,
        ]
        let display = EnergyPage.display(rows: rows, windowRates: rates, grouped: false)
        XCTAssertEqual(display.rows.map(\.pid), [2, 1])
        XCTAssertTrue(display.rows.allSatisfy { $0.groupedMemberCount == nil })
        XCTAssertEqual(display.rows.map(\.energyWatts), [9, nil])
        XCTAssertEqual(display.rates, rates)
        XCTAssertFalse(display.readings[2]?.energyReadingIsPartial ?? true)
        XCTAssertFalse(display.readings[2]?.wakeupReadingIsPartial ?? true)
        XCTAssertNil(display.readings[1]?.watts)
        XCTAssertEqual(display.readings[1]?.wakeupsPerSecond, nil)
    }

    private func row(
        _ pid: Int32,
        _ name: String,
        memory: UInt64,
        decoyWatts: Double?,
        decoyWakeups: Double?
    ) -> ProcessRow {
        ProcessRow(
            pid: pid,
            name: name,
            bundleIdentifier: nil,
            executablePath: nil,
            cpuPercent: 1,
            memoryBytes: memory,
            threadCount: 1,
            energyWatts: decoyWatts,
            wakeupsPerSecond: decoyWakeups
        )
    }
}
