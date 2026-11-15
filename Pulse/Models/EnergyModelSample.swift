import Foundation

struct EnergyModelChannel: Equatable {
    var name: String
    var unit: String
    var cumulative: Double
}

struct GPUFrequencyState: Equatable {
    var subgroup: String
    var name: String
    var residency: Int64
}

enum GPUFrequency: Equatable {
    case missing
    case idle
    case hertz(Double)
}

/// One frequency-distribution bar. `fraction` is residency / total residency.
struct GPUFrequencyDistributionBar: Equatable, Identifiable {
    var id: Int
    var label: String
    var percentText: String
    var fraction: Double
}

/// Bars for the latest GPU-page interval. `.missing` is 「—」, not an empty list and not 0%.
enum GPUFrequencyDistribution: Equatable {
    case missing
    case bars([GPUFrequencyDistributionBar])
}

enum GPUFrequencyDistributionCopy {
    static let title = "频率分布"
    static let off = "关闭"
    static let missing = "—"
}

struct EnergyModelReading: Equatable {
    var cpuWatts: Double? = nil
    var performanceHertz: Double? = nil
    var efficiencyHertz: Double? = nil
    var gpuWatts: Double? = nil
    var gpuFrequency: GPUFrequency = .missing
    /// Same performance-state delta as `gpuFrequency`. Not a second sample.
    var gpuFrequencyDistribution: GPUFrequencyDistribution = .missing
    var aneWatts: Double? = nil
    var dramWatts: Double? = nil
}

enum EnergyModelDecoder {
    static let gpuTotalChannel = "GPU Energy"

    static func deltaWatts(
        previous: EnergyModelChannel?,
        current: EnergyModelChannel,
        elapsed: TimeInterval
    ) -> Double? {
        guard let previous, elapsed > 0, previous.unit == current.unit else { return nil }
        let joules: Double
        switch current.unit {
        case "mJ":
            joules = 0.001
        case "nJ":
            joules = 1e-9
        default:
            return nil
        }
        let delta = current.cumulative - previous.cumulative
        guard delta >= 0, delta.isFinite else { return nil }
        let watts = delta * joules / elapsed
        guard watts.isFinite else { return nil }
        return watts
    }

    static func cpuReading(
        channels: [(previous: EnergyModelChannel, current: EnergyModelChannel)],
        elapsed: TimeInterval,
        performanceHertz: Double?,
        efficiencyHertz: Double?
    ) -> EnergyModelReading {
        let match = channels.first { $0.current.name.contains("CPU") }
        let watts = match.flatMap {
            deltaWatts(previous: $0.previous, current: $0.current, elapsed: elapsed)
        }
        return EnergyModelReading(
            cpuWatts: watts,
            performanceHertz: performanceHertz.flatMap(frequencyHertz),
            efficiencyHertz: efficiencyHertz.flatMap(frequencyHertz)
        )
    }

    /// `GPU Energy` already contains the other GPU channels, so it is used alone
    /// when present. Without it, GPU-named channels are summed. No match is nil.
    static func gpuWatts(
        channels: [(previous: EnergyModelChannel, current: EnergyModelChannel)],
        elapsed: TimeInterval
    ) -> Double? {
        if channels.contains(where: { $0.current.name == gpuTotalChannel }) {
            return summedWatts(channels: channels, elapsed: elapsed) { $0 == gpuTotalChannel }
        }
        return summedWatts(channels: channels, elapsed: elapsed) { $0.contains("GPU") }
    }

    /// `ANE` or `Neural`, case insensitive. Finite matching channels are summed; no match is nil.
    static func aneWatts(
        channels: [(previous: EnergyModelChannel, current: EnergyModelChannel)],
        elapsed: TimeInterval
    ) -> Double? {
        summedWatts(channels: channels, elapsed: elapsed) { name in
            name.range(of: "ANE", options: .caseInsensitive) != nil
                || name.range(of: "Neural", options: .caseInsensitive) != nil
        }
    }

    /// Sum of finite DRAM channels. No matching name is nil, not zero.
    static func dramWatts(
        channels: [(previous: EnergyModelChannel, current: EnergyModelChannel)],
        elapsed: TimeInterval
    ) -> Double? {
        summedWatts(channels: channels, elapsed: elapsed) { $0.contains("DRAM") }
    }

    /// Non-OFF residency in `GPU Performance States` only, weighted by time.
    /// The whole interval OFF is idle, even when the table is missing.
    static func gpuFrequency(
        states: [GPUFrequencyState],
        table: [VoltageState9]?
    ) -> GPUFrequency {
        var numerator = 0.0
        var denominator = 0.0
        var off: Int64 = 0
        for state in states where state.subgroup == "GPU Performance States" && state.residency > 0 {
            let name = state.name.trimmingCharacters(in: .whitespacesAndNewlines)
            if name == "OFF" {
                off += state.residency
                continue
            }
            guard let table, let hertz = hertz(forGear: name, table: table) else { return .missing }
            numerator += hertz * Double(state.residency)
            denominator += Double(state.residency)
        }
        if denominator > 0, numerator.isFinite {
            return .hertz(numerator / denominator)
        }
        if off > 0 { return .idle }
        return .missing
    }

