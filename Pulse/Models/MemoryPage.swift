import Foundation

/// One host `pageins` / `pageouts` reading. Not a per-process counter and not disk throughput.
struct HostPageCounters: Equatable, Sendable {
    var pageins: UInt64
    var pageouts: UInt64
    var pageSize: UInt64
}

/// Previous host counters. The next frame supplies the page size.
struct MemoryPageBaseline: Equatable, Sendable {
    var pageins: UInt64
    var pageouts: UInt64
    var capturedAt: Date
}

/// Published 换入 / 换出 rates. Nil is missing, not zero. There is no curve.
struct MemoryPageState: Equatable, Sendable {
    var pageInBytesPerSecond: Double?
    var pageOutBytesPerSecond: Double?
    var baseline: MemoryPageBaseline?

    var pageInText: String { NetworkRateText.string(pageInBytesPerSecond) }

    var pageOutText: String { NetworkRateText.string(pageOutBytesPerSecond) }

    static let initial = MemoryPageState(
        pageInBytesPerSecond: nil,
        pageOutBytesPerSecond: nil,
        baseline: nil
    )
}

enum MemoryPageCopy {
    static let pageIn = "换入"
    static let pageOut = "换出"
    static let pageInCaption = "读进内存"
    static let pageOutCaption = "写到磁盘"
}

enum MemoryPageProjection {
    /// Page delta times page size, divided by elapsed time. No `Date()` of its own.
    static func apply(
        counters: HostPageCounters?,
        sampledAt: Date?,
        current: MemoryPageState
    ) -> MemoryPageState {
        guard let counters, let sampledAt, counters.pageSize > 0 else {
            return MemoryPageState(
                pageInBytesPerSecond: nil,
                pageOutBytesPerSecond: nil,
                baseline: current.baseline
            )
        }
        let reading = MemoryPageBaseline(
            pageins: counters.pageins,
            pageouts: counters.pageouts,
            capturedAt: sampledAt
        )
        let rates = byteRates(previous: current.baseline, current: reading, pageSize: counters.pageSize)
        return MemoryPageState(
            pageInBytesPerSecond: rates.pageIn,
            pageOutBytesPerSecond: rates.pageOut,
            baseline: reading
        )
    }

    private static func byteRates(
        previous: MemoryPageBaseline?,
        current: MemoryPageBaseline,
        pageSize: UInt64
    ) -> (pageIn: Double?, pageOut: Double?) {
        guard let previous else { return (nil, nil) }
        let seconds = current.capturedAt.timeIntervalSince(previous.capturedAt)
        guard seconds > 0,
              current.pageins >= previous.pageins,
              current.pageouts >= previous.pageouts
        else {
            return (nil, nil)
        }
        guard let pageIn = bytesPerSecond(
            pages: current.pageins - previous.pageins,
            pageSize: pageSize,
            seconds: seconds
        ), let pageOut = bytesPerSecond(
            pages: current.pageouts - previous.pageouts,
            pageSize: pageSize,
            seconds: seconds
        ) else {
            return (nil, nil)
        }
        return (pageIn, pageOut)
    }

    private static func bytesPerSecond(pages: UInt64, pageSize: UInt64, seconds: Double) -> Double? {
        let (bytes, overflow) = pages.multipliedReportingOverflow(by: pageSize)
        guard !overflow, seconds.isFinite else { return nil }
        return Double(bytes) / seconds
    }
}
