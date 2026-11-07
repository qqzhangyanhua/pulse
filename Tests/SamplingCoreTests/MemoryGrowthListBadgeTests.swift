import XCTest
@testable import SamplingCore

final class MemoryGrowthListBadgeTests: XCTestCase {
    func testLockedCopyIsShortBadgeAndCalmHelp() {
        XCTAssertEqual(MemoryGrowthListCopy.title, "上涨")
        XCTAssertEqual(MemoryGrowthListCopy.help, "完整进程列表按当前表头排序后取前5，非过滤后前5；仅按各进程自身的近期内存占用序列判断趋势。")
        XCTAssertNotEqual(MemoryGrowthListCopy.title, "持续上涨")
        XCTAssertNotEqual(MemoryGrowthListCopy.title, MemoryGrowthCopy.rising)
    }

    func testCopyDoesNotClaimALeakOrDanger() {
        let blob = [
            MemoryGrowthListCopy.title,
            MemoryGrowthListCopy.help,
        ].joined(separator: "\n")
        for word in ["泄漏", "泄露", "危险", "告警"] {
            XCTAssertFalse(blob.contains(word), word)
        }
        XCTAssertFalse(blob.localizedCaseInsensitiveContains("leak"))
    }

    func testRisingTopFiveMemoryRowShowsTheBadge() {
        let series = risingSeries()
        XCTAssertEqual(MemoryGrowthSignal.evaluate(series), .rising)

        let badge = MemoryGrowthList.badge(
            page: .memory,
            rowPid: 42,
            seriesByPid: [42: series]
        )
        XCTAssertEqual(
            badge,
            MemoryGrowthListBadge(title: MemoryGrowthListCopy.title, help: MemoryGrowthListCopy.help)
        )
    }

    /// ProcessTablePane looks up every row. Selection is not a gate.
    func testListWiringLightsEachTopFiveRisingRowNotOnlyTheSelection() {
        let rising = risingSeries()
        let short = series(count: 12, step: 8_388_608)
        let flat = series(count: 90, step: 0)
        XCTAssertEqual(MemoryGrowthSignal.evaluate(rising), .rising)
        XCTAssertEqual(MemoryGrowthSignal.evaluate(short), .insufficient)
        XCTAssertEqual(MemoryGrowthSignal.evaluate(flat), .none)

        let seriesByPid: [Int32: [ChartSample]] = [
            1: rising,
            2: rising,
            3: flat,
            4: rising,
            5: short,
        ]
        let rowPids: [Int32] = [1, 2, 3, 4, 5, 6]
        let badges = rowPids.map { pid in
            MemoryGrowthList.badge(page: .memory, rowPid: pid, seriesByPid: seriesByPid)
        }

        XCTAssertEqual(badges[0]?.title, MemoryGrowthListCopy.title)
        XCTAssertEqual(badges[1]?.title, MemoryGrowthListCopy.title)
        XCTAssertNil(badges[2], "Top5 ∩ none stays empty")
        XCTAssertEqual(badges[3]?.title, MemoryGrowthListCopy.title)
        XCTAssertNil(badges[4], "Top5 ∩ insufficient stays empty")
        XCTAssertNil(badges[5], "outside Top5 stays empty even if this row is selected")
        XCTAssertEqual(badges.compactMap { $0 }.count, 3)
    }

    func testSelectionAloneIsNotEnoughForTheBadge() {
        let rising = risingSeries()
        XCTAssertEqual(MemoryGrowthSignal.evaluate(rising), .rising)

        // Selected pid 99 can be rising in the sidebar series, but it is not in Top 5.
        XCTAssertNil(
            MemoryGrowthList.badge(
                page: .memory,
                rowPid: 99,
                seriesByPid: [
                    1: rising,
                    2: rising,
                    3: rising,
                    4: rising,
                    5: rising,
                ]
            )
        )
    }

    func testUnselectedTopFiveRisingRowStillShowsTheBadge() {
        let series = risingSeries()
        let badge = MemoryGrowthList.badge(
            page: .memory,
            rowPid: 7,
            seriesByPid: [7: series]
        )
        XCTAssertEqual(badge?.title, MemoryGrowthListCopy.title)
        XCTAssertEqual(badge?.help, MemoryGrowthListCopy.help)
    }

