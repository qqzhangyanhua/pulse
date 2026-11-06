import XCTest
@testable import SamplingCore

/// Phase 14 step 2: Darwin-free publish handoff + popover projection wiring.
///
/// Mirrors VM call sites with `DashboardNavigation` + `MemoryPageSortPublication`.
/// Does not instantiate `MemoryDashboardVM`, does not await Sampler, no AppKit.
/// Resource-tab live `tableSort` is not the popover source.
final class MemoryPageSortWiringTests: XCTestCase {
    func testMemoryPageHandoffPublishesFirstAndForwardsTheSameSort() {
        var publication = MemoryPageSortPublication()
        let sort = ProcessTableSort(column: .cpu, descending: true)

        let handoff = publication.publishMemoryPageSort(sort, selectedPage: .memory)

        XCTAssertEqual(publication.sort, sort)
        XCTAssertEqual(handoff, .notifySampler(sort))
        if case .notifySampler(let forwarded) = handoff {
            XCTAssertEqual(forwarded, sort)
            XCTAssertEqual(forwarded, publication.sort)
        } else {
            XCTFail("memory-page publish must forward the same sort to Sampler")
        }
    }

    func testResourceTabHandoffSkipsSamplerAndKeepsTheLastMemorySort() {
        var publication = MemoryPageSortPublication()
        let threads = ProcessTableSort(column: .threads, descending: true)
        XCTAssertEqual(
            publication.publishMemoryPageSort(threads, selectedPage: .memory),
            .notifySampler(threads)
        )

        for page in [DashboardPage.cpu, .network, .disk] {
            let live = ProcessTableSort.defaultSort(for: page)
            let handoff = publication.publishMemoryPageSort(live, selectedPage: page)
            XCTAssertEqual(handoff, .skip, "\(page) must not notify Sampler")
            XCTAssertEqual(publication.sort, threads, "\(page) live tableSort must not write publication")
        }
    }

    func testSetTableSortOnMemoryReordersCopiedRowsWithoutATick() {
        var session = PublishSession(rows: fixtureRows())
        session.start()
        let before = session.menuBarPopover
        XCTAssertEqual(before.processes.map(\.pid), [1, 2, 3])
        XCTAssertEqual(session.lastSamplerSort, ProcessTableSort.defaultSort(for: .memory))

        let nameSort = ProcessTableSort(column: .name, descending: false)
        session.setTableSort(nameSort)

        let after = session.menuBarPopover
        XCTAssertEqual(after.processes.map(\.pid), [4, 5, 1])
        XCTAssertEqual(after.processes.map(\.name), ["alpha", "beta", "chrome"])
        XCTAssertEqual(before.processes.map(\.pid), [1, 2, 3], "previous snapshot copy stays")
        XCTAssertEqual(session.rows.map(\.pid), fixtureRows().map(\.pid), "already-sampled rows are not resampled")
        XCTAssertEqual(session.lastSamplerSort, nameSort)
        XCTAssertEqual(session.publication.sort, nameSort)
        XCTAssertLessThanOrEqual(after.processes.count, MenuBarPopoverShell.maxProcessRows)
    }

    func testSelectResourceTabDoesNotDriveMenuBarWithLiveTableSort() {
        var session = PublishSession(rows: fixtureRows())
        let nameSort = ProcessTableSort(column: .name, descending: false)
        session.setTableSort(nameSort)
        XCTAssertEqual(session.menuBarPopover.processes.map(\.pid), [4, 5, 1])

        session.selectPage(.cpu)
        XCTAssertEqual(session.tableSort, ProcessTableSort.defaultSort(for: .cpu))
        XCTAssertEqual(session.publication.sort, nameSort)
        XCTAssertEqual(session.menuBarPopover.processes.map(\.pid), [4, 5, 1])
        XCTAssertNotEqual(
            session.menuBarPopover.processes.map(\.pid),
            Array(session.tableSort.ordered(session.rows).prefix(3).map(\.pid)),
            "CPU-tab live tableSort must not drive the menu bar"
        )
        XCTAssertEqual(session.lastSamplerSort, nameSort)

        session.selectPage(.network)
        session.selectPage(.disk)
        XCTAssertEqual(session.publication.sort, nameSort)
        XCTAssertEqual(session.menuBarPopover.processes.map(\.pid), [4, 5, 1])
        XCTAssertEqual(session.tableSort, ProcessTableSort.defaultSort(for: .disk))
        XCTAssertEqual(session.lastSamplerSort, nameSort)
    }

