import XCTest
@testable import SamplingCore

/// Memory-page magnitude lookup after the group representative changes.
/// A pass is not a sidebar click and not VoiceOver.
final class MemoryMagnitudeVisibleGroupTests: XCTestCase {
    func testRepresentativeChangeStillReturnsTheVisibleSameNameGroup() {
        var selected: Int32? = 2
        let visible = [
            row(2, "Chrome", memory: 100),
            row(9, "Chrome", memory: 250),
            row(4, "Mail", memory: 80)
        ]
        let found = MemoryMagnitudeVisibleGroup.row(
            page: .memory,
            grouping: true,
            selectedPid: selected,
            visibleUngrouped: visible
        )
        let expected = AppGroupProjection.combine(visible.filter { $0.name == "Chrome" })
        XCTAssertEqual(selected, 2)
        XCTAssertEqual(found?.pid, expected.pid)
        XCTAssertEqual(found?.pid, 9)
        XCTAssertNotEqual(found?.pid, selected)
        XCTAssertEqual(found?.memoryBytes, expected.memoryBytes)
        XCTAssertEqual(found?.memoryBytes, 350)
        XCTAssertEqual(found?.memorySource, expected.memorySource)
        XCTAssertEqual(found?.residentMemoryIsPartial, expected.residentMemoryIsPartial)
        XCTAssertEqual(found?.groupedMemberCount, expected.groupedMemberCount)
        XCTAssertEqual(found?.groupedMemberCount, 2)
    }

    func testOneVisibleMemberStillCarriesAGroupedCountOfOne() throws {
        let visible = [row(4, "Mail", memory: 80)]
        let found = MemoryMagnitudeVisibleGroup.row(
            page: .memory,
            grouping: true,
            selectedPid: 4,
            visibleUngrouped: visible
        )
        XCTAssertEqual(found?.groupedMemberCount, 1)
        XCTAssertEqual(found?.memoryBytes, 80)
        XCTAssertEqual(found?.pid, 4)
        let attribution = MemoryDetailAttribution.make(
            page: .memory,
            magnitudeRow: try XCTUnwrap(found),
            curveRow: row(4, "Mail", memory: 80),
            memoryPointCount: 2,
            trendIsRising: false
        )
        XCTAssertEqual(attribution.magnitude, "当前可见的 1 个同名进程合计")
    }

    func testGroupingOffReturnsNil() {
        let visible = [row(2, "Chrome", memory: 100), row(9, "Chrome", memory: 250)]
        XCTAssertNil(
            MemoryMagnitudeVisibleGroup.row(
                page: .memory,
                grouping: false,
                selectedPid: 2,
                visibleUngrouped: visible
            )
        )
    }

    func testHiddenPidDoesNotBorrowAnotherSameNameRow() {
        let visible = [row(9, "Chrome", memory: 250)]
        let found = MemoryMagnitudeVisibleGroup.row(
            page: .memory,
            grouping: true,
            selectedPid: 2,
            visibleUngrouped: visible
        )
        XCTAssertNil(found)
        XCTAssertNotEqual(found?.memoryBytes, 250)
    }

    func testMissingSelectionReturnsNil() {
        let visible = [row(2, "Chrome", memory: 100), row(9, "Chrome", memory: 250)]
        XCTAssertNil(
            MemoryMagnitudeVisibleGroup.row(
                page: .memory,
                grouping: true,
                selectedPid: nil,
                visibleUngrouped: visible
            )
        )
    }

    func testRenamedVisibleRowUsesTheCurrentName() {
        let alone = [
            row(2, "Chrome Beta", memory: 100),
            row(9, "Chrome", memory: 250)
        ]
        let single = MemoryMagnitudeVisibleGroup.row(
            page: .memory,
            grouping: true,
            selectedPid: 2,
            visibleUngrouped: alone
        )
        XCTAssertEqual(single?.name, "Chrome Beta")
        XCTAssertEqual(single?.groupedMemberCount, 1)
        XCTAssertEqual(single?.memoryBytes, 100)
        XCTAssertEqual(single?.pid, 2)
        XCTAssertNotEqual(single?.memoryBytes, 350)

        let withPeer = [
            row(2, "Chrome Beta", memory: 100),
            row(6, "Chrome Beta", memory: 40),
            row(9, "Chrome", memory: 250)
        ]
        let grouped = MemoryMagnitudeVisibleGroup.row(
            page: .memory,
            grouping: true,
            selectedPid: 2,
            visibleUngrouped: withPeer
        )
        let expected = AppGroupProjection.combine(withPeer.filter { $0.name == "Chrome Beta" })
        XCTAssertEqual(grouped?.memoryBytes, expected.memoryBytes)
        XCTAssertEqual(grouped?.memoryBytes, 140)
        XCTAssertEqual(grouped?.groupedMemberCount, 2)
        XCTAssertEqual(grouped?.pid, expected.pid)
    }

