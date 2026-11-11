import XCTest
@testable import SamplingCore

/// Insufficient-slot attribution. A pass is not a sidebar hover and not VoiceOver.
final class MemoryDetailInsufficientSlotPidTests: XCTestCase {
    func testInsufficientMemoryTrendNamesTheCurvePid() {
        let attribution = MemoryDetailAttribution.make(
            page: .memory,
            magnitudeRow: row(pid: 9),
            curveRow: row(pid: 4),
            memoryPointCount: 2,
            trendIsRising: false
        )
        XCTAssertEqual(attribution.trend, "当前采样对象：PID 4")
        XCTAssertFalse(attribution.trend?.contains("9") ?? true)
    }

    func testCurvePidChangeRewritesTheSentenceAndIgnoresSelectedPid() {
        var selectedPid: Int32 = 9
        let first = MemoryDetailAttribution.make(
            page: .memory,
            magnitudeRow: row(pid: selectedPid, members: 3),
            curveRow: row(pid: 4),
            memoryPointCount: 12,
            trendIsRising: false
        )
        XCTAssertEqual(first.trend, "当前采样对象：PID 4")
        XCTAssertEqual(selectedPid, 9)

        selectedPid = 4
        let next = MemoryDetailAttribution.make(
            page: .memory,
            magnitudeRow: row(pid: 9, members: 1),
            curveRow: row(pid: 7),
            memoryPointCount: 0,
            trendIsRising: false
        )
        XCTAssertEqual(next.trend, "当前采样对象：PID 7")
        XCTAssertEqual(selectedPid, 4)
        XCTAssertFalse(next.trend?.contains("9") ?? true)
        XCTAssertNotEqual(first.trend, next.trend)
    }

    func testRisingSentenceStaysTheOriginalCurvePidLine() {
        let rising = MemoryDetailAttribution.make(
            page: .memory,
            magnitudeRow: row(pid: 9, members: 3),
            curveRow: row(pid: 4),
            memoryPointCount: 80,
            trendIsRising: true
        )
        XCTAssertEqual(rising.trend, "这条趋势属于 PID 4")
        XCTAssertFalse(rising.trend?.contains("当前采样对象") ?? true)
        XCTAssertFalse(rising.trend?.contains("9") ?? true)
        XCTAssertEqual(MemoryGrowthCopy.rising, "近期内存占用上涨")
        XCTAssertEqual(MemoryGrowthCopy.insufficient, "样本不足，暂不判断")
        XCTAssertFalse(MemoryGrowthCopy.insufficient.contains("PID"))
        XCTAssertFalse(MemoryGrowthCopy.rising.contains("当前采样对象"))
        XCTAssertFalse(MemoryGrowthCopy.basis.contains("当前采样对象"))
        XCTAssertFalse(MemoryGrowthListCopy.help.contains("当前采样对象"))
    }

    func testOtherPagesAndShortSummariesStayClear() {
        XCTAssertEqual(MemoryDetailAttribution.curvePlaceholder, "正在采集内存曲线")
        for points in [0, 1] {
            let attribution = MemoryDetailAttribution.make(
                page: .memory,
                magnitudeRow: row(pid: 9),
                curveRow: row(pid: 4),
                memoryPointCount: points,
                trendIsRising: false
            )
            XCTAssertNil(attribution.curvePid, "points \(points)")
            XCTAssertEqual(attribution.trend, "当前采样对象：PID 4", "points \(points)")
            XCTAssertEqual(
                MemoryDetailAttribution.curveSummary(page: .memory, samples: [], curvePid: 4),
                ""
            )
        }
        let one = [ChartSample(id: 1, date: Date(timeIntervalSince1970: 1_700_000_000), value: 1_048_576)]
        XCTAssertEqual(MemoryDetailAttribution.curveSummary(page: .memory, samples: one, curvePid: 4), "")
        XCTAssertFalse(
            MemoryDetailAttribution.curveSummary(page: .memory, samples: one, curvePid: 4).contains("PID")
        )

        for page in [DashboardPage.cpu, .disk, .network, .machine, .gpu] {
            for rising in [false, true] {
                let other = MemoryDetailAttribution.make(
                    page: page,
                    magnitudeRow: row(pid: 9),
                    curveRow: row(pid: 4),
                    memoryPointCount: 80,
                    trendIsRising: rising
                )
                XCTAssertNil(other.trend, "\(page) rising=\(rising)")
            }
        }
    }

