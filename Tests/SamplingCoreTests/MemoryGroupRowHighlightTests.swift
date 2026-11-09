import XCTest
@testable import SamplingCore

/// Documents today's pid comparison, then the visible-group highlight.
/// A pass is not a Mac row click, not List selection retention, and not VoiceOver.
final class MemoryGroupRowHighlightTests: XCTestCase {
    func testTodayComparisonMissesTheHeavierRepresentative() {
        let visible = [row(4, "Chrome", memory: 100), row(9, "Chrome", memory: 250)]
        let grouped = MemoryMagnitudeVisibleGroup.row(
            page: .memory,
            grouping: true,
            selectedPid: 4,
            visibleUngrouped: visible
        )
        XCTAssertEqual(grouped?.pid, 9)
        XCTAssertFalse(4 == grouped?.pid)

        XCTAssertEqual(ProcessSelection.scrollTarget(selectedPid: 4, rows: visible), 4)
        let copied = ProcessRowCopy.line(page: .memory, row: visible[0])
        XCTAssertEqual(copied.split(separator: "\t", omittingEmptySubsequences: false)[1], "4")
        let groupedLine = ProcessRowCopy.line(page: .memory, row: tryUnwrap(grouped))
        XCTAssertEqual(groupedLine.split(separator: "\t", omittingEmptySubsequences: false)[1], "2")
        XCTAssertNotEqual(copied, groupedLine)
    }

    func testTodayComparisonAlreadyPaintsAOneMemberGroup() {
        let visible = [row(4, "Mail", memory: 80)]
        let grouped = MemoryMagnitudeVisibleGroup.row(
            page: .memory,
            grouping: true,
            selectedPid: 4,
            visibleUngrouped: visible
        )
        XCTAssertEqual(grouped?.groupedMemberCount, 1)
        XCTAssertEqual(grouped?.pid, 4)
        XCTAssertTrue(4 == grouped?.pid)
    }

    func testEmptyLookupStillComparesTheSelectedPid() {
        let visible = [row(4, "Chrome", memory: 100), row(9, "Chrome", memory: 250)]
        XCTAssertNil(
            MemoryMagnitudeVisibleGroup.row(
                page: .memory,
                grouping: false,
                selectedPid: 4,
                visibleUngrouped: visible
            )
        )
        XCTAssertTrue(4 == visible[0].pid)
        XCTAssertFalse(4 == visible[1].pid)

        for page in [DashboardPage.cpu, .disk, .network, .machine, .gpu] {
            XCTAssertNil(
                MemoryMagnitudeVisibleGroup.row(
                    page: page,
                    grouping: true,
                    selectedPid: 4,
                    visibleUngrouped: visible
                ),
                "\(page)"
            )
        }
        XCTAssertNil(
            MemoryMagnitudeVisibleGroup.row(
                page: .memory,
                grouping: true,
                selectedPid: nil,
                visibleUngrouped: visible
            )
        )
        XCTAssertNil(
            MemoryMagnitudeVisibleGroup.row(
                page: .memory,
                grouping: true,
                selectedPid: 4,
                visibleUngrouped: [row(9, "Chrome", memory: 250)]
            )
        )
    }

    func testRepresentativeChangeHighlightsOnlyTheCombinedRow() {
        var selected: Int32? = 4
        let visible = [row(4, "Chrome", memory: 100), row(9, "Chrome", memory: 250)]
        let grouped = MemoryMagnitudeVisibleGroup.row(
            page: .memory,
            grouping: true,
            selectedPid: selected,
            visibleUngrouped: visible
        )
        XCTAssertEqual(grouped?.pid, 9)
        XCTAssertTrue(
            MemoryGroupRowHighlight.highlighted(
                page: .memory,
                grouping: true,
                selectedPid: selected,
                visibleUngrouped: visible,
                rowPid: 9
            )
        )
        XCTAssertFalse(
            MemoryGroupRowHighlight.highlighted(
                page: .memory,
                grouping: true,
                selectedPid: selected,
                visibleUngrouped: visible,
                rowPid: 4
            )
        )
        XCTAssertEqual(selected, 4)
    }