    /// One bar per positive residency in `GPU Performance States`.
    /// Share is that residency over the total, one decimal. Zero residency is omitted.
    /// OFF is 「关闭」. A gear the table maps is MHz; otherwise the raw name.
    static func gpuFrequencyDistribution(
        states: [GPUFrequencyState],
        table: [VoltageState9]?
    ) -> GPUFrequencyDistribution {
        let visible = states.filter { state in
            state.subgroup == "GPU Performance States" && state.residency > 0
        }
        guard !visible.isEmpty else { return .missing }
        let total = visible.reduce(0.0) { $0 + Double($1.residency) }
        guard total > 0, total.isFinite else { return .missing }
        let bars = visible.enumerated().map { index, state in
            let residency = Double(state.residency)
            return GPUFrequencyDistributionBar(
                id: index,
                label: distributionLabel(state.name, table: table),
                percentText: CPUPercentText.string(residency / total * 100),
                fraction: residency / total
            )
        }
        return .bars(bars)
    }

    private static func summedWatts(
        channels: [(previous: EnergyModelChannel, current: EnergyModelChannel)],
        elapsed: TimeInterval,
        matching: (String) -> Bool
    ) -> Double? {
        var sum = 0.0
        var finite = false
        var matched = false
        for pair in channels where matching(pair.current.name) {
            matched = true
            guard let watts = deltaWatts(previous: pair.previous, current: pair.current, elapsed: elapsed) else {
                continue
            }
            sum += watts
            finite = true
        }
        guard matched, finite, sum.isFinite else { return nil }
        return sum
    }

    /// `Pn` is table entry n. Entry 0 is OFF, so P0 is not a working gear.
    private static func hertz(forGear name: String, table: [VoltageState9]) -> Double? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.first == "P" else { return nil }
        let digits = trimmed.dropFirst()
        guard let index = Int(digits), index > 0, String(index) == digits, index < table.count else {
            return nil
        }
        return Double(table[index].hertz)
    }

    private static func distributionLabel(_ name: String, table: [VoltageState9]?) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed == "OFF" { return GPUFrequencyDistributionCopy.off }
        if let table, let hertz = hertz(forGear: trimmed, table: table) {
            return megahertzLabel(hertz)
        }
        return trimmed
    }

    /// Whole megahertz when the table entry is an integer MHz. Otherwise one decimal.
    private static func megahertzLabel(_ hertz: Double) -> String {
        let mhz = hertz / 1_000_000
        guard mhz.isFinite, mhz >= 0 else { return GPUFrequencyDistributionCopy.missing }
        let whole = mhz.rounded()
        if abs(hertz - whole * 1_000_000) < 1 {
            return "\(Int(whole)) MHz"
        }
        return String(format: "%.1f MHz", locale: CPUPercentText.posix, mhz)
    }

    static func frequencyHertz(_ value: Double) -> Double? {
        value.isFinite ? value : nil
    }

    /// A state name is hertz when it already is, when it says GHz or MHz, or when
    /// it is only a megahertz figure. A cluster label stays missing.
    static func hertz(fromStateName name: String) -> Double? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if let value = Double(trimmed), value.isFinite, value >= 1_000_000 {
            return value
        }
        let lowered = trimmed.lowercased()
        if lowered.hasSuffix("ghz") || lowered.hasSuffix("mhz") {
            let scale = lowered.hasSuffix("ghz") ? 1_000_000_000.0 : 1_000_000.0
            let number = trimmed.dropLast(3).trimmingCharacters(in: .whitespacesAndNewlines)
            guard let value = Double(number), value.isFinite, value >= 0 else { return nil }
            return value * scale
        }
        if let megahertz = Double(trimmed), megahertz.isFinite, megahertz >= 100, megahertz <= 6_000 {
            return megahertz * 1_000_000
        }
        return nil
    }
}

enum EnergyModelCopy {
    static func gpuPowerLine(watts: Double?) -> String {
        "GPU 功耗 · \(gpuPowerReading(watts))"
    }

    static func gpuFrequencyLine(hertz: Double?) -> String {
        "GPU 频率 · \(gpuFrequencyReading(hertz))"
    }

    /// Card value. Missing and non-finite stay 「—」. Real 0 is `0.0 W`.
    static func gpuPowerReading(_ watts: Double?) -> String {
        guard let watts, watts.isFinite else { return "—" }
        return String(format: "%.1f W", locale: CPUPercentText.posix, watts)
    }

    /// Card value. Missing, non-finite, and negative stay 「—」. Real 0 is `0.00 GHz`.
    static func gpuFrequencyReading(_ hertz: Double?) -> String {
        guard let hertz, hertz.isFinite, hertz >= 0 else { return "—" }
        let ghz = hertz / 1_000_000_000
        return String(format: "%.2f GHz", locale: CPUPercentText.posix, ghz)
    }

    /// Card value for a weighted frequency. Idle is 「空闲」, not 0 and not 「—」.
    static func gpuFrequencyReading(_ frequency: GPUFrequency) -> String {
        switch frequency {
        case .missing:
            return "—"
        case .idle:
            return "空闲"
        case .hertz(let hertz):
            return gpuFrequencyReading(hertz)
        }
    }

    /// Idle is its own reading. A hertz value, including a real 0, still formats as GHz.
    static func gpuFrequencyLine(_ frequency: GPUFrequency) -> String {
        switch frequency {
        case .missing:
            return "GPU 频率 · —"
        case .idle:
            return "GPU 频率 · 空闲"
        case .hertz(let hertz):
            return gpuFrequencyLine(hertz: hertz)
        }
    }

    static func aneLine(watts: Double?) -> String {
        wattsLine("ANE 功耗", watts)
    }

    static func dramLine(watts: Double?) -> String {
        wattsLine("DRAM 功耗", watts)
    }

    private static func wattsLine(_ title: String, _ watts: Double?) -> String {
        guard let watts, watts.isFinite else { return "\(title) · —" }
        return "\(title) · \(String(format: "%.1f", locale: CPUPercentText.posix, watts)) W"
    }
}
