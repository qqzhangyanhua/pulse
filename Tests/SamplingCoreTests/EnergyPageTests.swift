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
