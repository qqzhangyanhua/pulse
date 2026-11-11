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
