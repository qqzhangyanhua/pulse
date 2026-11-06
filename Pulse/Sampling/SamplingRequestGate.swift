import Foundation

/// One in-flight sample. Issued at `begin`, accepted at most once.
struct SamplingFlight: Equatable, Hashable, Sendable {
    let id: UInt64
}

struct SamplingGatePlan: Equatable, Sendable {
    let sample: Bool
    let sleepNanoseconds: UInt64
    let flight: SamplingFlight?
}

/// Nanos to feed `SamplingClock.recordSleep` after a wait.
/// Interrupted leftover must never be recorded; that would shrink the next 1.5s / 3s.
enum SamplingSleepInterruption {
    static func recordableNanoseconds(planned: UInt64, consumed: UInt64, completed: Bool) -> UInt64 {
        if completed { return planned }
        return min(consumed, planned)
    }
}

/// Loop wait → `recordSleep`. `nil` means skip: the loop was cancelled before this slice finished.
enum SamplingSleepWait {
    static func recordableNanoseconds(
        planned: UInt64,
        consumed: UInt64,
        completed: Bool,
        loopCancelled: Bool
    ) -> UInt64? {
        if loopCancelled, !completed { return nil }
        return SamplingSleepInterruption.recordableNanoseconds(
            planned: planned,
            consumed: consumed,
            completed: completed
        )
    }
}

/// Darwin-free request gate. Manual retry and Clock due share one in-flight sample.
///
/// Idle `requestManualRetry()` sets `retrying` + `pendingImmediate`. In-flight
/// requests join the current flight and do not queue another after `accept`.
/// `invalidate()` is the cancel / quit boundary: later `accept` fails, no second flight.
struct SamplingRequestGate: Equatable, Sendable {
    private(set) var retrying = false
    private(set) var pendingImmediate = false

    private var currentFlight: SamplingFlight?
    private var nextFlightID: UInt64 = 1
    private var invalidated = false

    mutating func requestManualRetry() {
        guard !invalidated else { return }
        retrying = true
        if currentFlight == nil {
            pendingImmediate = true
        }
    }

    mutating func plan(clock: inout SamplingClock, step: SamplingStep) -> SamplingGatePlan {
        if invalidated || currentFlight != nil {
            return SamplingGatePlan(
                sample: false,
                sleepNanoseconds: clock.nextSleepNanoseconds(step: step),
                flight: nil
            )
        }

        let clockPlan = clock.plan(step: step, immediate: pendingImmediate)
        guard clockPlan.sample else {
            return SamplingGatePlan(
                sample: false,
                sleepNanoseconds: clockPlan.sleepNanoseconds,
                flight: nil
            )
        }

        pendingImmediate = false
        let flight = SamplingFlight(id: nextFlightID)
        nextFlightID += 1
        currentFlight = flight
        return SamplingGatePlan(
            sample: true,
            sleepNanoseconds: clockPlan.sleepNanoseconds,
            flight: flight
        )
    }

    mutating func accept(_ flight: SamplingFlight) -> Bool {
        guard !invalidated, currentFlight == flight else { return false }
        currentFlight = nil
        retrying = false
        pendingImmediate = false
        return true
    }

    mutating func invalidate() {
        invalidated = true
        currentFlight = nil
        pendingImmediate = false
        retrying = false
    }
}
