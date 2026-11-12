import Foundation

enum EnergyBatterySupply: Equatable, Sendable {
    case battery
    case adapter
}

/// Plain inputs already read from the host. Not an IOKit type.
/// `remainingSeconds` is whole seconds. -1 is unknown, -2 is unlimited.
/// `minutesToFull` is whole minutes. Nil means the key was missing. -1 is still calculating. 0 is a real zero.
struct EnergyBatteryReading: Equatable, Sendable {
    var hasInternalBattery: Bool
    var percent: Int?
    var supply: EnergyBatterySupply?
    var charging: Bool
    var lowPowerMode: Bool
    var remainingSeconds: Int?
    var minutesToFull: Int?

    static let absent = EnergyBatteryReading(
        hasInternalBattery: false,
        percent: nil,
        supply: nil,
        charging: false,
        lowPowerMode: false,
        remainingSeconds: nil,
        minutesToFull: nil
    )
}

struct EnergyBatteryCard: Equatable, Sendable {
    var percent: String
    var power: String
    var lowPowerMode: String?
    var time: String
}

enum EnergyBattery {
    /// Nil hides the card. A desktop, or a UPS with no internal battery, stays nil.
    static func card(_ reading: EnergyBatteryReading) -> EnergyBatteryCard? {
        guard reading.hasInternalBattery else { return nil }
        return EnergyBatteryCard(
            percent: percentText(reading.percent),
            power: powerText(reading.supply),
            lowPowerMode: reading.lowPowerMode ? "低电量模式" : nil,
            time: timeText(reading)
        )
    }

    private static func percentText(_ percent: Int?) -> String {
        guard let percent, percent >= 0 else { return "—" }
        return "\(percent)%"
    }

    private static func powerText(_ supply: EnergyBatterySupply?) -> String {
        switch supply {
        case .battery:
            return "电池"
        case .adapter:
            return "电源适配器"
        case nil:
            return "—"
        }
    }

    private static func timeText(_ reading: EnergyBatteryReading) -> String {
        switch reading.supply {
        case .battery:
            return remainingText(reading.remainingSeconds)
        case .adapter where reading.charging:
            return fullText(reading.minutesToFull)
        case .adapter:
            return "已接通电源"
        case nil where reading.charging:
            return fullText(reading.minutesToFull)
        case nil:
            return "正在估算…"
        }
    }

    /// Finite seconds only. Leftover seconds after the first minute are dropped.
    private static func remainingText(_ seconds: Int?) -> String {
        guard let seconds, seconds >= 0 else { return "正在估算…" }
        if seconds < 60 {
            return "剩余 \(seconds) 秒"
        }
        let hours = seconds / 3_600
        let minutes = (seconds % 3_600) / 60
        return "剩余 \(clock(hours: hours, minutes: minutes))"
    }

    /// Minutes from the system. A missing key or a negative sentinel is not a duration.
    private static func fullText(_ minutes: Int?) -> String {
        guard let minutes, minutes >= 0 else { return "正在估算…" }
        return "充满还需 \(clock(hours: minutes / 60, minutes: minutes % 60))"
    }

    private static func clock(hours: Int, minutes: Int) -> String {
        switch (hours, minutes) {
        case (0, 0):
            return "0 分钟"
        case (0, _):
            return "\(minutes) 分钟"
        case (_, 0):
            return "\(hours) 小时"
        default:
            return "\(hours) 小时 \(minutes) 分钟"
        }
    }
}
