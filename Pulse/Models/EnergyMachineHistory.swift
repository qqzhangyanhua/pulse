import Foundation

struct EnergyHistoryPoint: Equatable, Sendable {
    let minuteStart: Date
    let watts: Double?
    let batteryPercent: Double?
}

/// In-memory process-sum curve. A missing minute stays nil, never 0. Not `SystemCPUHistory`.
struct EnergyMachineHistory: Equatable, Sendable {
    private struct MinuteTotals: Equatable, Sendable {
        var wattSum = 0.0
        var wattCount = 0
        var batterySum = 0.0
        var batteryCount = 0

        mutating func add(processWatts: Double?, batteryPercent: Double?) {
            if let processWatts {
                wattSum += processWatts
                wattCount += 1
            }
            if let batteryPercent {
                batterySum += batteryPercent
                batteryCount += 1
            }
        }

        var watts: Double? {
            wattCount > 0 ? wattSum / Double(wattCount) : nil
        }

        var batteryPercent: Double? {
            batteryCount > 0 ? batterySum / Double(batteryCount) : nil
        }
    }

    private static let minuteCount = 240

    private var minutes: [Int: MinuteTotals] = [:]
    private var newestMinute: Int?

    var points: [EnergyHistoryPoint] {
        guard let newestMinute else { return [] }
        let oldest = newestMinute - (Self.minuteCount - 1)
        return (oldest...newestMinute).map { minute in
            let totals = minutes[minute]
            return EnergyHistoryPoint(
                minuteStart: Self.date(minute),
                watts: totals?.watts,
                batteryPercent: totals?.batteryPercent
            )
        }
    }

    mutating func record(processWatts: Double?, batteryPercent: Double?, at date: Date) {
        let minute = Self.minuteIndex(date)
        var totals = minutes[minute] ?? MinuteTotals()
        totals.add(processWatts: processWatts, batteryPercent: batteryPercent)
        minutes[minute] = totals
        newestMinute = max(newestMinute ?? minute, minute)
        let oldest = (newestMinute ?? minute) - (Self.minuteCount - 1)
        minutes = minutes.filter { $0.key >= oldest }
    }

    /// Same epoch floor as the minute ledger: `floor(seconds / 60) * 60`.
    private static func minuteIndex(_ date: Date) -> Int {
        Int(floor(date.timeIntervalSince1970 / 60))
    }

    private static func date(_ minute: Int) -> Date {
        Date(timeIntervalSince1970: Double(minute) * 60)
    }
}
