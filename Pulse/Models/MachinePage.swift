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
    /// `hw.model`, the same string as the toolbar. Nil when sysctl fails.
    var modelName: String?
    /// Same count the toolbar shows. The host reader reports at least 1.
    var coreCount: Int
    /// Nil when physical memory reads as 0. A Mac does not have zero bytes of RAM.
    var physicalMemoryBytes: UInt64?
    var os: MachineOSVersion
    var uptime: TimeInterval
    /// Read time minus a non-negative uptime. Nil when the caller has no clock.
    var bootedAt: Date?
    var power: MachinePower
    var volume: MachineVolume
}

enum MachinePageCopy {
    static func chipValue(_ name: String?) -> String {
        let trimmed = name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? "—" : trimmed
    }

    static func modelValue(_ name: String?) -> String {
        chipValue(name)
    }

    /// `12 核 · 18 GB`. A non-positive core count or unread RAM stays an em dash.
    static func capacityLine(coreCount: Int, physicalMemoryBytes: UInt64?) -> String {
        let cores = coreCount > 0 ? "\(coreCount) 核" : "—"
        let memory = physicalMemoryBytes.map { ByteFormat.gibWhole($0) } ?? "—"
        return "\(cores) · \(memory)"
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

    /// Card caption. Absolute local time, with no today/yesterday branch.
    static func bootCaption(_ date: Date?, calendar: Calendar = .current) -> String {
        guard let date else { return "—" }
        let parts = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        guard let year = parts.year, let month = parts.month, let day = parts.day,
              let hour = parts.hour, let minute = parts.minute else {
            return "—"
        }
        return String(format: "%d年%d月%d日 %02d:%02d 开机", year, month, day, hour, minute)
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

    /// Card caption. Adds only what the big number does not already say.
    /// Nil means the caption row stays blank. An unknown source stays an em dash.
    static func powerCaption(source: MachinePowerSource, percent: Int?, lowPowerMode: Bool) -> String? {
        let showsPercent = source != .unknown && (percent ?? -1) >= 0
        var parts: [String] = []
        if showsPercent {
            switch source {
            case .battery:
                parts.append("电池")
            case .adapter:
                parts.append("外接电源")
            case .unknown:
                break
            }
        }
        if lowPowerMode {
            parts.append("低电量模式")
        }
        if parts.isEmpty {
            return source == .unknown ? "—" : nil
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

    /// Card caption. Used percent is rounded. More available than total omits the percent.
    static func volumeCaption(available: UInt64?, total: UInt64?) -> String {
        guard let available, let total, total > 0 else { return "—" }
        let totalText = ByteFormat.memory(total)
        guard available <= total else { return "共 \(totalText)" }
        let used = ByteFormat.wholePercent(part: total - available, total: total)
        return "共 \(totalText) · 已用 \(used)"
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
        lines.append("机型 · \(modelValue(facts.modelName))")
        lines.append(capacityLine(coreCount: facts.coreCount, physicalMemoryBytes: facts.physicalMemoryBytes))
        lines.append(bootCaption(facts.bootedAt))
        if let thermal = thermalLine(thermalNotice) {
            lines.append(thermal)
        }
        return lines.joined(separator: "，")
    }
}

/// Host load already on the sampler. Missing samples stay an em dash. This type does not read the host.
enum MachineStatusCopy {
    static let samplingCaption = "正在采样…"
    static let missingCaption = "暂时读不到"
    static let missingValue = "—"
    static let memoryDestination = "打开内存页"
    static let cpuDestination = "打开 CPU 页"
    static let cpuReadyCaption = "全机"

    enum Phase: Equatable {
        case sampling
        case missing
        case ready
    }

    struct Cell: Equatable {
        /// Nil is the loading skeleton. A dash is a real missing value.
        var value: String?
        var caption: String
        var accessibilityValue: String
    }

    /// A held snapshot wins. Sampling is only the first wait. Anything else unread stays missing.
    static func phase(snapshot: MemorySnapshot?, loadState: LoadState) -> Phase {
        if snapshot != nil { return .ready }
        if loadState == .sampling { return .sampling }
        return .missing
    }

    static func pressure(snapshot: MemorySnapshot?, loadState: LoadState) -> Cell {
        switch phase(snapshot: snapshot, loadState: loadState) {
        case .sampling:
            return samplingCell
        case .missing:
            return missingCell
        case .ready:
            guard let snapshot else { return missingCell }
            return Cell(
                value: snapshot.pressure.title,
                caption: pressureCaption(snapshot),
                accessibilityValue: snapshot.pressure.title
            )
        }
    }

    static func usedMemory(snapshot: MemorySnapshot?, loadState: LoadState) -> Cell {
        switch phase(snapshot: snapshot, loadState: loadState) {
        case .sampling:
            return samplingCell
        case .missing:
            return missingCell
        case .ready:
            guard let snapshot else { return missingCell }
            let caption = snapshot.totalBytes > 0
                ? "共 \(ByteFormat.memory(snapshot.totalBytes))"
                : missingValue
            return Cell(
                value: ByteFormat.memory(snapshot.usedBytes),
                caption: caption,
                accessibilityValue: ByteFormat.memory(snapshot.usedBytes)
            )
        }
    }

    static func swap(snapshot: MemorySnapshot?, loadState: LoadState) -> Cell {
        switch phase(snapshot: snapshot, loadState: loadState) {
        case .sampling:
            return samplingCell
        case .missing:
            return missingCell
        case .ready:
            guard let snapshot else { return missingCell }
            let display = SwapUsage.display(usedBytes: snapshot.swapUsedBytes)
            return Cell(value: display.value, caption: display.caption, accessibilityValue: display.value)
        }
    }

    static func cpu(snapshot: MemorySnapshot?, loadState: LoadState, percent: Double?) -> Cell {
        switch phase(snapshot: snapshot, loadState: loadState) {
        case .sampling:
            return samplingCell
        case .missing:
            return missingCell
        case .ready:
            guard snapshot != nil else { return missingCell }
            let text = CPUPercentText.string(percent)
            let caption = percent == nil ? SwapUsage.missingCaption : cpuReadyCaption
            return Cell(value: text, caption: caption, accessibilityValue: text)
        }
    }

    static func buttonLabel(title: String, value: String, destination: String) -> String {
        "\(title)，\(value)，\(destination)"
    }

    /// Same caption rule as the memory page pressure card.
    private static func pressureCaption(_ snapshot: MemorySnapshot) -> String {
        if snapshot.pressure == .normal {
            let percent = Int((snapshot.pressureMetric * 100).rounded())
            return "\(percent)% · \(snapshot.pressure.caption)"
        }
        return snapshot.pressure.caption
    }

    private static let samplingCell = Cell(
        value: nil,
        caption: samplingCaption,
        accessibilityValue: samplingCaption
    )

    private static let missingCell = Cell(
        value: missingValue,
        caption: missingCaption,
        accessibilityValue: missingValue
    )
}
