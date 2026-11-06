import XCTest
@testable import SamplingCore

/// Phase 14 step 1: Darwin-free memory-page sort publication + `project(sort:)`.
/// No VM, no Sampler, no AppKit. Resource-tab live `tableSort` is not the source.
final class MemoryPageSortPublicationTests: XCTestCase {
    func testDefaultPublicationIsMemoryDescending() {
        let publication = MemoryPageSortPublication()
        XCTAssertEqual(publication.sort, ProcessTableSort.defaultSort(for: .memory))
        XCTAssertEqual(publication.sort.column, .memory)
        XCTAssertTrue(publication.sort.descending)
    }

    func testProjectSortMatchesOrderedPrefixThreeForMemoryPageColumns() {
        let rows = fixtureRows()
        let sorts: [ProcessTableSort] = [
            ProcessTableSort.defaultSort(for: .memory),
            ProcessTableSort(column: .memory, descending: false),
            ProcessTableSort(column: .cpu, descending: true),
            ProcessTableSort(column: .cpu, descending: false),
            ProcessTableSort(column: .name, descending: false),
            ProcessTableSort(column: .name, descending: true),
            ProcessTableSort(column: .threads, descending: true),
            ProcessTableSort(column: .threads, descending: false),
        ]
        for sort in sorts {
            let strip = project(rows: rows, sort: sort)
            XCTAssertEqual(
                strip.processes.map(\.pid),
                Array(sort.ordered(rows).prefix(MenuBarPopoverShell.maxProcessRows).map(\.pid)),
                "\(sort.column) descending=\(sort.descending)"
            )
            XCTAssertLessThanOrEqual(strip.processes.count, MenuBarPopoverShell.maxProcessRows)
            XCTAssertEqual(strip.processes.map(\.name), Array(sort.ordered(rows).prefix(3).map(\.name)))
            XCTAssertEqual(
                strip.processes.map(\.memoryBytes),
                Array(sort.ordered(rows).prefix(3).map(\.memoryBytes))
            )
        }
    }

    func testNonMemoryColumnsCanDifferFromTheThreeLargestMemoryRows() {
        let rows = fixtureRows()
        let memoryTop = project(rows: rows, sort: .defaultSort(for: .memory)).processes.map(\.pid)
        XCTAssertEqual(memoryTop, [1, 2, 3])

        let cpuTop = project(
            rows: rows,
            sort: ProcessTableSort(column: .cpu, descending: true)
        ).processes.map(\.pid)
        XCTAssertEqual(cpuTop, [2, 4, 1])
        XCTAssertNotEqual(cpuTop, memoryTop)

        let nameTop = project(
            rows: rows,
            sort: ProcessTableSort(column: .name, descending: false)
        ).processes.map(\.pid)
        XCTAssertEqual(nameTop, [4, 5, 1])
        XCTAssertNotEqual(nameTop, memoryTop)

        let threadTop = project(
            rows: rows,
            sort: ProcessTableSort(column: .threads, descending: true)
        ).processes.map(\.pid)
        XCTAssertEqual(threadTop, [4, 2, 3])
        XCTAssertNotEqual(threadTop, memoryTop)
    }

    func testOmittingSortKeepsTheMemoryDescendingDefault() {
        let rows = fixtureRows()
        let explicit = MenuBarPopoverSnapshot.project(
            pressure: .normal,
            usedBytes: nil,
            samplingFailed: false,
            rows: rows,
            processListFailed: false,
            sort: ProcessTableSort.defaultSort(for: .memory)
        )
        let omitted = MenuBarPopoverSnapshot.project(
            pressure: .normal,
            usedBytes: nil,
            samplingFailed: false,
            rows: rows,
            processListFailed: false
        )
        XCTAssertEqual(explicit.processes.map(\.pid), omitted.processes.map(\.pid))
        XCTAssertEqual(omitted.processes.map(\.pid), [1, 2, 3])
    }

    func testNameFilterOnOffDoesNotChangeProjectedPids() {
        let rows = fixtureRows()
        let sort = ProcessTableSort.defaultSort(for: .memory)
        let filtered = ProcessNameFilter.apply(rows, query: "xcode")
        XCTAssertEqual(filtered.map(\.pid), [2])

        let off = project(rows: rows, sort: sort)
        let on = project(rows: rows, sort: sort)
        XCTAssertEqual(off.processes.map(\.pid), on.processes.map(\.pid))
        XCTAssertEqual(off.processes.map(\.pid), [1, 2, 3])
        XCTAssertNotEqual(off.processes.map(\.pid), Array(filtered.prefix(3).map(\.pid)))
    }

    func testRisingOnlyOnOffDoesNotChangeProjectedPids() {
        let rows = fixtureRows()
        let sort = ProcessTableSort.defaultSort(for: .memory)
        let seriesByPid: [Int32: [ChartSample]] = [2: risingSeries()]
        let rising = MemoryGrowthRisingFilter.apply(
            rows: rows,
            nameQuery: "",
            page: .memory,
            risingOnly: true,
            seriesByPid: seriesByPid
        )
        XCTAssertEqual(rising.map(\.pid), [2])

        let off = project(rows: rows, sort: sort)
        let on = project(rows: rows, sort: sort)
        XCTAssertEqual(off.processes.map(\.pid), on.processes.map(\.pid))
        XCTAssertEqual(off.processes.map(\.pid), [1, 2, 3])
        XCTAssertNotEqual(off.processes.map(\.pid), Array(rising.prefix(3).map(\.pid)))
    }

