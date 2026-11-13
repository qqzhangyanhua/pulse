import Foundation

enum HistoryRetention: Equatable {
    case days(Int)

    var dayCount: Int {
        switch self {
        case let .days(count):
            return count
        }
    }

    var seconds: TimeInterval {
        switch self {
        case let .days(count):
            return TimeInterval(count) * 24 * 3600
        }
    }
}

enum HistoryRetentionPreference {
    static let defaultsKey = "pulse.historyRetentionDays"

    /// Absent key is 90 days. Anything other than 7, 30, or 90 is also 90.
    static func retention(in defaults: UserDefaults = .standard) -> HistoryRetention {
        guard defaults.object(forKey: defaultsKey) != nil else { return .days(90) }
        return resolved(defaults.integer(forKey: defaultsKey))
    }

    static func resolved(_ days: Int) -> HistoryRetention {
        switch days {
        case 7, 30, 90:
            return .days(days)
        default:
            return .days(90)
        }
    }
}

enum HistorySettingsCopy {
    static let localOnly = "历史只保存在这台 Mac 上"

    static func occupied(_ bytes: UInt64?) -> String {
        guard let bytes else { return "—" }
        return ByteFormat.memory(bytes)
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
    /// Last accepted tick in the minute bucket. Nil fields stay nil.
    var minute: HistorySample
    /// Last accepted tick in the quarter-hour bucket.
    var quarter: HistorySample
    var top: [HistoryProcessRank]
    /// Minute bucket of `sample.at`. The store replaces top rows at this instant.
    var topAt: Date
    var events: [HistoryEvent]
    var dropRawBefore: Date
    /// Minute rows older than this go away. The shorter of 7 days and the retention cutoff.
    var dropMinuteBefore: Date
    /// Quarter-hour rows, top processes, and events older than this go away.
    var retentionCutoff: Date
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
    static let minuteBucket: TimeInterval = 60
    static let quarterBucket: TimeInterval = 900

    static func dropRaw(before now: Date) -> Date {
        now.addingTimeInterval(-3600)
    }

    static func retentionCutoff(_ retention: HistoryRetention, now: Date) -> Date {
        now.addingTimeInterval(-retention.seconds)
    }

    /// Minute rows live at most 7 days, and never longer than the chosen retention.
    static func minuteDrop(before now: Date, retention: HistoryRetention) -> Date {
        max(retentionCutoff(.days(7), now: now), retentionCutoff(retention, now: now))
    }

    static func minuteBucketStart(_ date: Date) -> Date {
        bucketStart(date, step: minuteBucket)
    }

    static func quarterBucketStart(_ date: Date) -> Date {
        bucketStart(date, step: quarterBucket)
    }

    /// Copies every field. `at` is the floored bucket. A nil field stays nil.
    static func rolled(_ sample: HistorySample, step: TimeInterval) -> HistorySample {
        var copy = sample
        copy.at = bucketStart(sample.at, step: step)
        return copy
    }

    static func bucketStart(_ date: Date, step: TimeInterval) -> Date {
        guard step >= 1 else { return date }
        let whole = Int64(date.timeIntervalSince1970.rounded(.down))
        let width = Int64(step.rounded(.down))
        guard width > 0 else { return date }
        let remainder = whole % width
        guard remainder >= 0 else { return date }
        return Date(timeIntervalSince1970: TimeInterval(whole - remainder))
    }

    static func rawSamples(from samples: [HistorySample], now: Date) -> [HistorySample] {
        samples.filter { sample in
            let age = now.timeIntervalSince(sample.at)
            return age >= 0 && age <= 3600
        }
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
}
