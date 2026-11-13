import XCTest
@testable import SamplingCore

/// Literals are the retention rules from ticket #194. A missing minute is nil, never 0.
final class HistoryPolicyTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_700_000_000)

    func testRawTierDropsASampleOlderThanOneHour() {
        let fresh = sample(at: t0, cpu: 10)
        let stale = sample(at: t0.addingTimeInterval(-3601), cpu: 90)
        let kept = HistoryPolicy.rawSamples(from: [stale, fresh], now: t0)
        XCTAssertEqual(kept, [fresh])
    }

    func testOneMinuteBucketsCoverSevenDaysAndLeaveAGapNil() {
        let now = t0
        let start = now.addingTimeInterval(-120)
        let rows = [
            sample(at: start, cpu: 10),
            sample(at: now, cpu: 30),
        ]
        let buckets = HistoryPolicy.minuteBuckets(from: rows, now: now, retention: .days(7))
        XCTAssertEqual(buckets.count, 3)
        XCTAssertEqual(buckets[0].cpuPercent, 10)
        XCTAssertNil(buckets[1].cpuPercent)
        XCTAssertEqual(buckets[2].cpuPercent, 30)
        XCTAssertFalse(buckets.contains { $0.cpuPercent == 0 })
    }

    func testMinuteBucketsDropAnythingOlderThanSevenDays() {
        let old = sample(at: t0.addingTimeInterval(-(8 * 24 * 3600)), cpu: 40)
        let kept = HistoryPolicy.minuteBuckets(from: [old], now: t0, retention: .days(7))
        XCTAssertTrue(kept.isEmpty)
    }

    func testFifteenMinuteBucketsCoverNinetyDaysAndLeaveAGapNil() {
        let start = t0.addingTimeInterval(-30 * 60)
        let rows = [
            sample(at: start, cpu: 5),
            sample(at: start.addingTimeInterval(30 * 60), cpu: 15),
        ]
        let buckets = HistoryPolicy.quarterHourBuckets(from: rows, now: t0, retention: .days(90))
        XCTAssertEqual(buckets.map(\.cpuPercent), [5, nil, 15])
    }

    func testRetentionOfThirtyDaysDropsAnOlderQuarterHourPoint() {
        let old = sample(at: t0.addingTimeInterval(-(31 * 24 * 3600)), cpu: 8)
        let kept = HistoryPolicy.quarterHourBuckets(from: [old], now: t0, retention: .days(30))
        XCTAssertTrue(kept.isEmpty)
    }

    func testTopProcessesKeepsTenAndDoesNotRankANilPrimaryAsZero() {
        let ranked = (0..<12).map { HistoryProcessCandidate(pid: Int32($0), name: "p\($0)", primary: Double(100 - $0)) }
        let withNil = ranked + [HistoryProcessCandidate(pid: 99, name: "missing", primary: nil)]
        let top = HistoryPolicy.topProcesses(withNil, limit: 10)
        XCTAssertEqual(top.count, 10)
        XCTAssertEqual(top.first?.pid, 0)
        XCTAssertEqual(top.last?.pid, 9)
        XCTAssertFalse(top.contains { $0.pid == 99 })
        XCTAssertFalse(top.contains { $0.pid == 10 || $0.pid == 11 })
    }

    func testAHoleWherePulseDidNotRunStaysNil() {
        let only = sample(at: t0, cpu: 12)
        let queried = HistoryPolicy.minuteBuckets(
            from: [only],
            now: t0.addingTimeInterval(180),
            retention: .days(7)
        )
        let values = queried.map(\.cpuPercent)
        XCTAssertEqual(values.filter { $0 != nil }, [12])
        XCTAssertGreaterThanOrEqual(values.filter { $0 == nil }.count, 3)
    }

    func testPressureChangeAndSleepAreEventsNotZeroSamples() {
        let events = HistoryPolicy.events(
            previousPressure: .normal,
            pressure: .elevated,
            thermal: "serious",
            previousThermal: "nominal",
            lifecycle: .wake
        )
        XCTAssertEqual(events, [.pressure("elevated"), .thermal("serious"), .wake])
    }

    private func sample(at date: Date, cpu: Double?) -> HistorySample {
        HistorySample(
            at: date,
            usedBytes: 100,
            pressure: .normal,
            swapUsedBytes: nil,
            cpuPercent: cpu,
            networkInBytesPerSecond: nil,
            networkOutBytesPerSecond: nil,
            diskReadBytesPerSecond: nil,
            diskWriteBytesPerSecond: nil,
            gpuPercent: nil
        )
    }
}
