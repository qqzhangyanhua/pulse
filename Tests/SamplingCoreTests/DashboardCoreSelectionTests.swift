import XCTest
@testable import SamplingCore

/// Selection, page, sort, and filter transitions on `DashboardCore`.
final class DashboardCoreSelectionTests: XCTestCase {
    func testClearingFiltersResetsTheThreeFieldsAndKeepsTheSelectedProcess() {
        var core = DashboardCore(ownPid: 1)
        accept(&core, rows: [row(4, "Mail", memory: 80, cpu: 1)], series: [4: risingSeries()])
        _ = core.select(pid: 4)
        _ = core.setFilter("Mail")
        _ = core.setRisingOnly(true)
        _ = core.setWindowedOnly(true, windowedPids: [4])
        _ = core.setGroupedByApp(true)

        let effects = core.clearMemoryPageFilters()

        XCTAssertEqual(effects, [])
        XCTAssertEqual(core.filter, "")
        XCTAssertFalse(core.risingOnlyFilter)
        XCTAssertFalse(core.windowedOnlyFilter)
        XCTAssertTrue(core.groupedByApp)
        XCTAssertEqual(core.selectedPid, 4)
    }

    func testLeavingTheMemoryPageKeepsTheMenuBarOnTheMemoryPageSort() {
        var core = DashboardCore(ownPid: 1)
        accept(&core, rows: [
            row(2, "Alpha", memory: 50, cpu: 1),
            row(3, "Middle", memory: 200, cpu: 50),
            row(1, "Zebra", memory: 100, cpu: 10),
        ])
        XCTAssertEqual(core.menuBarPopover.processes.map(\.pid), [3, 1, 2])

        let nameSort = ProcessTableSort(column: .name, descending: false)
        XCTAssertEqual(core.setTableSort(nameSort), [.forwardMemoryPageSort(nameSort)])
        XCTAssertEqual(core.menuBarPopover.processes.map(\.pid), [2, 3, 1])

        let left = core.selectPage(.cpu)
        XCTAssertFalse(left.contains(.forwardMemoryPageSort(nameSort)))
        XCTAssertFalse(left.contains(.forwardMemoryPageSort(ProcessTableSort.defaultSort(for: .cpu))))
        XCTAssertEqual(core.tableSort, ProcessTableSort.defaultSort(for: .cpu))
        XCTAssertEqual(core.setTableSort(nameSort), [])
        XCTAssertEqual(core.menuBarPopover.processes.map(\.pid), [2, 3, 1])
    }

    func testPageSwitchReturnsSortGPUAndWatchEffects() {
        var core = DashboardCore(ownPid: 1)
        let nameSort = ProcessTableSort(column: .name, descending: false)
        XCTAssertEqual(core.setTableSort(nameSort), [.forwardMemoryPageSort(nameSort)])

        XCTAssertEqual(core.selectPage(.memory), [
            .forwardMemoryPageSort(nameSort),
            .setGPUSampling(on: false),
            .stopMachineWatch,
            .stopEnergyBatteryWatch,
        ])
        XCTAssertEqual(core.tableSort, nameSort)

        XCTAssertEqual(core.selectPage(.energy), [
            .setGPUSampling(on: false),
            .stopMachineWatch,
            .startEnergyBatteryWatch,
        ])
        XCTAssertEqual(core.selectPage(.gpu), [
            .setGPUSampling(on: true),
            .stopMachineWatch,
            .stopEnergyBatteryWatch,
        ])
        XCTAssertEqual(core.selectPage(.machine), [
            .setGPUSampling(on: false),
            .startMachineWatch,
            .stopEnergyBatteryWatch,
        ])
        XCTAssertEqual(core.focusMemoryPage(), [
            .forwardMemoryPageSort(ProcessTableSort.defaultSort(for: .memory)),
            .setGPUSampling(on: false),
            .stopMachineWatch,
            .stopEnergyBatteryWatch,
        ])
    }

    func testAFilterThatHidesTheSelectedProcessKeepsANameMissAndClearsRisingOrWindowed() {
        var core = DashboardCore(ownPid: 1)
        accept(&core, rows: [
            row(10, "Mail", memory: 100, cpu: 1),
            row(20, "Notes", memory: 40, cpu: 2),
        ])
        _ = core.select(pid: 10)
        _ = core.setFilter("zzz")

        XCTAssertEqual(core.selectedPid, 10)
        XCTAssertTrue(core.visibleRows.isEmpty)
        XCTAssertEqual(core.selectedRow?.pid, 10)

        _ = core.setFilter("")
        XCTAssertEqual(core.setRisingOnly(true), [.forwardSelectedPid(nil)])
        XCTAssertNil(core.selectedPid)
        XCTAssertTrue(core.visibleRows.isEmpty)

        _ = core.setRisingOnly(false)
        _ = core.select(pid: 10)
        XCTAssertEqual(
            core.setWindowedOnly(true, windowedPids: [20]),
            [.forwardSelectedPid(nil)]
        )
        XCTAssertNil(core.selectedPid)
        XCTAssertEqual(core.visibleRows.map(\.pid), [20])
    }

