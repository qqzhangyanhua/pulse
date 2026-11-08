import Foundation

/// Menu-bar title beside the pressure dot. Absent preference stays `.dot` so an upgrade does not widen the bar.
enum MenuBarReadingMode: String, Equatable, Sendable, CaseIterable {
    case dot
    case usedMemory
    case cpu

    static func resolved(stored raw: String?) -> MenuBarReadingMode {
        guard let raw, let mode = MenuBarReadingMode(rawValue: raw) else { return .dot }
        return mode
    }

    var settingsLabel: String {
        switch self {
        case .dot:
            return "仅色点"
        case .usedMemory:
            return "色点 + 已用内存"
        case .cpu:
            return "色点 + CPU"
        }
    }
}

enum MenuBarReadingCopy {
    static let openSettingsTitle = "设置"
}

/// Status-item title. Dot mode is empty, never an em dash. A nil reading stays 「—」 and is not invented as 0.
enum MenuBarReadingTitle {
    static let missing = "—"

    static func string(mode: MenuBarReadingMode, usedBytes: UInt64?, cpuPercent: Double?) -> String {
        switch mode {
        case .dot:
            return ""
        case .usedMemory:
            guard let usedBytes else { return missing }
            return ByteFormat.memory(usedBytes)
        case .cpu:
            guard let cpuPercent else { return missing }
            return CPUPercentText.string(cpuPercent)
        }
    }
}

/// Square item for the dot. A reading uses variable width with the image in front.
enum MenuBarStatusItemLayout: Equatable, Sendable {
    case dot
    case reading

    static func resolve(mode: MenuBarReadingMode) -> MenuBarStatusItemLayout {
        switch mode {
        case .dot:
            return .dot
        case .usedMemory, .cpu:
            return .reading
        }
    }
}

enum MenuBarReadingPreference {
    static let defaultsKey = "pulse.menuBarReading"

    static func mode(in defaults: UserDefaults = .standard) -> MenuBarReadingMode {
        MenuBarReadingMode.resolved(stored: defaults.string(forKey: defaultsKey))
    }

    static func store(_ mode: MenuBarReadingMode, in defaults: UserDefaults = .standard) {
        defaults.set(mode.rawValue, forKey: defaultsKey)
    }
}
