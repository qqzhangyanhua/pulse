import Foundation

/// Cumulative `ri_billed_energy` (nanojoules) and `ri_pkg_idle_wkups` for one process.
struct EnergyTick: Sendable, Equatable {
    let billedNanojoules: UInt64
    let idleWakeups: UInt64
    let date: Date
}

struct ProcessEnergyRates: Sendable, Equatable {
    let watts: Double?
    let idleWakeupsPerSecond: Double?

    static let missing = ProcessEnergyRates(watts: nil, idleWakeupsPerSecond: nil)
}

struct ProcessEnergySample: Sendable, Equatable {
    let rates: ProcessEnergyRates
    let baseline: EnergyTick?
}

/// Two-frame wall-clock process energy. A missed rusage keeps the last baseline.
enum ProcessEnergyLoad {
    static func rates(previous: EnergyTick?, current: EnergyTick) -> ProcessEnergyRates {
        guard let previous,
              current.billedNanojoules >= previous.billedNanojoules,
              current.idleWakeups >= previous.idleWakeups
        else {
            return .missing
        }
        let seconds = current.date.timeIntervalSince(previous.date)
        guard seconds > 0 else { return .missing }
        let nanojoules = current.billedNanojoules - previous.billedNanojoules
        let wakeups = current.idleWakeups - previous.idleWakeups
        return ProcessEnergyRates(
            watts: Double(nanojoules) / seconds / 1e9,
            idleWakeupsPerSecond: Double(wakeups) / seconds
        )
    }

    static func advance(previous: EnergyTick?, reading: EnergyTick?) -> ProcessEnergySample {
        guard let reading else {
            return ProcessEnergySample(rates: .missing, baseline: previous)
        }
        return ProcessEnergySample(
            rates: rates(previous: previous, current: reading),
            baseline: reading
        )
    }
}

struct PartialReadingSum: Sendable, Equatable {
    let value: Double?
    let isPartial: Bool
}

/// Sums present members only. Not `AppGroupProjection.sum`, which drops the total when any member is nil.
enum ProcessEnergyGroup {
    static func sum(_ values: [Double?]) -> PartialReadingSum {
        var total = 0.0
        var present = 0
        for value in values {
            guard let value else { continue }
            total += value
            present += 1
        }
        guard present > 0 else {
            return PartialReadingSum(value: nil, isPartial: false)
        }
        return PartialReadingSum(value: total, isPartial: present < values.count)
    }
}

/// Cell text. Watts, not an Activity Monitor energy-impact score. Missing stays 「—」.
enum ProcessEnergyText {
    static let missing = "—"
    static let partial = "部分读数"
    static let impactTitle = "能耗影响"
    static let idleWakeTitle = "空闲唤醒"

    static func caption(isPartial: Bool) -> String {
        isPartial ? partial : ""
    }

    static func watts(_ value: Double?) -> String {
        guard let value else { return missing }
        return String(format: "%.1f W", locale: Locale(identifier: "en_US_POSIX"), value)
    }

    static func wakeups(_ value: Double?) -> String {
        guard let value else { return missing }
        return String(format: "%.1f 次/秒", locale: Locale(identifier: "en_US_POSIX"), value)
    }
}
