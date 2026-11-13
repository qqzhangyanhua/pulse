import Foundation

enum HistoryRetention: Equatable {
    case days(Int)

    var seconds: TimeInterval {
        switch self {
        case let .days(count):
            return TimeInterval(count) * 24 * 3600
        }
    }
}

struct HistorySample: Equatable {
    var at: Date
    var usedBytes: UInt64?
    var pressure: PressureLevel?
    var swapUsedBytes: UInt64?
    var cpuPercent: Double?
    var networkInBytesPerSecond: Double?
    var networkOutBytesPerSecond: Double?
    var diskReadBytesPerSecond: Double?
    var diskWriteBytesPerSecond: Double?
    var gpuPercent: Double?
}

struct HistoryMinute: Equatable {
    var cpuPercent: Double?
}

struct HistoryProcessCandidate {
    var pid: Int32
    var name: String
    var primary: Double?
}

struct HistoryProcessRank: Equatable {
    var pid: Int32
    var name: String
    var primary: Double
}

struct HistoryDraft: Equatable {
    var sample: HistorySample
    var top: [HistoryProcessRank]
    var events: [HistoryEvent]
    var dropRawBefore: Date
}

enum HistoryLifecycle {
    case sleep
    case wake
}

enum HistoryEvent: Equatable {
    case pressure(String)
    case thermal(String)
    case sleep
    case wake
}

enum HistoryPolicy {
    static func dropRaw(before now: Date) -> Date {
        now.addingTimeInterval(-3600)
    }

    static func rawSamples(from samples: [HistorySample], now: Date) -> [HistorySample] {
        samples.filter { sample in
            let age = now.timeIntervalSince(sample.at)
            return age >= 0 && age <= 3600
        }
    }

    static func minuteBuckets(
        from samples: [HistorySample],
        now: Date,
        retention: HistoryRetention
    ) -> [HistoryMinute] {
        buckets(from: samples, now: now, retention: retention, step: 60)
    }

    static func quarterHourBuckets(
        from samples: [HistorySample],
        now: Date,
        retention: HistoryRetention
    ) -> [HistoryMinute] {
        buckets(from: samples, now: now, retention: retention, step: 900)
    }

    static func topProcesses(_ rows: [HistoryProcessCandidate], limit: Int) -> [HistoryProcessRank] {
        rows
            .filter { $0.primary != nil }
            .sorted { ($0.primary ?? 0) > ($1.primary ?? 0) }
            .prefix(limit)
            .compactMap { row -> HistoryProcessRank? in
                guard let primary = row.primary else { return nil }
                return HistoryProcessRank(pid: row.pid, name: row.name, primary: primary)
            }
    }

    static func events(
        previousPressure: PressureLevel?,
        pressure: PressureLevel?,
        thermal: String?,
        previousThermal: String?,
        lifecycle: HistoryLifecycle?
    ) -> [HistoryEvent] {
        var emitted: [HistoryEvent] = []
        if let pressure, pressure != previousPressure {
            emitted.append(.pressure(pressure.rawValue))
        }
        if let thermal, thermal != previousThermal {
            emitted.append(.thermal(thermal))
        }
        switch lifecycle {
        case .sleep:
            emitted.append(.sleep)
        case .wake:
            emitted.append(.wake)
        case nil:
            break
        }
        return emitted
    }

    private static func buckets(
        from samples: [HistorySample],
        now: Date,
        retention: HistoryRetention,
        step: TimeInterval
    ) -> [HistoryMinute] {
        let kept = samples.filter { sample in
            let age = now.timeIntervalSince(sample.at)
            return age >= 0 && age <= retention.seconds
        }
        guard let origin = kept.map(\.at).min() else { return [] }
        let count = Int(now.timeIntervalSince(origin) / step) + 1
        guard count > 0 else { return [] }
        var points = Array(repeating: HistoryMinute(cpuPercent: nil), count: count)
        for sample in kept.sorted(by: { $0.at < $1.at }) {
            let index = Int(sample.at.timeIntervalSince(origin) / step)
            guard index >= 0, index < count else { continue }
            points[index].cpuPercent = sample.cpuPercent
        }
        return points
    }
}
