import XCTest
@testable import SamplingCore

/// Ordinary reveal id versus the visible same-name group row.
/// A pass is not a Mac scroll, not List selection retention, and not VoiceOver.
final class MemoryRevealGroupRowTests: XCTestCase {
    func testLighterPidRevealUsesTheVisibleRepresentative() {
        var selected: Int32? = 4
        let visible = [row(4, "Chrome", memory: 100), row(9, "Chrome", memory: 250)]
        let gate = ProcessSelection.scrollTarget(selectedPid: selected, rows: visible)
        let grouped = MemoryMagnitudeVisibleGroup.row(
            page: .memory,
            grouping: true,
            selectedPid: selected,
            visibleUngrouped: visible
        )
        XCTAssertEqual(gate, 4)
        XCTAssertEqual(grouped?.pid, 9)
        XCTAssertNotEqual(gate, grouped?.pid)
        let mapped = MemoryRevealGroupRow.target(
            scrollTarget: gate,
            page: .memory,
            grouping: true,
            visibleUngrouped: visible
        )
        XCTAssertEqual(mapped, grouped?.pid)
        XCTAssertEqual(selected, 4)
    }

    func testNilGateStaysNilEvenWhenAnotherSameNameRowIsVisible() {
        let visible = [row(4, "Chrome", memory: 100), row(9, "Chrome", memory: 250)]
        XCTAssertNil(ProcessSelection.scrollTarget(selectedPid: nil, rows: visible))
        XCTAssertNil(ProcessSelection.scrollTarget(selectedPid: 4, rows: []))
        XCTAssertNil(
            MemoryRevealGroupRow.target(
                scrollTarget: nil,
                page: .memory,
                grouping: true,
                visibleUngrouped: visible
            )
        )
    }

    func testOneMemberAndCurrentRepresentativeStayOnThatPid() {
        let alone = [row(4, "Mail", memory: 80)]
        XCTAssertEqual(
            MemoryRevealGroupRow.target(
                scrollTarget: ProcessSelection.scrollTarget(selectedPid: 4, rows: alone),
                page: .memory,
                grouping: true,
                visibleUngrouped: alone
            ),
            4
        )
        let pair = [row(4, "Chrome", memory: 100), row(9, "Chrome", memory: 250)]
        XCTAssertEqual(
            MemoryRevealGroupRow.target(
                scrollTarget: 9,
                page: .memory,
                grouping: true,
                visibleUngrouped: pair
            ),
            9
        )
    }

    func testRenameUsesTheNewNameRepresentative() {
        var selected: Int32? = 4
        let visible = [
            row(4, "Chrome Beta", memory: 40),
            row(6, "Chrome Beta", memory: 200),
            row(9, "Chrome", memory: 250)
        ]
        let mapped = MemoryRevealGroupRow.target(
            scrollTarget: ProcessSelection.scrollTarget(selectedPid: selected, rows: visible),
            page: .memory,
            grouping: true,
            visibleUngrouped: visible
        )
        XCTAssertEqual(mapped, 6)
        XCTAssertEqual(selected, 4)
    }

    func testHiddenPidKeepsTheOldTarget() {
        let rows = [row(4, "Chrome", memory: 100), row(9, "Chrome", memory: 250)]
        let gate = ProcessSelection.scrollTarget(selectedPid: 4, rows: rows)
        let mapped = MemoryRevealGroupRow.target(
            scrollTarget: gate,
            page: .memory,
            grouping: true,
            visibleUngrouped: [row(9, "Chrome", memory: 250)]
        )
        XCTAssertEqual(mapped, gate)
        XCTAssertEqual(mapped, 4)
    }

    func testClosedGroupingAndOtherPagesKeepTheOldTarget() {
        let visible = [row(4, "Chrome", memory: 100), row(9, "Chrome", memory: 250)]
        let gate = ProcessSelection.scrollTarget(selectedPid: 4, rows: visible)
        XCTAssertEqual(
            MemoryRevealGroupRow.target(
                scrollTarget: gate,
                page: .memory,
                grouping: false,
                visibleUngrouped: visible
            ),
            gate
        )
        for page in [DashboardPage.cpu, .disk, .network, .machine, .gpu] {
            XCTAssertEqual(
                MemoryRevealGroupRow.target(
                    scrollTarget: gate,
                    page: page,
                    grouping: true,
                    visibleUngrouped: visible
                ),
                gate,
                "\(page)"
            )
        }
    }

    func testALaterMissDropsTheEarlierRepresentative() {
        let both = [row(4, "Chrome", memory: 100), row(9, "Chrome", memory: 250)]
        let first = MemoryRevealGroupRow.target(
            scrollTarget: 4,
            page: .memory,
            grouping: true,
            visibleUngrouped: both
        )
        XCTAssertEqual(first, 9)
        let rows = both
        let gate = ProcessSelection.scrollTarget(selectedPid: 4, rows: rows)
        let second = MemoryRevealGroupRow.target(
            scrollTarget: gate,
            page: .memory,
            grouping: true,
            visibleUngrouped: [row(9, "Chrome", memory: 250)]
        )
        XCTAssertEqual(second, 4)
        XCTAssertNotEqual(second, first)
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
}