    func testReturnToMemoryAndFocusFromAResourceTabUseTheSameGuard() {
        var session = PublishSession(rows: fixtureRows())
        session.setTableSort(ProcessTableSort(column: .threads, descending: true))
        XCTAssertEqual(session.menuBarPopover.processes.map(\.pid), [4, 2, 3])

        session.selectPage(.cpu)
        XCTAssertEqual(session.publication.sort.column, .threads)

        session.selectPage(.memory)
        XCTAssertEqual(session.publication.sort, ProcessTableSort.defaultSort(for: .memory))
        XCTAssertEqual(session.lastSamplerSort, ProcessTableSort.defaultSort(for: .memory))
        XCTAssertEqual(
            session.menuBarPopover.processes.map(\.pid),
            [1, 2, 3],
            "already-sampled rows reorder immediately; no sample() tick"
        )

        session.selectPage(.network)
        session.focusMemoryPage()
        XCTAssertEqual(session.selectedPage, .memory)
        XCTAssertEqual(session.publication.sort, ProcessTableSort.defaultSort(for: .memory))
        XCTAssertEqual(session.menuBarPopover.processes.map(\.pid), [1, 2, 3])
        XCTAssertEqual(session.lastSamplerSort, ProcessTableSort.defaultSort(for: .memory))
    }

    func testFocusMemoryPageAlreadyOnMemoryDoesNotChangePublication() {
        var session = PublishSession(rows: fixtureRows())
        let threads = ProcessTableSort(column: .threads, descending: true)
        session.setTableSort(threads)
        session.focusMemoryPage()
        XCTAssertEqual(session.selectedPage, .memory)
        XCTAssertEqual(session.publication.sort, threads)
        XCTAssertEqual(session.tableSort, threads)
        XCTAssertEqual(session.menuBarPopover.processes.map(\.pid), [4, 2, 3])
        XCTAssertEqual(session.lastSamplerSort, threads)
    }

    func testStartOnMemoryPublishesDefaultAndStartOffMemoryDoesNotReset() {
        var onMemory = PublishSession(rows: fixtureRows())
        onMemory.start()
        XCTAssertEqual(onMemory.selectedPage, .memory)
        XCTAssertEqual(onMemory.publication.sort, ProcessTableSort.defaultSort(for: .memory))
        XCTAssertEqual(onMemory.lastSamplerSort, ProcessTableSort.defaultSort(for: .memory))
        XCTAssertEqual(onMemory.menuBarPopover.processes.map(\.pid), [1, 2, 3])

        var offMemory = PublishSession(rows: fixtureRows())
        let threads = ProcessTableSort(column: .threads, descending: true)
        offMemory.setTableSort(threads)
        offMemory.selectPage(.cpu)
        offMemory.lastSamplerSort = nil
        offMemory.start()
        XCTAssertEqual(offMemory.publication.sort, threads)
        XCTAssertNil(offMemory.lastSamplerSort, "start() must not unconditionally rewrite publication")
        XCTAssertEqual(offMemory.menuBarPopover.processes.map(\.pid), [4, 2, 3])
    }

    func testPopoverProjectionIgnoresNameFilterAndRisingOnly() {
        var session = PublishSession(rows: fixtureRows())
        session.setTableSort(ProcessTableSort.defaultSort(for: .memory))
        session.filter = "xcode"
        session.risingOnly = true

        let filtered = ProcessNameFilter.apply(session.rows, query: session.filter)
        XCTAssertEqual(filtered.map(\.pid), [2])
        XCTAssertEqual(session.menuBarPopover.processes.map(\.pid), [1, 2, 3])
        XCTAssertNotEqual(
            session.menuBarPopover.processes.map(\.pid),
            Array(filtered.prefix(3).map(\.pid))
        )
    }

    func testProcessListFailedStillDropsRowsAfterANonMemoryHandoff() {
        var session = PublishSession(rows: fixtureRows(), processListFailed: true)
        session.setTableSort(ProcessTableSort(column: .cpu, descending: true))
        XCTAssertTrue(session.menuBarPopover.processes.isEmpty)
        XCTAssertEqual(session.menuBarPopover.processesEmptyCopy, MenuBarCopy.processesEmpty)
    }

    /// Call-site stand-in for the four VM entries. Not `MemoryDashboardVM`.
    private struct PublishSession {
        var navigation = DashboardNavigation()
        var publication = MemoryPageSortPublication()
        var rows: [ProcessRow]
        var processListFailed = false
        var filter = ""
        var risingOnly = false
        var lastSamplerSort: ProcessTableSort?

        var selectedPage: DashboardPage { navigation.selectedPage }
        var tableSort: ProcessTableSort { navigation.sort }

        var menuBarPopover: MenuBarPopoverSnapshot {
            _ = (filter, risingOnly)
            return MenuBarPopoverSnapshot.project(
                pressure: .normal,
                usedBytes: nil,
                samplingFailed: false,
                rows: rows,
                processListFailed: processListFailed,
                sort: publication.sort
            )
        }

        mutating func setTableSort(_ sort: ProcessTableSort) {
            navigation.updateSort(sort)
            publishMemoryPageSort()
        }

        mutating func selectPage(_ page: DashboardPage) {
            navigation.select(page)
            publishMemoryPageSort()
        }

        mutating func focusMemoryPage() {
            navigation.focusMemoryPage()
            publishMemoryPageSort()
        }

        mutating func start() {
            publishMemoryPageSort()
        }

        mutating func publishMemoryPageSort() {
            switch publication.publishMemoryPageSort(tableSort, selectedPage: selectedPage) {
            case .notifySampler(let sort):
                lastSamplerSort = sort
            case .skip:
                break
            }
        }
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
