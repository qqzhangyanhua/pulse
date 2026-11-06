import Foundation

struct CPUTick: Sendable, Equatable {
    let userTimeNs: UInt64
    let systemTimeNs: UInt64
    let date: Date
}

/// Two-frame wall-clock CPU for one process. The first frame is `nil`.
enum ProcessCPUPercent {
    static func percent(previous: CPUTick?, current: CPUTick) -> Double? {
        guard let previous,
              current.userTimeNs >= previous.userTimeNs,
              current.systemTimeNs >= previous.systemTimeNs
        else {
            return nil
        }
        let deltaCPU = Double(
            (current.userTimeNs - previous.userTimeNs) + (current.systemTimeNs - previous.systemTimeNs)
        )
        let wallNs = current.date.timeIntervalSince(previous.date) * 1_000_000_000
        guard wallNs > 0 else { return nil }
        return (deltaCPU / wallNs) * 100
    }
}

/// Cumulative `host_cpu_load_info` counters. Order at the reader is user, system, idle, nice.
struct HostCPUTicks: Sendable, Equatable {
    let user: UInt64
    let system: UInt64
    let idle: UInt64
    let nice: UInt64
}

struct SystemCPUSample: Sendable, Equatable {
    let percent: Double?
    let baseline: HostCPUTicks?
}

/// Two-frame host tick delta: (user + system + nice) / total. Not Activity Monitor point parity.
enum SystemCPULoad {
    static func percent(previous: HostCPUTicks?, current: HostCPUTicks) -> Double? {
        guard let previous,
              current.user >= previous.user,
              current.system >= previous.system,
              current.idle >= previous.idle,
              current.nice >= previous.nice
        else {
            return nil
        }
        let busy = (current.user - previous.user)
            + (current.system - previous.system)
            + (current.nice - previous.nice)
        let total = busy + (current.idle - previous.idle)
        guard total > 0 else { return nil }
        return (Double(busy) / Double(total)) * 100
    }

    /// Failed reads stay `nil` and keep the last baseline. A successful read always becomes the next baseline.
    static func advance(previous: HostCPUTicks?, reading: HostCPUTicks?) -> SystemCPUSample {
        guard let reading else {
            return SystemCPUSample(percent: nil, baseline: previous)
        }
        return SystemCPUSample(
            percent: percent(previous: previous, current: reading),
            baseline: reading
        )
    }
}

struct BusiestCoreSample: Sendable, Equatable {
    let percent: Double?
    let baseline: [HostCPUTicks]?
}

/// Same ratio as `SystemCPULoad.percent`, over reader-ordered cores.
/// A missed core is skipped, not stored as 0. Ties keep the earlier core.
/// The chosen index is not part of the sample.
enum BusiestCoreLoad {
    static func advance(previous: [HostCPUTicks]?, reading: [HostCPUTicks]?) -> BusiestCoreSample {
        guard let reading else {
            return BusiestCoreSample(percent: nil, baseline: previous)
        }
        guard let previous, previous.count == reading.count, !reading.isEmpty else {
            return BusiestCoreSample(percent: nil, baseline: reading)
        }
        var best: Double?
        for index in reading.indices {
            guard let percent = SystemCPULoad.percent(previous: previous[index], current: reading[index]) else {
                continue
            }
            if let best, percent <= best {
                continue
            }
            best = percent
        }
        return BusiestCoreSample(percent: best, baseline: reading)
    }
}
