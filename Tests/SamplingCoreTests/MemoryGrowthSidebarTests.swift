import XCTest
@testable import SamplingCore

final class MemoryGrowthSidebarTests: XCTestCase {
    func testLockedCopy() {
        XCTAssertEqual(MemoryGrowthCopy.title, "内存趋势")
        XCTAssertEqual(MemoryGrowthCopy.rising, "近几分钟持续上涨")
        XCTAssertEqual(MemoryGrowthCopy.insufficient, "样本不足，暂不判断")
        XCTAssertEqual(MemoryGrowthCopy.caption(for: .rising), MemoryGrowthCopy.rising)
        XCTAssertEqual(MemoryGrowthCopy.caption(for: .insufficient), MemoryGrowthCopy.insufficient)
        XCTAssertNil(MemoryGrowthCopy.caption(for: .none))
    }

    func testCopyDoesNotClaimALeakOrDanger() {
        let blob = [
            MemoryGrowthCopy.title,
            MemoryGrowthCopy.rising,
            MemoryGrowthCopy.insufficient,
        ].joined(separator: "\n")
        for word in ["泄漏", "泄露", "危险", "告警"] {
            XCTAssertFalse(blob.contains(word), word)
        }
        XCTAssertFalse(blob.localizedCaseInsensitiveContains("leak"))
    }

    func testRisingSeriesShowsTheCalmLineOnTheMemoryPage() {
        let slot = MemoryGrowthSidebar.slot(
            page: .memory,
            selectedPid: 42,
            detailSeries: series(count: MemoryGrowthSignal.minSamples, step: 1_048_576)
        )
        XCTAssertEqual(
            slot,
            MemoryGrowthSlot(title: MemoryGrowthCopy.title, caption: MemoryGrowthCopy.rising)
        )
    }

    func testShortSeriesShowsInsufficientInsteadOfAnEmptySlot() {
        let slot = MemoryGrowthSidebar.slot(
            page: .memory,
            selectedPid: 42,
            detailSeries: series(count: 12, step: 8_388_608)
        )
        XCTAssertEqual(slot?.caption, MemoryGrowthCopy.insufficient)

        let clearedDetail = MemoryGrowthSidebar.slot(
            page: .memory,
            selectedPid: 42,
            detailSeries: nil
        )
        XCTAssertEqual(clearedDetail?.caption, MemoryGrowthCopy.insufficient)
    }

    func testNoneAndNoSelectionOmitTheSlot() {
        let flat = MemoryGrowthSidebar.slot(
            page: .memory,
            selectedPid: 42,
            detailSeries: series(count: 90, step: 0)
        )
        XCTAssertNil(flat)

        let closed = MemoryGrowthSidebar.slot(
            page: .memory,
            selectedPid: nil,
            detailSeries: series(count: MemoryGrowthSignal.minSamples, step: 1_048_576)
        )
        XCTAssertNil(closed)
    }

    func testSwitchingAwayDropsThePreviousRisingLine() {
        let earlier = series(count: MemoryGrowthSignal.minSamples, step: 1_048_576)
        let rising = MemoryGrowthSidebar.slot(page: .memory, selectedPid: 7, detailSeries: earlier)
        XCTAssertEqual(rising?.caption, MemoryGrowthCopy.rising)

        let nextProcess = MemoryGrowthSidebar.slot(page: .memory, selectedPid: 8, detailSeries: nil)
        XCTAssertEqual(nextProcess?.caption, MemoryGrowthCopy.insufficient)

        let deselected = MemoryGrowthSidebar.slot(page: .memory, selectedPid: nil, detailSeries: earlier)
        XCTAssertNil(deselected)
    }

    func testCPUPageDoesNotShowMemoryTrendCopy() {
        let rising = series(count: MemoryGrowthSignal.minSamples, step: 1_048_576)
        for page in [DashboardPage.cpu, .disk, .network, .gpu] {
            XCTAssertNil(
                MemoryGrowthSidebar.slot(page: page, selectedPid: 42, detailSeries: rising),
                page.rawValue
            )
        }
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
