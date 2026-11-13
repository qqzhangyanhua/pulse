import Foundation

/// Curve window on the memory, CPU, network, disk, and GPU pages. Live stays in memory.
enum HistoryCurveRange: String, Equatable, Hashable, CaseIterable, Sendable {
    case live
    case hour
    case day
    case week

    var title: String {
        switch self {
        case .live: return "实时"
        case .hour: return "1 小时"
        case .day: return "24 小时"
        case .week: return "7 天"
        }
    }

    /// Nil while the page uses the in-memory ring. Minute rows feed the day and the week.
    var query: (duration: TimeInterval, minute: Bool)? {
        switch self {
        case .live:
            return nil
        case .hour:
            return (3600, false)
        case .day:
            return (86_400, true)
        case .week:
            return (7 * 86_400, true)
        }
    }
}

struct HistoryCurvePoint: Identifiable, Equatable, Sendable {
    var id: Int
    var at: Date
    var value: Double?
}

struct HistoryCurveMark: Identifiable, Equatable, Sendable {
    var id: Int
    var at: Date
    var label: String
}

struct HistoryStoredEvent: Equatable, Sendable {
    var at: Date
    var event: HistoryEvent
}

/// Points and marks for one non-live curve. Nil means the page is still on 「实时」.
struct HistoryCurvePlot: Equatable, Sendable {
    var points: [HistoryCurvePoint]
    var marks: [HistoryCurveMark]
}

enum HistoryCurveSeries {
    static func label(_ event: HistoryEvent) -> String {
        switch event {
        case .sleep:
            return "睡眠"
        case .wake:
            return "唤醒"
        case .thermal:
            return "热状态"
        case .pressure:
            return "压力"
        }
    }

    /// Raw samples in order. A field that is nil stays nil. A hole longer than `gap` is one nil point, not 0.
    static func raw(
        samples: [HistorySample],
        from start: Date,
        to end: Date,
        gap: TimeInterval = 6,
        value: (HistorySample) -> Double?
    ) -> [HistoryCurvePoint] {
        let kept = samples
            .filter { $0.at >= start && $0.at <= end }
            .sorted { $0.at < $1.at }
        var points: [HistoryCurvePoint] = []
        var previous: Date?
        for sample in kept {
            if let previous, sample.at.timeIntervalSince(previous) > gap {
                points.append(HistoryCurvePoint(id: points.count, at: previous.addingTimeInterval(gap), value: nil))
            }
            points.append(HistoryCurvePoint(id: points.count, at: sample.at, value: value(sample)))
            previous = sample.at
        }
        return points
    }

    /// One point per bucket. A missing row is nil. A nil field stays nil. Nothing is written as 0.
    static func buckets(
        samples: [HistorySample],
        from start: Date,
        to end: Date,
        step: TimeInterval,
        value: (HistorySample) -> Double?
    ) -> [HistoryCurvePoint] {
        guard step >= 1, end >= start else { return [] }
        let origin = bucketStart(start, step: step)
        let last = bucketStart(end, step: step)
        let width = Int((last.timeIntervalSince(origin) / step).rounded(.down))
        guard width >= 0, width < 20_000 else { return [] }
        var latest: [Date: HistorySample] = [:]
        for sample in samples where sample.at >= start && sample.at <= end {
            let bucket = bucketStart(sample.at, step: step)
            if let current = latest[bucket], current.at > sample.at { continue }
            latest[bucket] = sample
        }
        return (0...width).map { index in
            let at = origin.addingTimeInterval(TimeInterval(index) * step)
            return HistoryCurvePoint(id: index, at: at, value: latest[at].flatMap(value))
        }
    }

    static func marks(_ events: [HistoryStoredEvent]) -> [HistoryCurveMark] {
        events.enumerated().map { index, row in
            HistoryCurveMark(id: index, at: row.at, label: label(row.event))
        }
    }

    private static func bucketStart(_ date: Date, step: TimeInterval) -> Date {
        let whole = Int64(date.timeIntervalSince1970.rounded(.down))
        let width = Int64(step.rounded(.down))
        guard width > 0 else { return date }
        let remainder = whole % width
        guard remainder >= 0 else { return date }
        return Date(timeIntervalSince1970: TimeInterval(whole - remainder))
    }
}
