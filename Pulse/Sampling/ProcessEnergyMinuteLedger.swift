import Foundation

/// One sealed generation still inside the 1-hour ranking.
/// Live `advance` results stay keyed by pid and do not include these rates.
struct ExitedEnergyProcess: Equatable, Sendable {
    let pid: Int32
    let generation: Int
    let name: String
    let rates: ProcessEnergyRates
}

/// Per-process minute buckets for the energy page's 1-hour ranking.
/// A process is `(pid, generation)`. The 1-minute column stays on `ProcessEnergyWindow`.
/// A failed list does not seal, drop, or split.
struct ProcessEnergyMinuteLedger: Equatable, Sendable {
    private static let maximumAge: TimeInterval = 3600
    private static let maximumBuckets = 60

    private struct Bucket: Equatable {
        var nanojoules: UInt64
        var wakeups: UInt64
        var seconds: TimeInterval
    }

    private struct Generation: Equatable {
        var anchor: EnergyTick?
        var buckets: [Date: Bucket]
        var name: String
    }

    private struct ExitedKey: Hashable, Equatable {
        var pid: Int32
        var generation: Int
    }

    private var live: [Int32: Generation] = [:]
    private var liveGeneration: [Int32: Int] = [:]
    private var exited: [ExitedKey: Generation] = [:]

    /// Exited generations that still have a rate. Missing rates are omitted.
    var exitedProcesses: [ExitedEnergyProcess] {
        exited.compactMap { key, generation -> ExitedEnergyProcess? in
            let rates = Self.rate(of: generation.buckets)
            guard rates != .missing else { return nil }
            return ExitedEnergyProcess(
                pid: key.pid,
                generation: key.generation,
                name: generation.name,
                rates: rates
            )
        }
        .sorted { lhs, rhs in
            if lhs.pid != rhs.pid { return lhs.pid < rhs.pid }
            return lhs.generation < rhs.generation
        }
    }

    /// Live rates for pids in `listed` only. Each rate is that pid's live generation.
    mutating func advance(
        listed: [Int32: EnergyTick?],
        names: [Int32: String] = [:],
        now: Date,
        listSucceeded: Bool
    ) -> [Int32: ProcessEnergyRates] {
        guard listSucceeded else { return [:] }
        let present = Set(listed.keys)
        for pid in Array(live.keys) where !present.contains(pid) {
            seal(pid)
        }
        for (pid, reading) in listed {
            accept(pid, reading, name: names[pid])
        }
        age(now: now)
        var rates: [Int32: ProcessEnergyRates] = [:]
        rates.reserveCapacity(listed.count)
        for pid in listed.keys {
            rates[pid] = live[pid].map { Self.rate(of: $0.buckets) } ?? .missing
        }
        return rates
    }

    private mutating func accept(_ pid: Int32, _ reading: EnergyTick?, name: String?) {
        ensureLive(pid, name: name)
        guard let reading else { return }
        record(pid, reading)
    }

    private mutating func ensureLive(_ pid: Int32, name: String?) {
        let resolved = resolvedName(pid: pid, provided: name)
        if var generation = live[pid] {
            generation.name = resolved
            live[pid] = generation
            return
        }
        open(pid, name: resolved, anchor: nil)
    }

    private mutating func record(_ pid: Int32, _ reading: EnergyTick) {
        guard var generation = live[pid] else { return }
        guard let anchor = generation.anchor else {
            generation.anchor = reading
            live[pid] = generation
            return
        }
        let seconds = reading.date.timeIntervalSince(anchor.date)
        if reading.energyNanojoules < anchor.energyNanojoules
            || reading.interruptWakeups < anchor.interruptWakeups
            || seconds <= 0
        {
            let name = generation.name
            seal(pid)
            open(pid, name: name, anchor: reading)
            return
        }
        let minute = Self.minuteStart(reading.date)
        var bucket = generation.buckets[minute] ?? Bucket(nanojoules: 0, wakeups: 0, seconds: 0)
        bucket.nanojoules += reading.energyNanojoules - anchor.energyNanojoules
        bucket.wakeups += reading.interruptWakeups - anchor.interruptWakeups
        bucket.seconds += seconds
        generation.buckets[minute] = bucket
        generation.anchor = reading
        live[pid] = generation
    }

    /// Move present buckets off the live generation. An anchor with no bucket is dropped.
    private mutating func seal(_ pid: Int32) {
        guard let generation = live.removeValue(forKey: pid) else { return }
        let generationID = liveGeneration[pid] ?? 0
        guard Self.hasPresentBucket(generation.buckets) else { return }
        exited[ExitedKey(pid: pid, generation: generationID)] = Generation(
            anchor: nil,
            buckets: generation.buckets,
            name: generation.name
        )
    }

    private mutating func open(_ pid: Int32, name: String, anchor: EnergyTick?) {
        let generation = (liveGeneration[pid] ?? 0) + 1
        liveGeneration[pid] = generation
        live[pid] = Generation(anchor: anchor, buckets: [:], name: name)
    }

    private func resolvedName(pid: Int32, provided: String?) -> String {
        if let provided {
            let trimmed = provided.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { return trimmed }
        }
        if let current = live[pid]?.name, !current.isEmpty { return current }
        return String(pid)
    }

    private mutating func age(now: Date) {
        for pid in Array(live.keys) {
            guard var generation = live[pid] else { continue }
            generation.buckets = pruned(generation.buckets, now: now)
            live[pid] = generation
        }
        for key in Array(exited.keys) {
            guard var generation = exited[key] else { continue }
            generation.buckets = pruned(generation.buckets, now: now)
            if Self.hasPresentBucket(generation.buckets) {
                exited[key] = generation
            } else {
                exited.removeValue(forKey: key)
            }
        }
    }

    private func pruned(_ stored: [Date: Bucket], now: Date) -> [Date: Bucket] {
        var kept = stored.filter { now.timeIntervalSince($0.key) <= Self.maximumAge }
        if kept.count > Self.maximumBuckets {
            let overflow = kept.count - Self.maximumBuckets
            for minute in kept.keys.sorted().prefix(overflow) {
                kept.removeValue(forKey: minute)
            }
        }
        return kept
    }

    private static func hasPresentBucket(_ buckets: [Date: Bucket]) -> Bool {
        buckets.values.contains { $0.seconds > 0 }
    }

    private static func rate(of buckets: [Date: Bucket]) -> ProcessEnergyRates {
        var nanojoules: UInt64 = 0
        var wakeups: UInt64 = 0
        var seconds = 0.0
        for bucket in buckets.values where bucket.seconds > 0 {
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
