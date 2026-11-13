import XCTest
@testable import SamplingCore

/// Memory-page 换入 / 换出. Counters and a sample time in; the two byte rates out.
/// No Darwin, no curve, and no disk throughput.
final class MemoryPageTests: XCTestCase {
    func testFirstFrameStaysMissingInsteadOfZero() {
        let page = succeed(pageins: 1_000, pageouts: 40, at: 10)

        XCTAssertNil(page.pageInBytesPerSecond)
        XCTAssertNil(page.pageOutBytesPerSecond)
        XCTAssertEqual(page.pageInText, "—")
        XCTAssertEqual(page.pageOutText, "—")
        XCTAssertNotEqual(page.pageInText, "0 字节/秒")
        XCTAssertNotEqual(page.pageOutText, "0 字节/秒")
    }

    func testUnchangedCountersAreZeroBytesPerSecond() {
        let first = succeed(pageins: 1_000, pageouts: 40, at: 10)
        let page = succeed(pageins: 1_000, pageouts: 40, at: 12, current: first)

        XCTAssertEqual(page.pageInBytesPerSecond, 0)
        XCTAssertEqual(page.pageOutBytesPerSecond, 0)
        XCTAssertEqual(page.pageInText, "0 字节/秒")
        XCTAssertEqual(page.pageOutText, "0 字节/秒")
    }

    func testPageDeltaTimesPageSizeOverElapsedTime() {
        let first = succeed(pageins: 1_000, pageouts: 40, at: 10)
        let page = succeed(pageins: 1_100, pageouts: 42, at: 12, current: first)

        XCTAssertEqual(page.pageInBytesPerSecond, 204_800)
        XCTAssertEqual(page.pageOutBytesPerSecond, 4_096)
        XCTAssertEqual(page.pageInText, "200 KB/秒")
        XCTAssertEqual(page.pageOutText, "4 KB/秒")
    }

    func testCounterRewindStaysMissingAndBecomesTheNextBaseline() {
        let first = succeed(pageins: 1_000, pageouts: 40, at: 10)
        let rewound = succeed(pageins: 999, pageouts: 50, at: 12, current: first)

        XCTAssertNil(rewound.pageInBytesPerSecond)
        XCTAssertNil(rewound.pageOutBytesPerSecond)
        XCTAssertEqual(rewound.pageInText, "—")
        XCTAssertEqual(rewound.pageOutText, "—")

        let next = succeed(pageins: 999, pageouts: 50, at: 14, current: rewound)
        XCTAssertEqual(next.pageInBytesPerSecond, 0)
        XCTAssertEqual(next.pageOutBytesPerSecond, 0)
        XCTAssertEqual(next.pageInText, "0 字节/秒")
    }

    func testUnreadCountersStayMissingWithoutDroppingTheBaseline() {
        let first = succeed(pageins: 1_000, pageouts: 40, at: 10)
        let unread = MemoryPageProjection.apply(
            counters: nil,
            sampledAt: Date(timeIntervalSince1970: 12),
            current: first
        )

        XCTAssertNil(unread.pageInBytesPerSecond)
        XCTAssertNil(unread.pageOutBytesPerSecond)
        XCTAssertEqual(unread.pageInText, "—")
        XCTAssertEqual(unread.pageOutText, "—")

        let resumed = succeed(pageins: 1_000, pageouts: 40, at: 14, current: unread)
        XCTAssertEqual(resumed.pageInBytesPerSecond, 0)
        XCTAssertEqual(resumed.pageOutText, "0 字节/秒")
    }

    func testZeroPageSizeStaysMissingAndDoesNotReplaceTheBaseline() {
        let first = succeed(pageins: 1_000, pageouts: 40, at: 10)
        let unread = succeed(pageins: 1_100, pageouts: 40, pageSize: 0, at: 12, current: first)

        XCTAssertNil(unread.pageInBytesPerSecond)
        XCTAssertEqual(unread.pageInText, "—")
        XCTAssertNotEqual(unread.pageInText, "0 字节/秒")

        let resumed = succeed(pageins: 1_100, pageouts: 40, at: 14, current: unread)
        XCTAssertEqual(resumed.pageInBytesPerSecond, 102_400)
        XCTAssertEqual(resumed.pageInText, "100 KB/秒")
        XCTAssertEqual(resumed.pageOutText, "0 字节/秒")
    }

