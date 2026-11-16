import XCTest
@testable import SamplingCore

/// Curve mean/peak and the GPU-share bar. Ranges and percents in; texts and fractions out.
final class GPUPageLayoutTests: XCTestCase {
    func testLiveMeanAndPeakUseLiveSamplesAndIgnoreHistory() {
        var page = GPUPageState.initial
        page.history.record(percent: 10, at: Date(timeIntervalSince1970: 1))
        page.history.record(percent: 30, at: Date(timeIntervalSince1970: 2))

        let summary = page.curveSummary(range: .live, historyPoints: [1, nil, 100])

        XCTAssertEqual(summary.meanText, "20.0%")
        XCTAssertEqual(summary.peakText, "30.0%")
    }

    func testLiveWithNoSamplesIsDashEvenWhenHistoryHasNumbers() {
        let summary = GPUPageState.initial.curveSummary(range: .live, historyPoints: [50])

        XCTAssertEqual(summary.meanText, "—")
        XCTAssertEqual(summary.peakText, "—")
    }

    func testLiveRealZeroStaysZero() {
        var page = GPUPageState.initial
        page.history.record(percent: 0, at: Date(timeIntervalSince1970: 1))

        let summary = page.curveSummary(range: .live, historyPoints: [])

        XCTAssertEqual(summary.meanText, "0.0%")
        XCTAssertEqual(summary.peakText, "0.0%")
    }

    func testHourDayAndWeekSkipGapsAndDoNotUseLiveSamples() {
        var page = GPUPageState.initial
        page.history.record(percent: 99, at: Date(timeIntervalSince1970: 1))
        let history: [Double?] = [10, nil, 40]

        for range in [HistoryCurveRange.hour, .day, .week] {
            let summary = page.curveSummary(range: range, historyPoints: history)
            XCTAssertEqual(summary.meanText, "25.0%", range.title)
            XCTAssertEqual(summary.peakText, "40.0%", range.title)
        }
    }

    func testStoredRangesWithNoNumbersAreDash() {
        var page = GPUPageState.initial
        page.history.record(percent: 80, at: Date(timeIntervalSince1970: 1))

        for range in [HistoryCurveRange.hour, .day, .week] {
            let empty = page.curveSummary(range: range, historyPoints: [])
            XCTAssertEqual(empty.meanText, "—", range.title)
            XCTAssertEqual(empty.peakText, "—", range.title)

            let gaps = page.curveSummary(range: range, historyPoints: [nil, nil])
            XCTAssertEqual(gaps.meanText, "—", range.title)
            XCTAssertEqual(gaps.peakText, "—", range.title)
        }
    }

    func testStoredZeroIsAPointAndAGapIsNotZero() {
        let summary = GPUPageState.initial.curveSummary(range: .hour, historyPoints: [nil, 0, 10])

        XCTAssertEqual(summary.meanText, "5.0%")
        XCTAssertEqual(summary.peakText, "10.0%")
    }

    func testNonFiniteSamplesAreNotNumbers() {
        var page = GPUPageState.initial
        page.history.record(percent: .nan, at: Date(timeIntervalSince1970: 1))
        page.history.record(percent: 8, at: Date(timeIntervalSince1970: 2))
        page.history.record(percent: .infinity, at: Date(timeIntervalSince1970: 3))

        let summary = page.curveSummary(range: .live, historyPoints: [])

        XCTAssertEqual(summary.meanText, "8.0%")
        XCTAssertEqual(summary.peakText, "8.0%")
    }

    func testShareBarClampsAboveOneHundredAndOmitsAMissingPercent() {
        XCTAssertEqual(shareRow(percent: 140, text: "140.0%").barFraction, 1)
        XCTAssertEqual(shareRow(percent: 100, text: "100.0%").barFraction, 1)
        XCTAssertNil(shareRow(percent: nil, text: "—").barFraction)
    }

    func testShareBarKeepsAnEmptyTrackForRealZero() {
        XCTAssertEqual(shareRow(percent: 0, text: "0.0%").barFraction, 0)
        XCTAssertEqual(shareRow(percent: 25, text: "25.0%").barFraction, 0.25)
    }

    private func shareRow(percent: Double?, text: String) -> GPUShareRow {
        GPUShareRow(
            pid: 10,
            name: "Safari",
            percent: percent,
            shareText: text,
            bundleIdentifier: nil,
            executablePath: nil
        )
    }
}
