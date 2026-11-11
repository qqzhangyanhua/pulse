import XCTest
@testable import SamplingCore

/// Top3 process-row schedule. A pass is not a Mac window, scroll, or VoiceOver pass.
final class Top3ProcessTapTests: XCTestCase {
    func testProcessTapOfPid4StaysSelectedWhenRisingOnlyHasNoBadge() {
        let host = Top3TapFixture()
        host.rows = [row(4, "Notes", 100), row(9, "Mail", 50)]
        host.risingOnlyFilter = true
        host.topMemorySeries = [:]
        host.navigation = DashboardNavigation(page: MenuBarNavigation(selectedPage: .memory))
        var dismisses = 0
        var activations = 0

        let schedule = Top3ProcessTap.perform(
            pid: 4,
            host: host,
            dismiss: { dismisses += 1 },
            activate: { activations += 1 }
        )

        XCTAssertEqual(host.selectedPid, 4)
        XCTAssertEqual(host.pageSwitches, 1)
        XCTAssertEqual(schedule.pageSwitches, 1)
        XCTAssertEqual(activations, 1)
        XCTAssertEqual(schedule.activations, 1)
        XCTAssertEqual(schedule.openPulseCalls, 0)
        XCTAssertEqual(dismisses, 1)
    }

    func testBlockingFiltersChangeOnlyWhenTheyHideThePid() {
        let blocked = fixture(rows: [row(4, "Notes", 100), row(2, "Safari", 80)])
        blocked.filter = "Safari"
        blocked.risingOnlyFilter = true
        blocked.windowedOnlyFilter = true
        blocked.windowedPids = [2]
        blocked.groupedByApp = true
        _ = tap(4, on: blocked)
        XCTAssertEqual(blocked.selectedPid, 4)
        XCTAssertEqual(blocked.filter, "")
        XCTAssertFalse(blocked.filter == "Notes")
        XCTAssertFalse(blocked.risingOnlyFilter)
        XCTAssertFalse(blocked.windowedOnlyFilter)
        XCTAssertTrue(blocked.groupedByApp)

        let matching = fixture(rows: [row(4, "Notes", 100)])
        matching.filter = "note"
        _ = tap(4, on: matching)
        XCTAssertEqual(matching.selectedPid, 4)
        XCTAssertEqual(matching.filter, "note")

        let blank = fixture(rows: [row(4, "Notes", 100)])
        blank.filter = "   "
        _ = tap(4, on: blank)
        XCTAssertEqual(blank.selectedPid, 4)
        XCTAssertEqual(blank.filter, "   ")

        let rising = fixture(rows: [row(4, "Notes", 100)])
        rising.risingOnlyFilter = true
        rising.topMemorySeries = [4: risingSeries()]
        XCTAssertNotNil(
            MemoryGrowthList.badge(page: .memory, rowPid: 4, seriesByPid: rising.topMemorySeries)
        )
        _ = tap(4, on: rising)
        XCTAssertEqual(rising.selectedPid, 4)
        XCTAssertTrue(rising.risingOnlyFilter)

        let windowed = fixture(rows: [row(4, "Notes", 100)])
        windowed.windowedOnlyFilter = true
        windowed.windowedPids = [4]
        _ = tap(4, on: windowed)
        XCTAssertEqual(windowed.selectedPid, 4)
        XCTAssertTrue(windowed.windowedOnlyFilter)

        let windowBlocked = fixture(rows: [row(4, "Notes", 100)])
        windowBlocked.windowedOnlyFilter = true
        windowBlocked.risingOnlyFilter = false
        _ = tap(4, on: windowBlocked)
        XCTAssertEqual(windowBlocked.selectedPid, 4)
        XCTAssertFalse(windowBlocked.windowedOnlyFilter)
        XCTAssertFalse(windowBlocked.risingOnlyFilter)
    }

    func testMissingPidDoesNotPrepareOrSubstitute() {
        let host = fixture(rows: [row(4, "Notes", 100), row(8, "Notes", 80)])
        host.selectedPid = 4
        host.filter = "zzz"
        host.risingOnlyFilter = true
        host.windowedOnlyFilter = true
        host.groupedByApp = true
        var activations = 0
        let schedule = Top3ProcessTap.perform(
            pid: 99,
            host: host,
            dismiss: {},
            activate: { activations += 1 }
        )
        XCTAssertNotEqual(host.selectedPid, 99)
        XCTAssertNotEqual(host.selectedPid, 8)
        XCTAssertEqual(host.filter, "zzz")
        XCTAssertTrue(host.risingOnlyFilter)
        XCTAssertTrue(host.windowedOnlyFilter)
        XCTAssertTrue(host.groupedByApp)
        XCTAssertEqual(host.pageSwitches, 1)
        XCTAssertEqual(activations, 1)
        XCTAssertEqual(schedule.openPulseCalls, 0)
        XCTAssertEqual(schedule.pageSwitches, 1)
    }

