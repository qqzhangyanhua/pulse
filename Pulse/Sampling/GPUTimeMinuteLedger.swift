import Foundation

/// One process observed on a sample. Identity is pid plus start time.
/// Nil `clients` keeps the anchor and adds nothing. An empty list means every client is gone.
struct GPUTimeLiveSample: Equatable, Sendable {
    var pid: Int32
    var startTimeSeconds: UInt64
    var name: String
    var clients: [GPUShareClientSample]?
}

/// A process that still has counted GPU time inside the hour.
struct GPUTimeLedgerEntry: Equatable, Sendable {
    var pid: Int32
    var startTimeSeconds: UInt64
    var name: String
    var nanoseconds: UInt64
    var secondsText: String
    var exited: Bool
}

enum GPUTimeCopy {
    static let title = "最近 1 小时 GPU 时间"
    static let pulse = "Pulse"
    static let exited = "已退出"
    static let limit = 5

    /// Tenths of a second, half up. Not a rate.
    static func seconds(_ nanoseconds: UInt64) -> String {
        let (tenths, overflow) = nanoseconds.addingReportingOverflow(50_000_000)
        let rounded = overflow ? UInt64.max / 100_000_000 : tenths / 100_000_000
        return "\(rounded / 10).\(rounded % 10) 秒"
    }
}

struct GPUTimeRow: Equatable, Sendable, Identifiable {
    var pid: Int32
    var startTimeSeconds: UInt64
    var name: String
    var secondsText: String
    var exited: Bool

    var id: String { "\(pid)-\(startTimeSeconds)" }
}

struct GPUTimePresentation: Equatable, Sendable {
    var rows: [GPUTimeRow]
}

enum GPUTimeRanking {
    /// Highest total first. The same total keeps the smaller pid.
    static func card(entries: [GPUTimeLedgerEntry], ownPid: Int32) -> [GPUTimeRow] {
        entries.prefix(GPUTimeCopy.limit).map { entry in
            GPUTimeRow(
                pid: entry.pid,
                startTimeSeconds: entry.startTimeSeconds,
                name: entry.pid == ownPid ? GPUTimeCopy.pulse : entry.name,
                secondsText: entry.secondsText,
                exited: entry.exited
            )
        }
    }
}

/// Per-process minute buckets for the GPU page's 1-hour ranking.
/// A process is `(pid, startTimeSeconds)`. Not stored on disk.
/// A failed list does not seal, drop, or split.
struct GPUTimeMinuteLedger: Equatable, Sendable {
    private static let maximumAge: TimeInterval = 3600
    private static let maximumBuckets = 60

    private struct Identity: Hashable, Equatable {
        var pid: Int32
        var startTimeSeconds: UInt64
    }

    private struct Generation: Equatable {
        var anchor: [GPUShareClientSample]?
        var buckets: [Date: UInt64]
        var name: String
    }

    private var live: [Identity: Generation] = [:]
    private var exited: [Identity: Generation] = [:]

    /// Counted totals still inside the hour. A missing-only process is absent, not zero.
    var entries: [GPUTimeLedgerEntry] {
        var all: [GPUTimeLedgerEntry] = []
        for (key, generation) in live {
            guard let total = Self.total(generation.buckets) else { continue }
            all.append(entry(key, generation, total: total, exited: false))
        }
        for (key, generation) in exited {
            guard let total = Self.total(generation.buckets) else { continue }
            all.append(entry(key, generation, total: total, exited: true))
        }
        return all.sorted { lhs, rhs in
            if lhs.nanoseconds != rhs.nanoseconds { return lhs.nanoseconds > rhs.nanoseconds }
            if lhs.pid != rhs.pid { return lhs.pid < rhs.pid }
            return lhs.startTimeSeconds < rhs.startTimeSeconds
        }
    }

    mutating func advance(live samples: [GPUTimeLiveSample], at now: Date, listSucceeded: Bool) {
        guard listSucceeded else { return }
        var present = Set<Identity>()
        var latest: [Identity: GPUTimeLiveSample] = [:]
        for sample in samples {
            let key = Identity(pid: sample.pid, startTimeSeconds: sample.startTimeSeconds)
            present.insert(key)
            latest[key] = sample
        }
        for (key, sample) in latest {
            accept(sample, key: key, at: now)
        }
        for key in Array(live.keys) where !present.contains(key) {
            seal(key)
        }
        age(now: now)
    }

    private func entry(
        _ key: Identity,
        _ generation: Generation,
        total: UInt64,
        exited: Bool
    ) -> GPUTimeLedgerEntry {
        GPUTimeLedgerEntry(
            pid: key.pid,
            startTimeSeconds: key.startTimeSeconds,
            name: generation.name,
            nanoseconds: total,
            secondsText: GPUTimeCopy.seconds(total),
            exited: exited
        )
    }

