import XCTest
@testable import SamplingCore

final class MemoryGrowthListBadgeTests: XCTestCase {
    func testLockedCopyIsShortBadgeAndCalmHelp() {
        XCTAssertEqual(MemoryGrowthListCopy.title, "上涨")
        XCTAssertEqual(MemoryGrowthListCopy.help, "近期内存持续上涨")
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

    func testRisingSelectedMemoryRowShowsTheBadge() {
        let series = risingSeries()
        XCTAssertEqual(MemoryGrowthSignal.evaluate(series), .rising)

        let badge = MemoryGrowthList.badge(
            page: .memory,
            rowPid: 42,
            selectedPid: 42,
            detailSeries: series
        )
        XCTAssertEqual(
            badge,
            MemoryGrowthListBadge(title: MemoryGrowthListCopy.title, help: MemoryGrowthListCopy.help)
        )
    }

    func testSameRisingSeriesLightsSidebarAndListTogether() {
        let series = risingSeries()
        let sidebar = MemoryGrowthSidebar.slot(page: .memory, selectedPid: 7, detailSeries: series)
        let badge = MemoryGrowthList.badge(
            page: .memory,
            rowPid: 7,
            selectedPid: 7,
            detailSeries: series
        )
        XCTAssertEqual(sidebar?.caption, MemoryGrowthCopy.rising)
        XCTAssertEqual(badge?.title, MemoryGrowthListCopy.title)
    }

    func testInsufficientAndNoneOmitTheBadge() {
        let short = MemoryGrowthList.badge(
            page: .memory,
            rowPid: 42,
            selectedPid: 42,
            detailSeries: series(count: 12, step: 8_388_608)
        )
        XCTAssertEqual(MemoryGrowthSignal.evaluate(series(count: 12, step: 8_388_608)), .insufficient)
        XCTAssertNil(short)

        let flatSeries = series(count: 90, step: 0)
        XCTAssertEqual(MemoryGrowthSignal.evaluate(flatSeries), .none)
        let flat = MemoryGrowthList.badge(
            page: .memory,
            rowPid: 42,
            selectedPid: 42,
            detailSeries: flatSeries
        )
        XCTAssertNil(flat)

        let cleared = MemoryGrowthList.badge(
            page: .memory,
            rowPid: 42,
            selectedPid: 42,
            detailSeries: nil
        )
        XCTAssertNil(cleared)
    }

    func testInsufficientStillShowsSidebarButNotTheListBadge() {
        let short = series(count: 12, step: 8_388_608)
        let sidebar = MemoryGrowthSidebar.slot(page: .memory, selectedPid: 42, detailSeries: short)
        let badge = MemoryGrowthList.badge(
            page: .memory,
            rowPid: 42,
            selectedPid: 42,
            detailSeries: short
        )
        XCTAssertEqual(sidebar?.caption, MemoryGrowthCopy.insufficient)
        XCTAssertNil(badge)
    }

    func testUnselectedRowStaysSilentEvenWhenSeriesIsRising() {
        let series = risingSeries()
        let otherRow = MemoryGrowthList.badge(
            page: .memory,
            rowPid: 99,
            selectedPid: 42,
            detailSeries: series
        )
        XCTAssertNil(otherRow)

        let deselected = MemoryGrowthList.badge(
            page: .memory,
            rowPid: 42,
            selectedPid: nil,
            detailSeries: series
        )
        XCTAssertNil(deselected)
    }

    func testNonMemoryPagesNeverShowTheBadge() {
        let series = risingSeries()
        for page in [DashboardPage.cpu, .disk, .network, .gpu] {
            XCTAssertNil(
                MemoryGrowthList.badge(
                    page: page,
                    rowPid: 42,
                    selectedPid: 42,
                    detailSeries: series
                ),
                page.rawValue
            )
        }
    }

    func testSwitchingAwayDropsThePreviousRisingBadge() {
        let earlier = risingSeries()
        let rising = MemoryGrowthList.badge(
            page: .memory,
            rowPid: 7,
            selectedPid: 7,
            detailSeries: earlier
        )
        XCTAssertEqual(rising?.title, MemoryGrowthListCopy.title)

        // Sampler / VM clear the series on pid change; the new row starts insufficient.
        let nextProcess = MemoryGrowthList.badge(
            page: .memory,
            rowPid: 8,
            selectedPid: 8,
            detailSeries: nil
        )
        XCTAssertNil(nextProcess)

        let deselected = MemoryGrowthList.badge(
            page: .memory,
            rowPid: 7,
            selectedPid: nil,
            detailSeries: earlier
        )
        XCTAssertNil(deselected)
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