    func testSortFollowsTheExistingFocusRule() {
        let fromCPU = fixture(rows: [row(4, "Notes", 100)])
        fromCPU.navigation = DashboardNavigation(
            page: MenuBarNavigation(selectedPage: .cpu),
            sort: ProcessTableSort(column: .name, descending: false)
        )
        _ = tap(4, on: fromCPU)
        XCTAssertEqual(fromCPU.navigation.selectedPage, .memory)
        XCTAssertEqual(fromCPU.navigation.sort, ProcessTableSort.defaultSort(for: .memory))
        XCTAssertEqual(fromCPU.pageSwitches, 1)

        let onMemory = fixture(rows: [row(4, "Notes", 100)])
        let kept = ProcessTableSort(column: .name, descending: false)
        onMemory.navigation = DashboardNavigation(
            page: MenuBarNavigation(selectedPage: .memory),
            sort: kept
        )
        _ = tap(4, on: onMemory)
        XCTAssertEqual(onMemory.navigation.sort, kept)
        XCTAssertEqual(onMemory.selectedPid, 4)
        XCTAssertEqual(onMemory.pageSwitches, 1)
    }

    func testGroupedRevealUsesTheRepresentativeAndSelectionStaysTheTappedPid() {
        let host = fixture(rows: [row(9, "Chrome", 100), row(4, "Chrome", 250)])
        host.groupedByApp = true
        _ = tap(9, on: host)
        XCTAssertEqual(host.selectedPid, 9)
        XCTAssertTrue(host.groupedByApp)
        let revealed = MemoryRevealGroupRow.target(
            scrollTarget: host.selectedPid,
            page: host.navigation.selectedPage,
            grouping: host.groupedByApp,
            visibleUngrouped: host.rows
        )
        XCTAssertEqual(revealed, 4)
        XCTAssertNotEqual(revealed, host.selectedPid)
    }

    func testOpenPulseCallsTheSharedEntryOnceAndDoesNotPrepare() {
        let host = fixture(rows: [row(4, "Notes", 100)])
        host.filter = "keep"
        host.risingOnlyFilter = true
        host.selectedPid = 4
        var opens = 0
        var dismisses = 0
        let schedule = MenuBarOpenPulseTap.perform(
            dismiss: { dismisses += 1 },
            openPulse: { opens += 1 }
        )
        XCTAssertEqual(opens, 1)
        XCTAssertEqual(dismisses, 1)
        XCTAssertEqual(schedule.openPulseCalls, 1)
        XCTAssertEqual(schedule.activations, 0)
        XCTAssertEqual(host.filter, "keep")
        XCTAssertTrue(host.risingOnlyFilter)
        XCTAssertEqual(host.selectedPid, 4)
        XCTAssertEqual(host.pageSwitches, 0)
    }

    func testSharedRisingGateStillClearsAPidWithNoBadge() {
        XCTAssertNil(
            MemoryGrowthRisingFilter.selectedPid(
                current: 4,
                rows: [row(4, "Notes", 100)],
                nameQuery: "",
                page: .memory,
                risingOnly: true,
                seriesByPid: [:]
            )
        )
    }

    private func tap(_ pid: Int32, on host: Top3TapFixture) -> Top3ProcessTap.Schedule {
        Top3ProcessTap.perform(pid: pid, host: host, dismiss: {}, activate: {})
    }

    private func fixture(rows: [ProcessRow]) -> Top3TapFixture {
        let host = Top3TapFixture()
        host.rows = rows
        host.navigation = DashboardNavigation(page: MenuBarNavigation(selectedPage: .memory))
        return host
    }

    private func risingSeries() -> [ChartSample] {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        return (0..<MemoryGrowthSignal.minSamples).map { index in
            ChartSample(
                id: UInt64(index + 1),
                date: start.addingTimeInterval(Double(index)),
                value: 200_000_000 + Double(index) * 1_048_576
            )
        }
    }

    private func row(_ pid: Int32, _ name: String, _ bytes: UInt64) -> ProcessRow {
        ProcessRow(
            pid: pid,
            name: name,
            bundleIdentifier: nil,
            executablePath: nil,
            cpuPercent: nil,
            memoryBytes: bytes,
            threadCount: 1
        )
    }
}

final class Top3TapFixture: Top3TapHost {
    var selectedPid: Int32?
    var rows: [ProcessRow] = []
    var filter = ""
    var risingOnlyFilter = false
    var windowedOnlyFilter = false
    var groupedByApp = false
    var navigation = DashboardNavigation()
    var topMemorySeries: [Int32: [ChartSample]] = [:]
    var windowedPids: Set<Int32> = []
    var pageSwitches = 0

    func selectPidIfPresent(_ pid: Int32) {
        if let accepted = ProcessSelection.acceptedPid(pid, in: rows) {
            selectedPid = accepted
        }
    }

    /// Same list-selection effect as `MemoryDashboardVM.focusMemoryPage`.
    /// Sort publication and the machine-page watch do not change `selectedPid`.
    func focusMemoryPage() {
        pageSwitches += 1
        navigation.focusMemoryPage()
        selectedPid = MemoryGrowthRisingFilter.selectedPid(
            current: selectedPid,
            rows: rows,
            nameQuery: filter,
            page: navigation.selectedPage,
            risingOnly: risingOnlyFilter,
            seriesByPid: topMemorySeries
        )
        selectedPid = WindowedAppFilter.selectedPid(
            current: selectedPid,
            page: navigation.selectedPage,
            windowedOnly: windowedOnlyFilter,
            windowedPids: { self.windowedPids }
        )
    }
}
