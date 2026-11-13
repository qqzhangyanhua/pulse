import Foundation

struct EnergyModelChannel: Equatable {
    var name: String
    var unit: String
    var cumulative: Double
}

struct EnergyModelReading: Equatable {
    var cpuWatts: Double?
    var performanceHertz: Double?
    var efficiencyHertz: Double?
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
