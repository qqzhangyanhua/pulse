import Foundation

struct MachineOSVersion: Equatable, Sendable {
    var major: Int
    var minor: Int
    var patch: Int
}

enum MachinePowerSource: Equatable, Sendable {
    case battery
    case adapter
    case unknown
}

struct MachinePower: Equatable, Sendable {
    var source: MachinePowerSource
    /// Integer percent. Nil is missing, including a desktop Mac with no battery. Zero is a real empty battery.
    var batteryPercent: Int?
    var lowPowerMode: Bool
}

struct MachineVolume: Equatable, Sendable {
    /// Nil is an unread key. Zero is a full volume.
    var availableBytes: UInt64?
    /// Nil, or a reported total of 0, is unread. There is no zero-byte system volume.
    var totalBytes: UInt64?
}

/// Facts already read from the host. This type does not sample.
struct MachineFacts: Equatable, Sendable {
    var chipName: String?
    var os: MachineOSVersion
    var uptime: TimeInterval
    var power: MachinePower
    var volume: MachineVolume
}

enum MachinePageCopy {
    static func chipValue(_ name: String?) -> String {
        let trimmed = name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? "—" : trimmed
    }

    static func chipLine(_ name: String?) -> String {
        "芯片 · \(chipValue(name))"
    }

    static func osValue(_ version: MachineOSVersion) -> String {
        "macOS \(version.major).\(version.minor).\(version.patch)"
    }

    static func osLine(_ version: MachineOSVersion) -> String {
        "系统 · \(osValue(version))"
    }

    static func uptimeValue(_ seconds: TimeInterval) -> String {
        let whole = seconds >= 0 ? Int(seconds) : 0
        if whole < 60 { return "不到 1 分钟" }
        let days = whole / 86_400
        let hours = (whole % 86_400) / 3_600
        let minutes = (whole % 3_600) / 60
        var parts: [String] = []
        if days > 0 { parts.append("\(days) 天") }
        if hours > 0 { parts.append("\(hours) 小时") }
        if minutes > 0 { parts.append("\(minutes) 分钟") }
        return parts.joined(separator: " ")
    }

    static func uptimeLine(_ seconds: TimeInterval) -> String {
        "已开机 · \(uptimeValue(seconds))"
    }

    static func powerLine(source: MachinePowerSource, percent: Int?, lowPowerMode: Bool) -> String {
        let sourceText: String
        switch source {
        case .battery:
            sourceText = "电池"
        case .adapter:
            sourceText = "外接电源"
        case .unknown:
            sourceText = "—"
        }
        var parts = ["电源", sourceText]
        if source != .unknown, let percent, percent >= 0 {
            parts.append("\(percent)%")
        }
        if lowPowerMode {
            parts.append("低电量模式")
        }
        return parts.joined(separator: " · ")
    }

    /// Big number on the power card. Percent wins. A desktop Mac with no battery keeps the source word.
    static func powerValue(source: MachinePowerSource, percent: Int?) -> String {
        if source != .unknown, let percent, percent >= 0 {
            return "\(percent)%"
        }
        switch source {
        case .battery:
            return "电池"
        case .adapter:
            return "外接电源"
        case .unknown:
            return "—"
        }
    }

    static func volumeValue(available: UInt64?, total: UInt64?) -> String {
        guard let available, let total, total > 0 else { return "—" }
        return ByteFormat.memory(available)
    }

    static func volumeLine(available: UInt64?, total: UInt64?) -> String {
        guard let available, let total, total > 0 else { return "磁盘剩余 · —" }
        return "磁盘剩余 · 可用 \(ByteFormat.memory(available)) / 共 \(ByteFormat.memory(total))"
    }

    /// Same string the other pages already show. Nil hides the row.
    static func thermalLine(_ notice: String?) -> String? {
        guard let notice, !notice.isEmpty else { return nil }
        return notice
    }

    static func factLines(_ facts: MachineFacts) -> [String] {
        [
            chipLine(facts.chipName),
            osLine(facts.os),
            uptimeLine(facts.uptime),
            powerLine(
                source: facts.power.source,
                percent: facts.power.batteryPercent,
                lowPowerMode: facts.power.lowPowerMode
            ),
            volumeLine(available: facts.volume.availableBytes, total: facts.volume.totalBytes),
        ]
    }

    static func accessibilityLabel(facts: MachineFacts, thermalNotice: String?) -> String {
        var lines = factLines(facts)
        if let thermal = thermalLine(thermalNotice) {
            lines.append(thermal)
        }
        return lines.joined(separator: "，")
    }
}
