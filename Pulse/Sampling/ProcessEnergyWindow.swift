import Foundation

/// Monotonic `EnergyTick` segment per pid. The energy page's second consumer of the
/// same tick the two-frame baseline already built. A failed list does not prune.
struct ProcessEnergyWindow: Equatable, Sendable {
    static let maximumAge: TimeInterval = 60
    private var ticksByPid: [Int32: [EnergyTick]] = [:]

    mutating func advance(
        listed: [Int32: EnergyTick?],
        listSucceeded: Bool
    ) -> [Int32: ProcessEnergyRates] {
        guard listSucceeded else { return [:] }
        let present = Set(listed.keys)
        ticksByPid = ticksByPid.filter { present.contains($0.key) }
        var rates: [Int32: ProcessEnergyRates] = [:]
        rates.reserveCapacity(listed.count)
        for (pid, reading) in listed {
            rates[pid] = push(pid, reading)
        }
        return rates
    }

    private mutating func push(_ pid: Int32, _ reading: EnergyTick?) -> ProcessEnergyRates {
        guard let reading else { return .missing }
        var ticks = ticksByPid[pid] ?? []
        if let last = ticks.last {
            let seconds = reading.date.timeIntervalSince(last.date)
            if reading.energyNanojoules < last.energyNanojoules
                || reading.interruptWakeups < last.interruptWakeups
                || seconds <= 0
            {
                ticksByPid[pid] = [reading]
                return .missing
            }
        }
        ticks.append(reading)
        let newest = reading.date
        ticks.removeAll { newest.timeIntervalSince($0.date) > ProcessEnergyWindow.maximumAge }
        ticksByPid[pid] = ticks
        guard ticks.count >= 2, let anchor = ticks.first, let current = ticks.last else {
            return .missing
        }
        return ProcessEnergyLoad.rates(previous: anchor, current: current)
    }
}
