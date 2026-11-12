import Foundation

/// Per-pid minute buckets for the energy page's 1-hour ranking.
/// The 1-minute column stays on `ProcessEnergyWindow`. A failed list does not prune.
struct ProcessEnergyMinuteLedger: Equatable, Sendable {
    private static let maximumAge: TimeInterval = 3600
    private static let maximumBuckets = 60

    private struct Bucket: Equatable {
        var nanojoules: UInt64
        var wakeups: UInt64
        var seconds: TimeInterval
    }

    private var anchors: [Int32: EnergyTick] = [:]
    private var buckets: [Int32: [Date: Bucket]] = [:]

    mutating func advance(
        listed: [Int32: EnergyTick?],
        now: Date,
        listSucceeded: Bool
    ) -> [Int32: ProcessEnergyRates] {
        guard listSucceeded else { return [:] }
        let present = Set(listed.keys)
        anchors = anchors.filter { present.contains($0.key) }
        buckets = buckets.filter { present.contains($0.key) }
        var rates: [Int32: ProcessEnergyRates] = [:]
        rates.reserveCapacity(listed.count)
        for (pid, reading) in listed {
            rates[pid] = accept(pid, reading, now: now)
        }
        return rates
    }

    private mutating func accept(_ pid: Int32, _ reading: EnergyTick?, now: Date) -> ProcessEnergyRates {
        if let reading {
            record(pid, reading)
        }
        prune(pid, now: now)
        return rate(for: pid)
    }

    private mutating func record(_ pid: Int32, _ reading: EnergyTick) {
        guard let anchor = anchors[pid] else {
            anchors[pid] = reading
            return
        }
        let seconds = reading.date.timeIntervalSince(anchor.date)
        if reading.energyNanojoules < anchor.energyNanojoules
            || reading.interruptWakeups < anchor.interruptWakeups
            || seconds <= 0
        {
            anchors[pid] = reading
            return
        }
        let minute = Self.minuteStart(reading.date)
        var stored = buckets[pid] ?? [:]
        var bucket = stored[minute] ?? Bucket(nanojoules: 0, wakeups: 0, seconds: 0)
        bucket.nanojoules += reading.energyNanojoules - anchor.energyNanojoules
        bucket.wakeups += reading.interruptWakeups - anchor.interruptWakeups
        bucket.seconds += seconds
        stored[minute] = bucket
        buckets[pid] = stored
        anchors[pid] = reading
    }

    private mutating func prune(_ pid: Int32, now: Date) {
        guard var stored = buckets[pid] else { return }
        stored = stored.filter { now.timeIntervalSince($0.key) <= Self.maximumAge }
        if stored.count > Self.maximumBuckets {
            let overflow = stored.count - Self.maximumBuckets
            for minute in stored.keys.sorted().prefix(overflow) {
                stored.removeValue(forKey: minute)
            }
        }
        buckets[pid] = stored.isEmpty ? nil : stored
    }

    private func rate(for pid: Int32) -> ProcessEnergyRates {
        guard let stored = buckets[pid] else { return .missing }
        var nanojoules: UInt64 = 0
        var wakeups: UInt64 = 0
        var seconds = 0.0
        for bucket in stored.values where bucket.seconds > 0 {
            nanojoules += bucket.nanojoules
            wakeups += bucket.wakeups
            seconds += bucket.seconds
        }
        guard seconds > 0 else { return .missing }
        return ProcessEnergyRates(
            watts: Double(nanojoules) / seconds / 1e9,
            wakeupsPerSecond: Double(wakeups) / seconds
        )
    }

    private static func minuteStart(_ date: Date) -> Date {
        Date(timeIntervalSince1970: floor(date.timeIntervalSince1970 / 60) * 60)
    }
}
