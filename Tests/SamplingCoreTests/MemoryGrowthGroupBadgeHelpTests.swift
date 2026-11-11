import XCTest
@testable import SamplingCore

/// Group-row badge help. A pass is not a Mac hover and not a VoiceOver pass.
final class MemoryGrowthGroupBadgeHelpTests: XCTestCase {
    func testGroupedRisingBadgeHelpAppendsTheEvaluatedPid() {
        let series = risingSeries()
        XCTAssertEqual(MemoryGrowthSignal.evaluate(series), .rising)
        let grouped = AppGroupProjection.combine([
            row(4, "Chrome", memory: 100),
            row(9, "Chrome", memory: 250)
        ])
        XCTAssertNotNil(grouped.groupedMemberCount)
        XCTAssertEqual(grouped.pid, 9)
        let badge = MemoryGrowthList.badge(
            page: .memory,
            rowPid: grouped.pid,
            seriesByPid: [grouped.pid: series]
        )
        XCTAssertEqual(badge?.help, MemoryGrowthListCopy.help)
        let expected = MemoryGrowthListCopy.help
            + "此上涨判断针对 PID \(grouped.pid)，不代表同名组合计趋势。"
        let shown = MemoryGrowthList.presented(
            badge,
            groupedMemberCount: grouped.groupedMemberCount,
            rowPid: grouped.pid
        )
        XCTAssertEqual(shown?.title, "上涨")
        XCTAssertEqual(shown?.help, expected)
    }

    func testOneMemberGroupAppendsItsOwnPid() {
        let grouped = AppGroupProjection.combine([row(4, "Mail", memory: 80)])
        XCTAssertEqual(grouped.groupedMemberCount, 1)
        let badge = MemoryGrowthList.badge(
            page: .memory,
            rowPid: grouped.pid,
            seriesByPid: [grouped.pid: risingSeries()]
        )
        let shown = MemoryGrowthList.presented(
            badge,
            groupedMemberCount: grouped.groupedMemberCount,
            rowPid: grouped.pid
        )
        XCTAssertEqual(
            shown?.help,
            MemoryGrowthListCopy.help + "此上涨判断针对 PID 4，不代表同名组合计趋势。"
        )
    }

    func testRepresentativeChangeUsesTheNewRowPidNotTheSelection() {
        let series = risingSeries()
        var selected: Int32 = 3
        let first = AppGroupProjection.combine([
            row(9, "Chrome", memory: 250),
            row(4, "Chrome", memory: 100)
        ])
        let firstHelp = MemoryGrowthList.presented(
            MemoryGrowthList.badge(page: .memory, rowPid: first.pid, seriesByPid: [first.pid: series]),
            groupedMemberCount: first.groupedMemberCount,
            rowPid: first.pid
        )?.help
        XCTAssertEqual(first.pid, 9)
        XCTAssertTrue(firstHelp?.contains("PID 9") ?? false)
        XCTAssertFalse(firstHelp?.contains("PID \(selected)") ?? true)

        let second = AppGroupProjection.combine([
            row(9, "Chrome", memory: 40),
            row(4, "Chrome", memory: 300)
        ])
        let secondHelp = MemoryGrowthList.presented(
            MemoryGrowthList.badge(page: .memory, rowPid: second.pid, seriesByPid: [second.pid: series]),
            groupedMemberCount: second.groupedMemberCount,
            rowPid: second.pid
        )?.help
        XCTAssertEqual(second.pid, 4)
        XCTAssertTrue(secondHelp?.contains("PID 4") ?? false)
        XCTAssertFalse(secondHelp?.contains("PID 9") ?? true)
        XCTAssertFalse(secondHelp?.contains("PID \(selected)") ?? true)
        XCTAssertEqual(selected, 3)
    }

    func testMissingBadgeStaysEmptyAndUngroupedHelpStaysStatic() {
        let short = series(count: 12, step: 8_388_608)
        let flat = series(count: 90, step: 0)
        XCTAssertNil(MemoryGrowthList.badge(page: .memory, rowPid: 9, seriesByPid: [9: short]))
        XCTAssertNil(MemoryGrowthList.badge(page: .memory, rowPid: 9, seriesByPid: [9: flat]))
        XCTAssertNil(MemoryGrowthList.badge(page: .memory, rowPid: 9, seriesByPid: [:]))
        XCTAssertNil(MemoryGrowthList.presented(nil, groupedMemberCount: 2, rowPid: 9))

        let badge = MemoryGrowthList.badge(
            page: .memory,
            rowPid: 9,
            seriesByPid: [9: risingSeries()]
        )
        let plain = MemoryGrowthList.presented(badge, groupedMemberCount: nil, rowPid: 9)
        XCTAssertEqual(plain?.help, MemoryGrowthListCopy.help)
        XCTAssertFalse(plain?.help.contains("PID") ?? true)
        XCTAssertEqual(MemoryGrowthListCopy.help, "完整进程列表按当前表头排序后取前5，非过滤后前5；仅按各进程自身的近期内存占用序列判断趋势。")
    }

    func testOtherPagesStayEmptyEvenWhenTheRowIsGrouped() {
        let grouped = AppGroupProjection.combine([
            row(4, "Chrome", memory: 100),
            row(9, "Chrome", memory: 250)
        ])
        XCTAssertNotNil(grouped.groupedMemberCount)
        for page in [DashboardPage.cpu, .disk, .network, .machine, .gpu] {
            XCTAssertNil(
                MemoryGrowthList.badge(
                    page: page,
                    rowPid: grouped.pid,
                    seriesByPid: [grouped.pid: risingSeries()]
                ),
                "\(page)"
            )
        }
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

    private func risingSeries() -> [ChartSample] {
        series(count: MemoryGrowthSignal.minSamples, step: 1_048_576)
    }

    private func series(count: Int, step: Double) -> [ChartSample] {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        return (0..<count).map { index in
            ChartSample(
                id: UInt64(index + 1),
                date: start.addingTimeInterval(Double(index) * 1.5),
                value: 200_000_000 + Double(index) * step
            )
        }
    }
}
