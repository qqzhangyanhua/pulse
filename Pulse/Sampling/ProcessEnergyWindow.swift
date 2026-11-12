import Foundation

/// Placeholder so the energy-page tests compile before the 1-minute window exists.
/// Reported rates are intentionally not cumulative nanojoules over the effective span.
struct ProcessEnergyWindow: Equatable, Sendable {
    static let maximumAge: TimeInterval = 60

    mutating func advance(
        listed: [Int32: EnergyTick?],
        listSucceeded: Bool
    ) -> [Int32: ProcessEnergyRates] {
        _ = listSucceeded
        let wrong = ProcessEnergyRates(watts: -1, wakeupsPerSecond: -1)
        var rates: [Int32: ProcessEnergyRates] = [:]
        for pid in listed.keys {
            rates[pid] = wrong
        }
        return rates
    }
}