    func testDisplayGatesDoNotInventASlot() throws {
        let rising = series(count: MemoryGrowthSignal.minSamples, step: 1_048_576)
        XCTAssertNil(
            MemoryGrowthSidebar.slot(page: .memory, selectedPid: nil, detailSeries: rising)
        )
        XCTAssertNil(
            MemoryGrowthSidebar.slot(
                page: .memory,
                selectedPid: 4,
                detailSeries: series(count: 90, step: 0)
            )
        )

        let emptySeries = MemoryGrowthSidebar.slot(page: .memory, selectedPid: 4, detailSeries: [])
        XCTAssertEqual(emptySeries?.caption, MemoryGrowthCopy.insufficient)
        XCTAssertNil(emptySeries?.basis)
        XCTAssertFalse(emptySeries?.caption.contains("当前采样对象") ?? true)
        XCTAssertFalse(emptySeries?.caption.contains("PID") ?? true)

        let cleared = MemoryGrowthSidebar.slot(page: .memory, selectedPid: 4, detailSeries: nil)
        XCTAssertEqual(cleared?.caption, MemoryGrowthCopy.insufficient)

        let noSubject = ProcessQuitSession.sidebar(
            ProcessQuitOutcome(),
            ProcessQuitSession.Context(
                listSelectedPid: nil,
                sidebarSubjectPid: nil,
                rows: [],
                liveDetail: nil
            )
        )
        XCTAssertNil(noSubject.detail)
        XCTAssertFalse(noSubject.showsLiveTrend)

        let missingRow = ProcessQuitSession.sidebar(
            ProcessQuitOutcome(),
            ProcessQuitSession.Context(
                listSelectedPid: 4,
                sidebarSubjectPid: 4,
                rows: [row(pid: 9)],
                liveDetail: nil
            )
        )
        XCTAssertNil(missingRow.detail)
        XCTAssertFalse(missingRow.showsLiveTrend)

        let mismatched = ProcessQuitSession.sidebar(
            ProcessQuitOutcome(),
            ProcessQuitSession.Context(
                listSelectedPid: 4,
                sidebarSubjectPid: 4,
                rows: [row(pid: 4), row(pid: 9)],
                liveDetail: ProcessDetail(
                    row: row(pid: 9),
                    memorySeries: rising,
                    cpuSeries: []
                )
            )
        )
        let detail = try XCTUnwrap(mismatched.detail)
        XCTAssertEqual(detail.row.pid, 4)
        XCTAssertEqual(detail.memorySeries.count, 0)
        XCTAssertTrue(mismatched.showsLiveTrend)
        XCTAssertFalse(mismatched.frozen)
        let slot = MemoryGrowthSidebar.slot(
            page: .memory,
            selectedPid: 4,
            detailSeries: detail.memorySeries
        )
        XCTAssertEqual(slot?.caption, MemoryGrowthCopy.insufficient)
        let trend = MemoryDetailAttribution.make(
            page: .memory,
            magnitudeRow: row(pid: 9, members: 3),
            curveRow: detail.row,
            memoryPointCount: detail.memorySeries.count,
            trendIsRising: slot?.caption == MemoryGrowthCopy.rising
        ).trend
        XCTAssertEqual(trend, "当前采样对象：PID 4")
        XCTAssertFalse(trend?.contains("9") ?? true)

        try assertAbsentFreezeDoesNotOpenASlot(rising: rising)
    }

    private func assertAbsentFreezeDoesNotOpenASlot(rising: [ChartSample]) throws {
        var store = ProcessQuitOutcome()
        let subject = row(pid: 4)
        let issued = try XCTUnwrap(store.click(.terminate, selectedPid: 4, rows: [subject]))
        store.complete(pid: 4, token: issued.token, result: .stillRunning)
        let frozenDetail = ProcessDetail(
            row: subject,
            memorySeries: series(count: 4, step: 1),
            cpuSeries: []
        )
        let otherLive = ProcessDetail(row: row(pid: 9), memorySeries: rising, cpuSeries: [])
        _ = ProcessQuitSession.applySample(
            store: &store,
            listSelectedPid: nil,
            sidebarSubjectPid: 4,
            currentLiveDetail: nil,
            observation: ProcessQuitSession.Observation(
                rows: [row(pid: 9)],
                liveDetail: otherLive,
                detailToFreeze: frozenDetail
            )
        )
        let side = ProcessQuitSession.sidebar(
            store,
            ProcessQuitSession.Context(
                listSelectedPid: nil,
                sidebarSubjectPid: 4,
                rows: [row(pid: 9)],
                liveDetail: otherLive
            )
        )
        XCTAssertTrue(side.frozen)
        XCTAssertFalse(side.showsLiveTrend)
        XCTAssertEqual(side.detail, frozenDetail)
        XCTAssertNotEqual(side.detail?.row.pid, 9)
        let slot: MemoryGrowthSlot? = side.showsLiveTrend
            ? MemoryGrowthSidebar.slot(
                page: .memory,
                selectedPid: side.detail?.row.pid,
                detailSeries: side.detail?.memorySeries
            )
            : nil
        XCTAssertNil(slot)
    }

    private func row(pid: Int32, members: Int? = nil) -> ProcessRow {
        ProcessRow(
            pid: pid,
            name: "Example",
            bundleIdentifier: nil,
            executablePath: nil,
            cpuPercent: nil,
            memoryBytes: 1_048_576,
            threadCount: 1,
            groupedMemberCount: members
        )
    }

    private func series(count: Int, step: Double) -> [ChartSample] {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        return (0..<count).map { index in
            ChartSample(
                id: UInt64(index + 1),
                date: start.addingTimeInterval(Double(index)),
                value: 200_000_000 + Double(index) * step
            )
        }
    }
}
