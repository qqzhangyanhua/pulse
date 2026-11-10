import XCTest
@testable import SamplingCore

/// Top reveal scroll id. Does not execute `TopConsumer`; that type is not in SamplingCore.
/// A pass is not a Mac scroll, not List retention, and not VoiceOver.
final class TopCardRevealTargetTests: XCTestCase {
    func testTieForkRevealTargetEqualsTheGroupRepresentative() throws {
        let rows = tieRows()
        let sorted = AppGroupProjection.apply(rows: rows, grouped: true)
        XCTAssertEqual(sorted.map(\.pid), [4])
        XCTAssertFalse(sorted.contains { $0.pid == 9 })

        let plan = try XCTUnwrap(TopAppLocation.plan(
            name: "Chrome",
            pid: 9,
            rows: rows,
            page: .memory,
            currentFilter: "",
            currentRisingOnly: false,
            previousReveal: nil
        ))
        XCTAssertEqual(plan.acceptedPid, 9)
        XCTAssertEqual(plan.reveal.pid, 9)
        XCTAssertEqual(ProcessSelection.applying(pid: 9, to: nil, in: rows), 9)
        XCTAssertEqual(
            MemoryMagnitudeVisibleGroup.row(
                page: .memory,
                grouping: true,
                selectedPid: 9,
                visibleUngrouped: rows
            )?.pid,
            4
        )
        XCTAssertNotEqual(plan.reveal.pid, Int32(4))

        let target = TopCardRevealTarget.scrollID(
            requestPid: plan.reveal.pid,
            page: .memory,
            grouping: true,
            visibleUngrouped: rows,
            sortedRows: sorted
        )
        XCTAssertEqual(target, 4)
    }

    func testOneMemberRevealStaysOnThatPid() {
        let only = [row(4, "Mail", memory: 80)]
        let sorted = AppGroupProjection.apply(rows: only, grouped: true)
        XCTAssertEqual(
            TopCardRevealTarget.scrollID(
                requestPid: 4,
                page: .memory,
                grouping: true,
                visibleUngrouped: only,
                sortedRows: sorted
            ),
            4
        )
    }

    func testRenameUsesTheNewNameRepresentativeAndAStalePlanWritesNothing() {
        let visible = [
            row(4, "Chrome Beta", memory: 40),
            row(6, "Chrome Beta", memory: 200)
        ]
        let sorted = AppGroupProjection.apply(rows: visible, grouped: true)
        XCTAssertEqual(
            TopCardRevealTarget.scrollID(
                requestPid: 4,
                page: .memory,
                grouping: true,
                visibleUngrouped: visible,
                sortedRows: sorted
            ),
            6
        )
        XCTAssertNil(TopAppLocation.plan(
            name: "Chrome",
            pid: 4,
            rows: visible,
            page: .memory,
            currentFilter: "",
            currentRisingOnly: true,
            previousReveal: nil
        ))
    }

    func testLighterOriginalPidFollowsTheHeavierRepresentative() {
        let visible = [row(4, "Chrome", memory: 100), row(9, "Chrome", memory: 250)]
        let sorted = AppGroupProjection.apply(rows: visible, grouped: true)
        XCTAssertFalse(sorted.contains { $0.pid == 4 })
        XCTAssertEqual(
            TopCardRevealTarget.scrollID(
                requestPid: 4,
                page: .memory,
                grouping: true,
                visibleUngrouped: visible,
                sortedRows: sorted
            ),
            9
        )
    }

    func testClosedGroupingKeepsTheOriginalPidWhenTheUnmergedTableContainsIt() {
        let visible = [row(4, "Chrome", memory: 100), row(9, "Chrome", memory: 100)]
        let sorted = AppGroupProjection.apply(rows: visible, grouped: false)
        XCTAssertTrue(sorted.contains { $0.pid == 9 })
        XCTAssertEqual(
            TopCardRevealTarget.scrollID(
                requestPid: 9,
                page: .memory,
                grouping: false,
                visibleUngrouped: visible,
                sortedRows: sorted
            ),
            9
        )
    }

    func testHiddenPidDoesNotBorrowTheSameNameRepresentative() {
        let visible = [row(4, "Chrome", memory: 100)]
        let sorted = AppGroupProjection.apply(rows: visible, grouped: true)
        XCTAssertFalse(sorted.contains { $0.pid == 9 })
        XCTAssertNil(
            TopCardRevealTarget.scrollID(
                requestPid: 9,
                page: .memory,
                grouping: true,
                visibleUngrouped: visible,
                sortedRows: sorted
            )
        )
    }

    func testOtherPagesFallThroughToTheOldGate() {
        let rows = tieRows()
        let sorted = AppGroupProjection.apply(rows: rows, grouped: true)
        XCTAssertEqual(sorted.map(\.pid), [4])
        for page in [DashboardPage.cpu, .disk, .network, .machine, .gpu] {
            XCTAssertNil(
                TopCardRevealTarget.scrollID(
                    requestPid: 9,
                    page: page,
                    grouping: true,
                    visibleUngrouped: rows,
                    sortedRows: sorted
                ),
                "\(page)"
            )
        }
    }

    func testRepeatingThePlanAdvancesGenerationWithoutMovingTheCardPid() {
        let rows = tieRows()
        let first = TopAppLocation.plan(
            name: "Chrome",
            pid: 9,
            rows: rows,
            page: .memory,
            currentFilter: "",
            currentRisingOnly: false,
            previousReveal: nil
        )
        let second = TopAppLocation.plan(
            name: "Chrome",
            pid: 9,
            rows: rows,
            page: .memory,
            currentFilter: "",
            currentRisingOnly: false,
            previousReveal: first?.reveal
        )
        XCTAssertEqual(first?.reveal.pid, 9)
        XCTAssertEqual(second?.reveal.pid, 9)
        XCTAssertEqual(second?.reveal.generation, (first?.reveal.generation ?? 0) &+ 1)
        XCTAssertEqual(ProcessSelection.scrollTarget(selectedPid: 9, rows: rows), 9)
    }

    private func tieRows() -> [ProcessRow] {
        [row(4, "Chrome", memory: 100), row(9, "Chrome", memory: 100)]
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
