import Foundation

/// Cumulative `ri_energy_nj` (nanojoules) and `ri_interrupt_wkups` for one process.
struct EnergyTick: Sendable, Equatable {
    let energyNanojoules: UInt64
    let interruptWakeups: UInt64
    let date: Date
}

struct ProcessEnergyRates: Sendable, Equatable {
    let watts: Double?
    let wakeupsPerSecond: Double?

    static let missing = ProcessEnergyRates(watts: nil, wakeupsPerSecond: nil)
}

struct ProcessEnergySample: Sendable, Equatable {
    let rates: ProcessEnergyRates
    let baseline: EnergyTick?
}

/// Two-frame wall-clock process energy. A missed rusage keeps the last baseline.
enum ProcessEnergyLoad {
    static func rates(previous: EnergyTick?, current: EnergyTick) -> ProcessEnergyRates {
        guard let previous,
              current.energyNanojoules >= previous.energyNanojoules,
              current.interruptWakeups >= previous.interruptWakeups
        else {
            return .missing
        }
        let seconds = current.date.timeIntervalSince(previous.date)
        guard seconds > 0 else { return .missing }
        let nanojoules = current.energyNanojoules - previous.energyNanojoules
        let wakeups = current.interruptWakeups - previous.interruptWakeups
        return ProcessEnergyRates(
            watts: Double(nanojoules) / seconds / 1e9,
            wakeupsPerSecond: Double(wakeups) / seconds
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
    static let wakeTitle = "唤醒"
    private static let posix = Locale(identifier: "en_US_POSIX")

    static func caption(isPartial: Bool) -> String {
        isPartial ? partial : ""
    }

    static func watts(_ value: Double?) -> String {
        guard let value else { return missing }
        return String(format: "%.1f W", locale: posix, value)
    }

    static func wakeups(_ value: Double?) -> String {
        guard let value else { return missing }
        return String(format: "%.1f 次/秒", locale: posix, value)
    }
}