    func testRenameFollowsTheNewNameGroup() {
        var selected: Int32? = 4
        let visible = [
            row(4, "Chrome Beta", memory: 40),
            row(6, "Chrome Beta", memory: 200),
            row(9, "Chrome", memory: 250)
        ]
        XCTAssertTrue(
            MemoryGroupRowHighlight.highlighted(
                page: .memory,
                grouping: true,
                selectedPid: selected,
                visibleUngrouped: visible,
                rowPid: 6
            )
        )
        XCTAssertFalse(
            MemoryGroupRowHighlight.highlighted(
                page: .memory,
                grouping: true,
                selectedPid: selected,
                visibleUngrouped: visible,
                rowPid: 4
            )
        )
        XCTAssertFalse(
            MemoryGroupRowHighlight.highlighted(
                page: .memory,
                grouping: true,
                selectedPid: selected,
                visibleUngrouped: visible,
                rowPid: 9
            )
        )
        XCTAssertEqual(selected, 4)
    }

    func testOneMemberGroupStaysHighlightedAndClosedOrOtherPagesUsePid() {
        let alone = [row(4, "Mail", memory: 80)]
        let grouped = MemoryMagnitudeVisibleGroup.row(
            page: .memory,
            grouping: true,
            selectedPid: 4,
            visibleUngrouped: alone
        )
        XCTAssertEqual(grouped?.pid, 4)
        XCTAssertEqual(grouped?.groupedMemberCount, 1)
        XCTAssertTrue(
            MemoryGroupRowHighlight.highlighted(
                page: .memory,
                grouping: true,
                selectedPid: 4,
                visibleUngrouped: alone,
                rowPid: 4
            )
        )

        let pair = [row(4, "Chrome", memory: 100), row(9, "Chrome", memory: 250)]
        XCTAssertTrue(
            MemoryGroupRowHighlight.highlighted(
                page: .memory,
                grouping: false,
                selectedPid: 4,
                visibleUngrouped: pair,
                rowPid: 4
            )
        )
        XCTAssertFalse(
            MemoryGroupRowHighlight.highlighted(
                page: .memory,
                grouping: false,
                selectedPid: 4,
                visibleUngrouped: pair,
                rowPid: 9
            )
        )
        for page in [DashboardPage.cpu, .disk, .network, .machine, .gpu] {
            XCTAssertTrue(
                MemoryGroupRowHighlight.highlighted(
                    page: page,
                    grouping: true,
                    selectedPid: 4,
                    visibleUngrouped: pair,
                    rowPid: 4
                ),
                "\(page) selected"
            )
            XCTAssertFalse(
                MemoryGroupRowHighlight.highlighted(
                    page: page,
                    grouping: true,
                    selectedPid: 4,
                    visibleUngrouped: pair,
                    rowPid: 9
                ),
                "\(page) representative"
            )
        }
    }

    func testNoSelectionAndHiddenPidDoNotBorrowASameNameRow() {
        let visible = [row(9, "Chrome", memory: 250)]
        XCTAssertFalse(
            MemoryGroupRowHighlight.highlighted(
                page: .memory,
                grouping: true,
                selectedPid: nil,
                visibleUngrouped: visible,
                rowPid: 9
            )
        )
        XCTAssertFalse(
            MemoryGroupRowHighlight.highlighted(
                page: .memory,
                grouping: true,
                selectedPid: 4,
                visibleUngrouped: visible,
                rowPid: 9
            )
        )
    }

    func testALaterMissDoesNotKeepTheEarlierHighlight() {
        let first = [row(4, "Chrome", memory: 100), row(9, "Chrome", memory: 250)]
        XCTAssertTrue(
            MemoryGroupRowHighlight.highlighted(
                page: .memory,
                grouping: true,
                selectedPid: 4,
                visibleUngrouped: first,
                rowPid: 9
            )
        )
        let second = [row(9, "Chrome", memory: 250)]
        XCTAssertFalse(
            MemoryGroupRowHighlight.highlighted(
                page: .memory,
                grouping: true,
                selectedPid: 4,
                visibleUngrouped: second,
                rowPid: 9
            )
        )
        XCTAssertTrue(
            MemoryGroupRowHighlight.highlighted(
                page: .memory,
                grouping: true,
                selectedPid: 4,
                visibleUngrouped: second,
                rowPid: 4
            )
        )
    }

    private func row(_ pid: Int32, _ name: String, memory: UInt64) -> ProcessRow {
        ProcessRow(
            pid: pid,
            name: name,
            bundleIdentifier: nil,
            executablePath: nil,
            cpuPercent: nil,
            memoryBytes: memory,
            threadCount: 1
        )
    }

    private func tryUnwrap(_ row: ProcessRow?) -> ProcessRow {
        guard let row else {
            XCTFail("expected a row")
            return ProcessRow(
                pid: 0,
                name: "",
                bundleIdentifier: nil,
                executablePath: nil,
                cpuPercent: nil,
                memoryBytes: 0,
                threadCount: 0
            )
        }
        return row
    }
}