    func testWindowedFilteringUsesThePassedInSet() {
        var core = DashboardCore(ownPid: 1)
        accept(&core, rows: [
            row(4, "Mail", memory: 10, cpu: 1),
            row(8, "Notes", memory: 20, cpu: 1),
        ])
        _ = core.select(pid: 8)
        XCTAssertEqual(core.setWindowedOnly(true, windowedPids: [8]), [])
        XCTAssertEqual(core.visibleRows.map(\.pid), [8])
        XCTAssertEqual(core.selectedPid, 8)

        core.windowedPids = [4]
        XCTAssertEqual(core.visibleRows.map(\.pid), [4])
        XCTAssertEqual(core.applyWindowedOnlySelection(), [.forwardSelectedPid(nil)])
        XCTAssertNil(core.selectedPid)
    }

    func testTreeFocusUsesTheLiveDecisionSetAndLeavesTheStoredWindowedPids() {
        var kept = DashboardCore(ownPid: 1)
        accept(&kept, rows: [
            row(4, "Mail", memory: 10, cpu: 1),
            row(9, "Notes", memory: 20, cpu: 1),
        ])
        _ = kept.setWindowedOnly(true, windowedPids: [9])

        _ = kept.focusProcessFromTree(4, decisionWindowedPids: [4, 9])

        XCTAssertTrue(kept.windowedOnlyFilter)
        XCTAssertEqual(kept.windowedPids, Set<Int32>([9]))

        var cleared = DashboardCore(ownPid: 1)
        accept(&cleared, rows: [
            row(4, "Mail", memory: 10, cpu: 1),
            row(9, "Notes", memory: 20, cpu: 1),
        ])
        _ = cleared.setWindowedOnly(true, windowedPids: [9])

        _ = cleared.focusProcessFromTree(4, decisionWindowedPids: [9])

        XCTAssertFalse(cleared.windowedOnlyFilter)
        XCTAssertEqual(cleared.windowedPids, Set<Int32>([9]))
    }

    func testSelectingAMissingPidCorrectsOnceWithoutCaptureOrForward() {
        var core = DashboardCore(ownPid: 1)
        _ = core.selectPage(.energy)
        accept(&core, rows: [row(20, "Mail", memory: 80, cpu: 1)], generations: [20: 9, 99: 4])
        let legal = core.select(pid: 20)
        XCTAssertEqual(legal, [.forwardSelectedPid(20)])
        XCTAssertNil(core.detail)
        XCTAssertEqual(core.selectedEnergyGeneration, 9)
        XCTAssertEqual(core.sidebarSubjectPid, 20)
        core.detail = ProcessDetail(row: row(20, "Mail", memory: 80, cpu: 1), memorySeries: [], cpuSeries: [])

        let again = core.select(pid: 20)
        XCTAssertEqual(again, [])
        XCTAssertEqual(core.detail?.row.pid, 20)
        XCTAssertEqual(core.selectedEnergyGeneration, 9)

        let corrected = core.select(pid: 99)
        XCTAssertEqual(corrected, [])
        XCTAssertNil(core.selectedPid)
        XCTAssertEqual(core.detail?.row.pid, 20)
        XCTAssertEqual(core.selectedEnergyGeneration, 9)
        XCTAssertEqual(core.sidebarSubjectPid, 20)
        XCTAssertFalse(corrected.contains(.forwardSelectedPid(99)))
        XCTAssertFalse(corrected.contains(.forwardSelectedPid(nil)))
    }

    private func accept(
        _ core: inout DashboardCore,
        rows: [ProcessRow],
        series: [Int32: [ChartSample]] = [:],
        generations: [Int32: Int] = [:]
    ) {
        let capturedAt = Date(timeIntervalSince1970: 1_700_000_000)
        let snapshot = MemorySnapshot(
            usedBytes: 1_000,
            totalBytes: 4_000,
            breakdown: MemoryBreakdown(
                appBytes: 1,
                wiredBytes: 1,
                compressedBytes: 1,
                cachedBytes: 1
            ),
            pressure: .normal,
            pressureMetric: 0.1,
            pressureSeries: [],
            capturedAt: capturedAt,
            swapUsedBytes: 0
        )
        let frame = SampledFrame(
            snapshot: snapshot,
            rows: rows,
            detail: nil,
            processListFailed: false,
            systemCpuPercent: 1,
            hostNetworkRates: .missing,
            hostDiskRates: .missing,
            topMemorySeries: series,
            energyLiveGenerations: generations
        )
        _ = core.apply(
            result: Result<SampledFrame, SelectionDeliveryError>.success(frame),
            accepted: true,
            page: core.selectedPage,

        )
    }

    private func row(_ pid: Int32, _ name: String, memory: UInt64, cpu: Double) -> ProcessRow {
        ProcessRow(
            pid: pid,
            name: name,
            bundleIdentifier: nil,
            executablePath: nil,
            cpuPercent: cpu,
            memoryBytes: memory,
            threadCount: 1
        )
    }

    private func risingSeries() -> [ChartSample] {
        (0..<MemoryGrowthSignal.minSamples).map { index in
            ChartSample(
                id: UInt64(index + 1),
                date: Date(timeIntervalSince1970: TimeInterval(index)),
                value: Double(index) * 1_048_576
            )
        }
    }
}

private enum SelectionDeliveryError: Error {
    case unavailable
}