    func testNonPositiveIntervalStaysMissing() {
        let first = succeed(pageins: 1_000, pageouts: 40, at: 10)
        let sameTime = succeed(pageins: 1_100, pageouts: 50, at: 10, current: first)
        let backwards = succeed(pageins: 1_200, pageouts: 60, at: 9, current: first)

        XCTAssertNil(sameTime.pageInBytesPerSecond)
        XCTAssertNil(backwards.pageOutBytesPerSecond)
        XCTAssertEqual(sameTime.pageInText, "—")
        XCTAssertEqual(backwards.pageOutText, "—")
        XCTAssertNotEqual(sameTime.pageInText, "0 字节/秒")

        let next = succeed(pageins: 1_100, pageouts: 50, at: 12, current: sameTime)
        XCTAssertEqual(next.pageInBytesPerSecond, 0)
        XCTAssertEqual(next.pageOutText, "0 字节/秒")
    }

    func testAcceptedFramesPublishPageRatesOnAnyPage() {
        var core = DashboardCore(ownPid: 7)
        let first = frame(pageins: 1_000, pageouts: 40, at: 10)
        let opened = core.apply(result: success(first), accepted: true, page: .cpu)
        XCTAssertEqual(opened, [.applyRisingAndWindowedSelection])
        XCTAssertEqual(core.memoryPage.pageInText, "—")
        XCTAssertEqual(core.memoryPage.pageOutText, "—")
        XCTAssertNil(core.memoryPage.pageInBytesPerSecond)

        let second = frame(pageins: 1_100, pageouts: 40, at: 12)
        _ = core.apply(result: success(second), accepted: true, page: .memory)
        XCTAssertEqual(core.memoryPage.pageInBytesPerSecond, 204_800)
        XCTAssertEqual(core.memoryPage.pageInText, "200 KB/秒")
        XCTAssertEqual(core.memoryPage.pageOutBytesPerSecond, 0)
        XCTAssertEqual(core.memoryPage.pageOutText, "0 字节/秒")

        let ignored = frame(pageins: 2_000, pageouts: 80, at: 14)
        let rejected = core.apply(result: success(ignored), accepted: false, page: .memory)
        XCTAssertEqual(rejected, [])
        XCTAssertEqual(core.memoryPage.pageInText, "200 KB/秒")

        let failed = core.apply(result: .failure(PageRateDeliveryError.unavailable), accepted: true, page: .memory)
        XCTAssertEqual(failed, [])
        XCTAssertEqual(core.memoryPage.pageInBytesPerSecond, 204_800)
        XCTAssertEqual(core.memoryPage.pageOutText, "0 字节/秒")

        let unread = frame(pageins: nil, pageouts: nil, at: 16)
        _ = core.apply(result: success(unread), accepted: true, page: .disk)
        XCTAssertEqual(core.memoryPage.pageInText, "—")
        XCTAssertEqual(core.memoryPage.pageOutText, "—")

        let resumed = frame(pageins: 1_100, pageouts: 40, at: 18)
        _ = core.apply(result: success(resumed), accepted: true, page: .network)
        XCTAssertEqual(core.memoryPage.pageInBytesPerSecond, 0)
        XCTAssertEqual(core.memoryPage.pageOutText, "0 字节/秒")
    }

    private func success(_ frame: SampledFrame) -> Result<SampledFrame, PageRateDeliveryError> {
        .success(frame)
    }

    private func frame(pageins: UInt64?, pageouts: UInt64?, at time: TimeInterval) -> SampledFrame {
        let capturedAt = Date(timeIntervalSince1970: time)
        let counters: HostPageCounters?
        if let pageins, let pageouts {
            counters = HostPageCounters(pageins: pageins, pageouts: pageouts, pageSize: 4_096)
        } else {
            counters = nil
        }
        return SampledFrame(
            snapshot: MemorySnapshot(
                usedBytes: 12_000,
                totalBytes: 32_000,
                breakdown: MemoryBreakdown(
                    appBytes: 8_000,
                    wiredBytes: 2_000,
                    compressedBytes: 1_000,
                    cachedBytes: 500
                ),
                pressure: .normal,
                pressureMetric: 0.2,
                pressureSeries: [],
                capturedAt: capturedAt
            ),
            rows: [],
            detail: nil,
            processListFailed: false,
            systemCpuPercent: nil,
            hostNetworkRates: .missing,
            hostDiskRates: .missing,
            hostPageCounters: counters
        )
    }

    private func succeed(
        pageins: UInt64,
        pageouts: UInt64,
        pageSize: UInt64 = 4_096,
        at time: TimeInterval,
        current: MemoryPageState = .initial
    ) -> MemoryPageState {
        MemoryPageProjection.apply(
            counters: HostPageCounters(pageins: pageins, pageouts: pageouts, pageSize: pageSize),
            sampledAt: Date(timeIntervalSince1970: time),
            current: current
        )
    }
}

private enum PageRateDeliveryError: Error {
    case unavailable
}