    func testPublicationUpdatesOnlyOnMemoryPageAndResourceTabsKeepTheLastMemorySort() {
        let rows = fixtureRows()
        var publication = MemoryPageSortPublication()
        XCTAssertEqual(
            project(rows: rows, sort: publication.sort).processes.map(\.pid),
            [1, 2, 3]
        )

        let nameSort = ProcessTableSort(column: .name, descending: false)
        publication.publish(nameSort, selectedPage: .memory)
        XCTAssertEqual(publication.sort, nameSort)
        XCTAssertEqual(
            project(rows: rows, sort: publication.sort).processes.map(\.pid),
            [4, 5, 1]
        )

        let liveCPU = ProcessTableSort.defaultSort(for: .cpu)
        publication.publish(liveCPU, selectedPage: .cpu)
        XCTAssertEqual(publication.sort, nameSort)
        XCTAssertEqual(
            project(rows: rows, sort: publication.sort).processes.map(\.pid),
            [4, 5, 1],
            "CPU-tab live tableSort must not drive the menu bar"
        )
        XCTAssertNotEqual(
            project(rows: rows, sort: publication.sort).processes.map(\.pid),
            Array(liveCPU.ordered(rows).prefix(3).map(\.pid))
        )

        publication.publish(ProcessTableSort.defaultSort(for: .network), selectedPage: .network)
        publication.publish(ProcessTableSort.defaultSort(for: .disk), selectedPage: .disk)
        XCTAssertEqual(publication.sort, nameSort)
        XCTAssertEqual(
            project(rows: rows, sort: publication.sort).processes.map(\.pid),
            [4, 5, 1]
        )
    }

    func testReturningToMemoryRewritesPublicationAndReordersExistingRowsWithoutATick() {
        let rows = fixtureRows()
        var publication = MemoryPageSortPublication()
        publication.publish(ProcessTableSort(column: .threads, descending: true), selectedPage: .memory)
        XCTAssertEqual(
            project(rows: rows, sort: publication.sort).processes.map(\.pid),
            [4, 2, 3]
        )

        publication.publish(ProcessTableSort.defaultSort(for: .cpu), selectedPage: .cpu)
        XCTAssertEqual(publication.sort.column, .threads)

        let sameRows = rows
        publication.publish(ProcessTableSort.defaultSort(for: .memory), selectedPage: .memory)
        XCTAssertEqual(publication.sort, ProcessTableSort.defaultSort(for: .memory))
        XCTAssertEqual(
            project(rows: sameRows, sort: publication.sort).processes.map(\.pid),
            [1, 2, 3],
            "already-sampled rows reorder immediately; no sample() tick"
        )
    }

    func testStartOnANonMemoryPageDoesNotResetPublicationToDefault() {
        var publication = MemoryPageSortPublication()
        let threads = ProcessTableSort(column: .threads, descending: true)
        publication.publish(threads, selectedPage: .memory)
        XCTAssertEqual(publication.sort, threads)

        publication.publish(ProcessTableSort.defaultSort(for: .memory), selectedPage: .cpu)
        XCTAssertEqual(publication.sort, threads)

        publication.publish(ProcessTableSort.defaultSort(for: .cpu), selectedPage: .cpu)
        XCTAssertEqual(publication.sort, threads, "start() must not unconditionally rewrite publication")
        XCTAssertEqual(
            project(rows: fixtureRows(), sort: publication.sort).processes.map(\.pid),
            [4, 2, 3]
        )
    }

    func testProcessListFailedStillDropsRowsForANonMemorySort() {
        let strip = MenuBarPopoverSnapshot.project(
            pressure: .normal,
            usedBytes: 4_294_967_296,
            samplingFailed: false,
            rows: fixtureRows(),
            processListFailed: true,
            sort: ProcessTableSort(column: .cpu, descending: true)
        )
        XCTAssertTrue(strip.processes.isEmpty)
        XCTAssertEqual(strip.processesEmptyCopy, MenuBarCopy.processesEmpty)
        XCTAssertEqual(strip.pressure, .normal)
    }

    private func project(rows: [ProcessRow], sort: ProcessTableSort) -> MenuBarPopoverSnapshot {
        MenuBarPopoverSnapshot.project(
            pressure: .normal,
            usedBytes: nil,
            samplingFailed: false,
            rows: rows,
            processListFailed: false,
            sort: sort
        )
    }

    /// Memory desc 1,2,3; CPU desc 2,4,1; name asc 4,5,1; threads desc 4,2,3.
    private func fixtureRows() -> [ProcessRow] {
        [
            process(pid: 1, name: "chrome", cpu: 10, memory: 800, threads: 2),
            process(pid: 2, name: "xcode", cpu: 50, memory: 500, threads: 8),
            process(pid: 3, name: "mail", cpu: 5, memory: 200, threads: 4),
            process(pid: 4, name: "alpha", cpu: 40, memory: 100, threads: 16),
            process(pid: 5, name: "beta", cpu: 1, memory: 50, threads: 1),
        ]
    }

    private func risingSeries() -> [ChartSample] {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        return (0..<MemoryGrowthSignal.minSamples).map { index in
            ChartSample(
                id: UInt64(index + 1),
                date: start.addingTimeInterval(Double(index) * 1.5),
                value: 200_000_000 + Double(index) * 1_048_576
            )
        }
    }

    private func process(
        pid: Int32,
        name: String,
        cpu: Double?,
        memory: UInt64,
        threads: Int
    ) -> ProcessRow {
        ProcessRow(
            pid: pid,
            name: name,
            bundleIdentifier: nil,
            executablePath: nil,
            cpuPercent: cpu,
            memoryBytes: memory,
            threadCount: threads
        )
    }
}
