import XCTest
@testable import SamplingCore

/// Memory-page copy of the visible same-name group.
/// A pass is not a Mac pasteboard write, not a focused text field, and not VoiceOver.
final class MemoryGroupRowCopyTests: XCTestCase {
    func testLighterPidCopiesTheWholeVisibleGroupLine() throws {
        var selected: Int32? = 4
        let light = row(4, "Chrome", memory: 100, cpu: 1.5, threads: 2)
        let heavy = row(9, "Chrome", memory: 250, cpu: 3, threads: 5)
        let visible = [light, heavy]
        let sorted = AppGroupProjection.apply(rows: visible, grouped: true)
        let copied = MemoryGroupRowCopy.row(
            page: .memory,
            grouping: true,
            selectedPid: selected,
            visibleUngrouped: visible,
            sortedRows: sorted,
            rows: visible
        )
        let grouped = try XCTUnwrap(
            MemoryMagnitudeVisibleGroup.row(
                page: .memory,
                grouping: true,
                selectedPid: selected,
                visibleUngrouped: visible
            )
        )
        let copiedLine = ProcessRowCopy.line(page: .memory, row: try XCTUnwrap(copied))
        let groupedLine = ProcessRowCopy.line(page: .memory, row: grouped)
        XCTAssertEqual(copiedLine, groupedLine)
        let fields = groupedLine.split(separator: "\t", omittingEmptySubsequences: false)
        XCTAssertEqual(fields[0], "Chrome")
        XCTAssertEqual(fields[1], "2")
        XCTAssertEqual(fields[2], "4.5%")
        XCTAssertEqual(fields[3], "350 字节")
        XCTAssertEqual(fields[4], "7")
        XCTAssertEqual(selected, 4)
    }

    func testOneMemberGroupCopiesCountOne() throws {
        let only = row(4, "Mail", memory: 80, cpu: 0.5, threads: 3)
        let visible = [only]
        let sorted = AppGroupProjection.apply(rows: visible, grouped: true)
        let copied = try XCTUnwrap(copy(page: .memory, grouping: true, selected: 4, visible: visible, sorted: sorted, rows: visible))
        XCTAssertEqual(copied.groupedMemberCount, 1)
        XCTAssertEqual(copied.pid, 4)
        XCTAssertEqual(column(ProcessRowCopy.line(page: .memory, row: copied), 1), "1")
    }

    func testRepresentativePidAlreadyMatchesTodaysSelectedRow() throws {
        let light = row(4, "Chrome", memory: 100, cpu: 1, threads: 2)
        let heavy = row(9, "Chrome", memory: 250, cpu: 2, threads: 4)
        let visible = [light, heavy]
        let sorted = AppGroupProjection.apply(rows: visible, grouped: true)
        let copied = try XCTUnwrap(copy(page: .memory, grouping: true, selected: 9, visible: visible, sorted: sorted, rows: visible))
        let selectedRow = sorted.first { $0.pid == 9 } ?? visible.first { $0.pid == 9 }
        XCTAssertEqual(
            ProcessRowCopy.line(page: .memory, row: copied),
            ProcessRowCopy.line(page: .memory, row: try XCTUnwrap(selectedRow))
        )
    }

    func testRenameCopiesTheNewNameGroup() throws {
        var selected: Int32? = 4
        let visible = [
            row(4, "Chrome Beta", memory: 40, cpu: 1, threads: 2),
            row(6, "Chrome Beta", memory: 200, cpu: 4, threads: 8),
            row(9, "Chrome", memory: 250, cpu: 3, threads: 5)
        ]
        let sorted = AppGroupProjection.apply(rows: visible, grouped: true)
        let copied = try XCTUnwrap(copy(page: .memory, grouping: true, selected: selected, visible: visible, sorted: sorted, rows: visible))
        let grouped = try XCTUnwrap(MemoryMagnitudeVisibleGroup.row(
            page: .memory, grouping: true, selectedPid: selected, visibleUngrouped: visible
        ))
        XCTAssertEqual(grouped.name, "Chrome Beta")
        XCTAssertEqual(ProcessRowCopy.line(page: .memory, row: copied), ProcessRowCopy.line(page: .memory, row: grouped))
        XCTAssertEqual(selected, 4)
    }

