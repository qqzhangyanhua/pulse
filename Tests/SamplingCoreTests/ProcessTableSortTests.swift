import XCTest
@testable import SamplingCore

/// Phase 14 step 1: shared `ProcessTableSort.ordered` pid-ascending tie-break.
/// Not a second comparator. Does not add a PID column.
final class ProcessTableSortTests: XCTestCase {
    func testEqualNameBreaksTiesByPidAscendingAndDescendingDoesNotFlipTheTie() {
        let rows = [
            process(pid: 30, name: "Same"),
            process(pid: 10, name: "Same"),
            process(pid: 20, name: "Same"),
        ]
        let ascending = ProcessTableSort(column: .name, descending: false)
        let descending = ProcessTableSort(column: .name, descending: true)
        XCTAssertEqual(ascending.ordered(rows).map(\.pid), [10, 20, 30])
        XCTAssertEqual(descending.ordered(rows).map(\.pid), [10, 20, 30])
    }

    func testEqualNameKeepsPidAscendingUnderAMixedNameDescendingSort() {
        let rows = [
            process(pid: 30, name: "A"),
            process(pid: 10, name: "A"),
            process(pid: 20, name: "B"),
        ]
        let descending = ProcessTableSort(column: .name, descending: true)
        XCTAssertEqual(descending.ordered(rows).map(\.pid), [20, 10, 30])
        XCTAssertEqual(descending.ordered(rows).map(\.name), ["B", "A", "A"])
    }

    func testEqualCPUBreaksTiesByPidAscendingAndDescendingDoesNotFlipTheTie() {
        let rows = [
            process(pid: 30, name: "c", cpu: 5),
            process(pid: 10, name: "a", cpu: 5),
            process(pid: 20, name: "b", cpu: 5),
        ]
        let descending = ProcessTableSort(column: .cpu, descending: true)
        let ascending = ProcessTableSort(column: .cpu, descending: false)
        XCTAssertEqual(descending.ordered(rows).map(\.pid), [10, 20, 30])
        XCTAssertEqual(ascending.ordered(rows).map(\.pid), [10, 20, 30])
    }

    func testNilCPUStillUsesCpuSortKeyMinusOneAndSortsBelowARealZero() {
        let rows = [
            process(pid: 3, name: "missing-high", cpu: nil),
            process(pid: 1, name: "missing-low", cpu: nil),
            process(pid: 2, name: "idle", cpu: 0),
        ]
        XCTAssertEqual(rows[0].cpuSortKey, -1)
        XCTAssertEqual(rows[1].cpuSortKey, -1)
        XCTAssertEqual(rows[2].cpuSortKey, 0)

        let descending = ProcessTableSort.defaultSort(for: .cpu)
        XCTAssertTrue(descending.descending)
        XCTAssertEqual(descending.ordered(rows).map(\.name), ["idle", "missing-low", "missing-high"])
        XCTAssertEqual(descending.ordered(rows).map(\.pid), [2, 1, 3])
    }

    func testEqualMemoryBreaksTiesByPidAscendingAndDescendingDoesNotFlipTheTie() {
        let rows = [
            process(pid: 30, name: "c", memory: 100),
            process(pid: 10, name: "a", memory: 100),
            process(pid: 20, name: "b", memory: 100),
        ]
        let descending = ProcessTableSort.defaultSort(for: .memory)
        let ascending = ProcessTableSort(column: .memory, descending: false)
        XCTAssertTrue(descending.descending)
        XCTAssertEqual(descending.ordered(rows).map(\.pid), [10, 20, 30])
        XCTAssertEqual(ascending.ordered(rows).map(\.pid), [10, 20, 30])
    }

    func testEqualThreadCountBreaksTiesByPidAscendingAndDescendingDoesNotFlipTheTie() {
        let rows = [
            process(pid: 30, name: "c", threads: 4),
            process(pid: 10, name: "a", threads: 4),
            process(pid: 20, name: "b", threads: 4),
        ]
        let descending = ProcessTableSort(column: .threads, descending: true)
        let ascending = ProcessTableSort(column: .threads, descending: false)
        XCTAssertEqual(descending.ordered(rows).map(\.pid), [10, 20, 30])
        XCTAssertEqual(ascending.ordered(rows).map(\.pid), [10, 20, 30])
    }

    func testMemoryPageFourColumnsShareTheSamePidAscendingTieBreak() {
        let rows = [
            process(pid: 9, name: "dup", cpu: 3, memory: 50, threads: 2),
            process(pid: 2, name: "dup", cpu: 3, memory: 50, threads: 2),
            process(pid: 5, name: "dup", cpu: 3, memory: 50, threads: 2),
        ]
        let columns: [ProcessSortColumn] = [.name, .cpu, .memory, .threads]
        for column in columns {
            let descending = ProcessTableSort(column: column, descending: true)
            let ascending = ProcessTableSort(column: column, descending: false)
            XCTAssertEqual(descending.ordered(rows).map(\.pid), [2, 5, 9], "\(column) desc")
            XCTAssertEqual(ascending.ordered(rows).map(\.pid), [2, 5, 9], "\(column) asc")
        }
    }

    private func process(
        pid: Int32,
        name: String,
        cpu: Double? = nil,
        memory: UInt64 = 1,
        threads: Int = 1
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