    func testSameRisingSeriesLightsSidebarAndListTogether() {
        let series = risingSeries()
        let sidebar = MemoryGrowthSidebar.slot(page: .memory, selectedPid: 7, detailSeries: series)
        let badge = MemoryGrowthList.badge(
            page: .memory,
            rowPid: 7,
            seriesByPid: [7: series]
        )
        XCTAssertEqual(sidebar?.caption, MemoryGrowthCopy.rising)
        XCTAssertEqual(badge?.title, MemoryGrowthListCopy.title)
    }

    func testSelectedOutsideTopFiveKeepsSidebarButOmitsListBadge() {
        let series = risingSeries()
        let sidebar = MemoryGrowthSidebar.slot(page: .memory, selectedPid: 99, detailSeries: series)
        let badge = MemoryGrowthList.badge(
            page: .memory,
            rowPid: 99,
            seriesByPid: [1: series]
        )
        XCTAssertEqual(sidebar?.caption, MemoryGrowthCopy.rising)
        XCTAssertNil(badge)
    }

    func testInsufficientAndNoneOmitTheBadge() {
        let shortSeries = series(count: 12, step: 8_388_608)
        XCTAssertEqual(MemoryGrowthSignal.evaluate(shortSeries), .insufficient)
        XCTAssertNil(
            MemoryGrowthList.badge(
                page: .memory,
                rowPid: 42,
                seriesByPid: [42: shortSeries]
            )
        )

        let flatSeries = series(count: 90, step: 0)
        XCTAssertEqual(MemoryGrowthSignal.evaluate(flatSeries), .none)
        XCTAssertNil(
            MemoryGrowthList.badge(
                page: .memory,
                rowPid: 42,
                seriesByPid: [42: flatSeries]
            )
        )

        XCTAssertNil(
            MemoryGrowthList.badge(
                page: .memory,
                rowPid: 42,
                seriesByPid: [:]
            )
        )
    }

    func testInsufficientStillShowsSidebarButNotTheListBadge() {
        let short = series(count: 12, step: 8_388_608)
        let sidebar = MemoryGrowthSidebar.slot(page: .memory, selectedPid: 42, detailSeries: short)
        let badge = MemoryGrowthList.badge(
            page: .memory,
            rowPid: 42,
            seriesByPid: [42: short]
        )
        XCTAssertEqual(sidebar?.caption, MemoryGrowthCopy.insufficient)
        XCTAssertNil(badge)
    }

    func testNonMemoryPagesNeverShowTheBadge() {
        let series = risingSeries()
        let seriesByPid = [Int32(42): series]
        for page in [DashboardPage.cpu, .disk, .network, .gpu] {
            XCTAssertNil(
                MemoryGrowthList.badge(
                    page: page,
                    rowPid: 42,
                    seriesByPid: seriesByPid
                ),
                page.rawValue
            )
        }
    }

    func testPidMissingFromTheMapDropsTheBadge() {
        let earlier = risingSeries()
        let rising = MemoryGrowthList.badge(
            page: .memory,
            rowPid: 7,
            seriesByPid: [7: earlier]
        )
        XCTAssertEqual(rising?.title, MemoryGrowthListCopy.title)

        // Sort churn / drop: the fallen pid is gone from the Top 5 map.
        XCTAssertNil(
            MemoryGrowthList.badge(
                page: .memory,
                rowPid: 7,
                seriesByPid: [8: earlier]
            )
        )
        XCTAssertNil(
            MemoryGrowthList.badge(
                page: .memory,
                rowPid: 8,
                seriesByPid: [:]
            )
        )
    }

    private func risingSeries() -> [ChartSample] {
        series(count: MemoryGrowthSignal.minSamples, step: 1_048_576)
    }

    private func series(count: Int, step: Double) -> [ChartSample] {
        let baseline = 200_000_000.0
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        return (0..<count).map { index in
            ChartSample(
                id: UInt64(index + 1),
                date: start.addingTimeInterval(Double(index) * 1.5),
                value: baseline + Double(index) * step
            )
        }
    }
}