    func testClosedGroupingAndOtherPagesKeepTheSelectedRow() throws {
        let light = row(4, "Chrome", memory: 100, cpu: 1.5, threads: 2)
        let heavy = row(9, "Chrome", memory: 250, cpu: 3, threads: 5)
        let visible = [light, heavy]
        let ungrouped = AppGroupProjection.apply(rows: visible, grouped: false)
        let closed = try XCTUnwrap(copy(page: .memory, grouping: false, selected: 4, visible: visible, sorted: ungrouped, rows: visible))
        XCTAssertEqual(ProcessRowCopy.line(page: .memory, row: closed), ProcessRowCopy.line(page: .memory, row: light))

        let groupedSorted = AppGroupProjection.apply(rows: visible, grouped: true)
        for page in [DashboardPage.cpu, .disk, .network, .machine, .gpu] {
            let copied = try XCTUnwrap(copy(page: page, grouping: true, selected: 4, visible: visible, sorted: groupedSorted, rows: visible))
            let fallback = groupedSorted.first { $0.pid == 4 } ?? visible.first { $0.pid == 4 }
            XCTAssertEqual(
                ProcessRowCopy.line(page: page, row: copied),
                ProcessRowCopy.line(page: page, row: try XCTUnwrap(fallback)),
                "\(page)"
            )
            XCTAssertEqual(copied.pid, 4, "\(page)")
        }
    }

    func testHiddenPidDoesNotBorrowTheSameNameRow() throws {
        let light = row(4, "Chrome", memory: 100, cpu: 1.5, threads: 2)
        let heavy = row(9, "Chrome", memory: 250, cpu: 3, threads: 5)
        let rows = [light, heavy]
        let visible = [heavy]
        let sorted = AppGroupProjection.apply(rows: visible, grouped: true)
        let copied = try XCTUnwrap(copy(page: .memory, grouping: true, selected: 4, visible: visible, sorted: sorted, rows: rows))
        XCTAssertEqual(ProcessRowCopy.line(page: .memory, row: copied), ProcessRowCopy.line(page: .memory, row: light))
        XCTAssertEqual(column(ProcessRowCopy.line(page: .memory, row: copied), 1), "4")
    }

    func testNoSelectedRowProducesNoProcessLine() {
        let visible = [row(9, "Chrome", memory: 250, cpu: 3, threads: 5)]
        let sorted = AppGroupProjection.apply(rows: visible, grouped: true)
        XCTAssertNil(copy(page: .memory, grouping: true, selected: nil, visible: visible, sorted: sorted, rows: []))
        XCTAssertNil(copy(page: .memory, grouping: true, selected: 4, visible: visible, sorted: sorted, rows: visible))
    }

    func testALaterMissDropsTheEarlierGroupLine() throws {
        let light = row(4, "Chrome", memory: 100, cpu: 1.5, threads: 2)
        let heavy = row(9, "Chrome", memory: 250, cpu: 3, threads: 5)
        let both = [light, heavy]
        let firstSorted = AppGroupProjection.apply(rows: both, grouped: true)
        let first = try XCTUnwrap(copy(page: .memory, grouping: true, selected: 4, visible: both, sorted: firstSorted, rows: both))
        let firstGroup = try XCTUnwrap(MemoryMagnitudeVisibleGroup.row(
            page: .memory, grouping: true, selectedPid: 4, visibleUngrouped: both
        ))
        XCTAssertEqual(ProcessRowCopy.line(page: .memory, row: first), ProcessRowCopy.line(page: .memory, row: firstGroup))

        let visible = [heavy]
        let secondSorted = AppGroupProjection.apply(rows: visible, grouped: true)
        let second = try XCTUnwrap(copy(page: .memory, grouping: true, selected: 4, visible: visible, sorted: secondSorted, rows: both))
        XCTAssertEqual(ProcessRowCopy.line(page: .memory, row: second), ProcessRowCopy.line(page: .memory, row: light))
        XCTAssertNotEqual(ProcessRowCopy.line(page: .memory, row: second), ProcessRowCopy.line(page: .memory, row: first))
    }

    private func copy(
        page: DashboardPage,
        grouping: Bool,
        selected: Int32?,
        visible: [ProcessRow],
        sorted: [ProcessRow],
        rows: [ProcessRow]
    ) -> ProcessRow? {
        MemoryGroupRowCopy.row(
            page: page,
            grouping: grouping,
            selectedPid: selected,
            visibleUngrouped: visible,
            sortedRows: sorted,
            rows: rows
        )
    }

    private func column(_ line: String, _ index: Int) -> String {
        String(line.split(separator: "\t", omittingEmptySubsequences: false)[index])
    }

    private func row(
        _ pid: Int32,
        _ name: String,
        memory: UInt64,
        cpu: Double?,
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
