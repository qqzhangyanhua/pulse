import Foundation

struct SamplingStep: Equatable, Sendable {
    /// One sample on the shared `MemorySampler`. Background does not open a second poll.
    let samples: Bool
    let sleepNanoseconds: UInt64
}

enum SamplingPace {
    static let foregroundSleepNanoseconds: UInt64 = 1_500_000_000
    static let backgroundSleepNanoseconds: UInt64 = 3_000_000_000

    static func step(isForeground: Bool) -> SamplingStep {
        SamplingStep(
            samples: true,
            sleepNanoseconds: isForeground ? foregroundSleepNanoseconds : backgroundSleepNanoseconds
        )
    }
}

struct SamplingTickPlan: Equatable, Sendable {
    let sample: Bool
    let sleepNanoseconds: UInt64
}

/// Wakes often enough to notice `setForeground`, and samples only when the pace interval is due.
struct SamplingClock: Equatable, Sendable {
    static let wakeSliceNanoseconds: UInt64 = 400_000_000

    private(set) var elapsed: UInt64 = 0
    private var needsInitialSample = true

    mutating func plan(step: SamplingStep) -> SamplingTickPlan {
        let due = needsInitialSample || elapsed >= step.sleepNanoseconds
        if due {
            elapsed = 0
            needsInitialSample = false
        }
        let remain = step.sleepNanoseconds > elapsed ? step.sleepNanoseconds - elapsed : step.sleepNanoseconds
        let sleep = min(Self.wakeSliceNanoseconds, remain)
        return SamplingTickPlan(sample: due && step.samples, sleepNanoseconds: sleep)
    }

    mutating func recordSleep(_ nanoseconds: UInt64) {
        elapsed += nanoseconds
    }
}

/// Foreground / background hook used by `MemoryDashboardVM.setForeground`.
struct SamplingSession: Equatable, Sendable {
    private(set) var isForeground: Bool

    init(isForeground: Bool = true) {
        self.isForeground = isForeground
    }

    mutating func setForeground(_ active: Bool) {
        isForeground = active
    }

    var step: SamplingStep {
        SamplingPace.step(isForeground: isForeground)
    }
}
