import Foundation

struct EnergyModelChannel: Equatable {
    var name: String
    var unit: String
    var cumulative: Double
}

struct EnergyModelReading: Equatable {
    var cpuWatts: Double? = nil
    var performanceHertz: Double? = nil
    var efficiencyHertz: Double? = nil
    var gpuWatts: Double? = nil
    var gpuHertz: Double? = nil
    var aneWatts: Double? = nil
    var dramWatts: Double? = nil
}

enum EnergyModelDecoder {
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

    /// Sum of finite GPU channels. No matching name is nil, not zero.
    static func gpuWatts(
        channels: [(previous: EnergyModelChannel, current: EnergyModelChannel)],
        elapsed: TimeInterval
    ) -> Double? {
        summedWatts(channels: channels, elapsed: elapsed) { $0.contains("GPU") }
    }

    /// `ANE` or `Neural`, case insensitive. Same sum rule as GPU.
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

    /// The state that spent the most time. Only that name is parsed.
    /// A higher frequency with less residency is not the current frequency.
    static func dominantHertz(_ states: [(name: String, residency: Int64)]) -> Double? {
        var winner: (name: String, residency: Int64)?
        for state in states where state.residency > 0 {
            if state.residency > (winner?.residency ?? -1) {
                winner = state
            }
        }
        guard let winner else { return nil }
        return hertz(fromStateName: winner.name)
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
        wattsLine("GPU 功耗", watts)
    }

    static func gpuFrequencyLine(hertz: Double?) -> String {
        guard let hertz, hertz.isFinite, hertz >= 0 else { return "GPU 频率 · —" }
        let ghz = hertz / 1_000_000_000
        return "GPU 频率 · \(String(format: "%.2f", locale: CPUPercentText.posix, ghz)) GHz"
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