    private mutating func accept(_ sample: GPUTimeLiveSample, key: Identity, at now: Date) {
        var generation = opened(key, name: sample.name)
        generation.name = resolvedName(existing: generation.name, provided: sample.name, pid: key.pid)
        guard let clients = sample.clients else {
            live[key] = generation
            return
        }
        if let anchor = generation.anchor, let delta = Self.delta(previous: anchor, current: clients) {
            let minute = Self.minuteStart(now)
            let bucket = generation.buckets[minute] ?? 0
            let (next, overflow) = bucket.addingReportingOverflow(delta)
            if !overflow {
                generation.buckets[minute] = next
            }
        }
        if Self.readable(clients) {
            generation.anchor = clients
        }
        live[key] = generation
    }

    /// Same start time resumes the sealed buckets. A new start time stays separate.
    private mutating func opened(_ key: Identity, name: String) -> Generation {
        if let generation = live[key] {
            return generation
        }
        if let sealed = exited.removeValue(forKey: key) {
            let resumed = Generation(anchor: nil, buckets: sealed.buckets, name: sealed.name)
            live[key] = resumed
            return resumed
        }
        let opened = Generation(
            anchor: nil,
            buckets: [:],
            name: resolvedName(existing: nil, provided: name, pid: key.pid)
        )
        live[key] = opened
        return opened
    }

    /// Move present buckets off the live generation. An anchor with no bucket is dropped.
    private mutating func seal(_ key: Identity) {
        guard let generation = live.removeValue(forKey: key) else { return }
        guard Self.total(generation.buckets) != nil else { return }
        exited[key] = Generation(anchor: nil, buckets: generation.buckets, name: generation.name)
    }

    private func resolvedName(existing: String?, provided: String, pid: Int32) -> String {
        let trimmed = provided.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { return trimmed }
        if let existing, !existing.isEmpty { return existing }
        return String(pid)
    }

    private mutating func age(now: Date) {
        for key in Array(live.keys) {
            guard var generation = live[key] else { continue }
            generation.buckets = pruned(generation.buckets, now: now)
            live[key] = generation
        }
        for key in Array(exited.keys) {
            guard var generation = exited[key] else { continue }
            generation.buckets = pruned(generation.buckets, now: now)
            if Self.total(generation.buckets) != nil {
                exited[key] = generation
            } else {
                exited.removeValue(forKey: key)
            }
        }
    }

    private func pruned(_ stored: [Date: UInt64], now: Date) -> [Date: UInt64] {
        var kept = stored.filter { now.timeIntervalSince($0.key) <= Self.maximumAge }
        if kept.count > Self.maximumBuckets {
            let overflow = kept.count - Self.maximumBuckets
            for minute in kept.keys.sorted().prefix(overflow) {
                kept.removeValue(forKey: minute)
            }
        }
        return kept
    }

    /// Nil when nothing has been counted. A counted zero stays zero.
    private static func total(_ buckets: [Date: UInt64]) -> UInt64? {
        guard !buckets.isEmpty else { return nil }
        var sum: UInt64 = 0
        for value in buckets.values {
            let (next, overflow) = sum.addingReportingOverflow(value)
            guard !overflow else { return nil }
            sum = next
        }
        return sum
    }

    /// Nil skips the delta. A readable current still replaces the anchor.
    private static func delta(
        previous: [GPUShareClientSample],
        current: [GPUShareClientSample]
    ) -> UInt64? {
        guard readable(previous), readable(current), !previous.isEmpty else { return nil }
        let previousIDs = Set(previous.map(\.id))
        guard previousIDs.isSubset(of: Set(current.map(\.id))) else { return nil }
        let overlapped = current.filter { previousIDs.contains($0.id) }
        guard let before = sum(previous), let after = sum(overlapped), after >= before else { return nil }
        return after - before
    }

    private static func readable(_ clients: [GPUShareClientSample]) -> Bool {
        var seen = Set<UInt64>()
        for client in clients {
            guard seen.insert(client.id).inserted else { return false }
            guard client.accumulatedGPUTimeNanoseconds != nil else { return false }
        }
        return true
    }

    private static func sum(_ clients: [GPUShareClientSample]) -> UInt64? {
        var total: UInt64 = 0
        for client in clients {
            guard let time = client.accumulatedGPUTimeNanoseconds else { return nil }
            let (next, overflow) = total.addingReportingOverflow(time)
            guard !overflow else { return nil }
            total = next
        }
        return total
    }

    private static func minuteStart(_ date: Date) -> Date {
        Date(timeIntervalSince1970: floor(date.timeIntervalSince1970 / 60) * 60)
    }
}