    func testPartialResidentGroupDoesNotChangeTheCurveRowSource() throws {
        let visible = [
            row(2, "Safari", memory: 10),
            row(5, "Safari", memory: 30, source: .resident)
        ]
        let found = MemoryMagnitudeVisibleGroup.row(
            page: .memory,
            grouping: true,
            selectedPid: 2,
            visibleUngrouped: visible
        )
        XCTAssertEqual(found?.memorySource, .resident)
        XCTAssertEqual(found?.residentMemoryIsPartial, true)
        XCTAssertEqual(found?.memoryBytes, 40)
        XCTAssertEqual(found?.groupedMemberCount, 2)
        let attribution = MemoryDetailAttribution.make(
            page: .memory,
            magnitudeRow: try XCTUnwrap(found),
            curveRow: row(2, "Safari", memory: 10),
            memoryPointCount: 3,
            trendIsRising: false
        )
        XCTAssertEqual(attribution.curveTitle, "内存占用")
        XCTAssertEqual(attribution.magnitude, "当前可见的 2 个同名进程合计")
        XCTAssertFalse(attribution.curveTitle?.contains("部分") ?? true)
    }

    func testNonMemoryPagesStayNilEvenWhenGroupingIsOn() {
        let visible = [row(2, "Chrome", memory: 100), row(9, "Chrome", memory: 250)]
        for page in [DashboardPage.cpu, .disk, .network, .machine, .gpu] {
            XCTAssertNil(
                MemoryMagnitudeVisibleGroup.row(
                    page: page,
                    grouping: true,
                    selectedPid: 2,
                    visibleUngrouped: visible
                ),
                "\(page)"
            )
        }
    }

    func testALaterMissDoesNotKeepTheEarlierGroupBytes() {
        let visible = [row(2, "Chrome", memory: 100), row(9, "Chrome", memory: 250)]
        let hit = MemoryMagnitudeVisibleGroup.row(
            page: .memory,
            grouping: true,
            selectedPid: 2,
            visibleUngrouped: visible
        )
        XCTAssertEqual(hit?.memoryBytes, 350)
        let missed = MemoryMagnitudeVisibleGroup.row(
            page: .memory,
            grouping: true,
            selectedPid: 2,
            visibleUngrouped: [row(9, "Chrome", memory: 250)]
        )
        XCTAssertNil(missed)
        let otherPage = MemoryMagnitudeVisibleGroup.row(
            page: .cpu,
            grouping: true,
            selectedPid: 2,
            visibleUngrouped: visible
        )
        XCTAssertNil(otherPage)
    }

    func testExactNameDoesNotFoldADifferentSpelling() {
        let visible = [
            row(2, "Chrome", memory: 100),
            row(9, "chrome", memory: 250)
        ]
        let found = MemoryMagnitudeVisibleGroup.row(
            page: .memory,
            grouping: true,
            selectedPid: 2,
            visibleUngrouped: visible
        )
        XCTAssertEqual(found?.groupedMemberCount, 1)
        XCTAssertEqual(found?.memoryBytes, 100)
        XCTAssertEqual(found?.name, "Chrome")
    }

    private func row(
        _ pid: Int32,
        _ name: String,
        memory: UInt64,
        source: ProcessMemorySource = .footprint
    ) -> ProcessRow {
        ProcessRow(
            pid: pid,
            name: name,
            bundleIdentifier: nil,
            executablePath: nil,
            cpuPercent: nil,
            memoryBytes: memory,
            memorySource: source,
            threadCount: 1
        )
    }
}
