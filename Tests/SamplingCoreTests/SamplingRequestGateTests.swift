import XCTest
@testable import SamplingCore

/// Phase 13 step 1: Darwin-free request gate + retry chrome predicates.
/// Single in-flight merge for a failed-sample manual retry. No VM / Sampler / Views.
final class SamplingRequestGateTests: XCTestCase {
    private let foreground = SamplingPace.step(isForeground: true)
    private let background = SamplingPace.step(isForeground: false)

    // MARK: - Matrix 1

    func testIdleManualRetryBeginsOnceAndKeepsForegroundInterval() {
        var world = World()
        world.consumeInitial()

        world.clock.recordSleep(400_000_000)
        XCTAssertLessThan(world.clock.elapsed, foreground.sleepNanoseconds)

        world.gate.requestManualRetry()
        XCTAssertTrue(world.gate.retrying)

        let retry = world.plan()
        XCTAssertTrue(retry.sample, "idle + pendingImmediate must begin on the next plan")
        XCTAssertEqual(world.beginCount, 2, "cold-start + one manual begin")
        XCTAssertEqual(world.clock.elapsed, 0)
        XCTAssertEqual(
            retry.sleepNanoseconds,
            SamplingClock.wakeSliceNanoseconds,
            "immediate is begin-now, not a shortened 400ms wake posing as retry"
        )

        let inFlight = world.plan()
        XCTAssertFalse(inFlight.sample, "second plan while unloaded in-flight must not sample")
        XCTAssertNil(inFlight.flight)
        XCTAssertEqual(world.beginCount, 2)

        XCTAssertTrue(world.acceptCurrent())
        XCTAssertFalse(world.gate.retrying)

        let after = world.plan()
        XCTAssertFalse(after.sample, "complete must not queue an extra immediate")
        XCTAssertEqual(gapUntilNextSample(&world), 1_500_000_000)
    }

    func testIdleManualRetryKeepsBackgroundThreeSecondInterval() {
        var world = World(isForeground: false)
        world.consumeInitial()
        world.gate.requestManualRetry()
        XCTAssertTrue(world.plan().sample)
        XCTAssertTrue(world.acceptCurrent())
        XCTAssertEqual(gapUntilNextSample(&world), 3_000_000_000)
    }

    // MARK: - Matrix 2

    func testInFlightManualRetryJoinsAndStaleFlightIsRefused() {
        var world = World()
        let started = world.plan()
        XCTAssertTrue(started.sample)
        let current = tryUnwrap(started.flight)

        world.gate.requestManualRetry()
        XCTAssertTrue(world.gate.retrying)
        XCTAssertEqual(world.beginCount, 1, "join must not begin a second flight")

        let joined = world.plan()
        XCTAssertFalse(joined.sample)
        XCTAssertEqual(world.beginCount, 1)

        XCTAssertFalse(world.gate.accept(SamplingFlight(id: current.id &+ 99)))
        XCTAssertTrue(world.gate.retrying, "wrong token keeps the current flight explainable")

        XCTAssertTrue(world.gate.accept(current), "only the current flight accepts once")
        XCTAssertFalse(world.gate.retrying)
        XCTAssertFalse(world.gate.accept(current), "current token is single-use")
        XCTAssertEqual(world.beginCount, 1)
    }

    // MARK: - Matrix 3

    func testClockAsleepNotDueManualRequestBeginsImmediately() {
        var world = World()
        world.consumeInitial()

        let plannedSlice = SamplingClock.wakeSliceNanoseconds
        world.clock.recordSleep(plannedSlice)
        XCTAssertLessThan(world.clock.elapsed, foreground.sleepNanoseconds)

        world.gate.requestManualRetry()
        let consumed = SamplingSleepInterruption.recordableNanoseconds(
            planned: plannedSlice,
            consumed: 50_000_000,
            completed: false
        )
        XCTAssertEqual(consumed, 50_000_000)
        world.clock.recordSleep(consumed)

        let leftoverWouldHaveBeen = plannedSlice - 50_000_000
        XCTAssertGreaterThan(leftoverWouldHaveBeen, 0)
        XCTAssertLessThan(
            world.clock.elapsed,
            foreground.sleepNanoseconds,
            "interrupted leftover must not be recorded as if the slice matured"
        )

        let retry = world.plan()
        XCTAssertTrue(retry.sample)
        XCTAssertEqual(world.clock.elapsed, 0, "begin resets elapsed; leftover was not counted as due")
        XCTAssertTrue(world.acceptCurrent())
        XCTAssertEqual(gapUntilNextSample(&world), 1_500_000_000)
    }

    func testInterruptedRemainderMustNotBeRecordedAfterBegin() {
        var world = World()
        world.consumeInitial()
        world.clock.recordSleep(400_000_000)
        world.gate.requestManualRetry()
        world.clock.recordSleep(
            SamplingSleepInterruption.recordableNanoseconds(
                planned: 400_000_000,
                consumed: 0,
                completed: false
            )
        )
        XCTAssertTrue(world.plan().sample)
        XCTAssertEqual(world.clock.elapsed, 0)

        let polluted = world.clock
        var pollutedClock = polluted
        pollutedClock.recordSleep(1_100_000_000)
        XCTAssertGreaterThan(pollutedClock.elapsed, 0)
        XCTAssertEqual(
            world.clock.elapsed,
            0,
            "② must not recordSleep the interrupted remainder after begin"
        )
    }

    // MARK: - Matrix 4

    func testRepeatedManualRequestIsIdempotent() {
        var world = World()
        world.consumeInitial()

        world.gate.requestManualRetry()
        world.gate.requestManualRetry()
        world.gate.requestManualRetry()
        let first = world.plan()
        XCTAssertTrue(first.sample)
        XCTAssertEqual(world.beginCount, 2)

        world.gate.requestManualRetry()
        world.gate.requestManualRetry()
        XCTAssertFalse(world.plan().sample)
        XCTAssertEqual(world.beginCount, 2)

        XCTAssertTrue(world.acceptCurrent())
        XCTAssertFalse(world.gate.retrying)
        XCTAssertFalse(world.plan().sample, "idempotent clicks must not queue a post-complete extra")
    }

    // MARK: - Matrix 5 / 6

    func testAcceptSuccessAndFailureClearRetrying() {
        var world = World()
        world.consumeInitial()
        world.gate.requestManualRetry()
        XCTAssertTrue(world.plan().sample)

        XCTAssertEqual(
            SamplingRetryApply.loadState(accepted: true, sampleSucceeded: true, hasSnapshot: false),
            .ready
        )
        XCTAssertTrue(world.acceptCurrent())
        XCTAssertFalse(world.gate.retrying)

        world.gate.requestManualRetry()
        XCTAssertTrue(world.plan().sample)
        XCTAssertEqual(
            SamplingRetryApply.loadState(accepted: true, sampleSucceeded: false, hasSnapshot: false),
            .failed
        )
        XCTAssertTrue(world.acceptCurrent())
        XCTAssertFalse(world.gate.retrying)

        XCTAssertEqual(
            SamplingRetryApply.loadState(accepted: true, sampleSucceeded: false, hasSnapshot: true),
            .ready,
            "today's tick keeps ready when a snapshot already exists"
        )
        XCTAssertNil(
            SamplingRetryApply.loadState(accepted: false, sampleSucceeded: true, hasSnapshot: false),
            "stale / cancelled results must not write"
        )
    }

    // MARK: - Matrix 7

    func testSetForegroundDoesNotBeginOrInventATimerRetry() {
        var session = SamplingSession()
        var clock = SamplingClock()
        var gate = SamplingRequestGate()

        let initial = gate.plan(clock: &clock, step: session.step)
        XCTAssertTrue(initial.sample)
        XCTAssertFalse(gate.retrying)
        XCTAssertTrue(gate.accept(tryUnwrap(initial.flight)))

        clock.recordSleep(400_000_000)
        session.setForeground(false)
        XCTAssertEqual(session.step.sleepNanoseconds, SamplingPace.backgroundSleepNanoseconds)

        let backgroundPlan = gate.plan(clock: &clock, step: session.step)
        XCTAssertFalse(backgroundPlan.sample)
        XCTAssertFalse(gate.retrying)

        session.setForeground(true)
        XCTAssertEqual(session.step.sleepNanoseconds, SamplingPace.foregroundSleepNanoseconds)
        let foregroundPlan = gate.plan(clock: &clock, step: session.step)
        XCTAssertFalse(foregroundPlan.sample, "setForeground is not a retry request")
        XCTAssertFalse(gate.retrying)
        XCTAssertEqual(foregroundPlan.sleepNanoseconds, SamplingClock.wakeSliceNanoseconds)
    }

    func testReturningToForegroundStillSamplesWhenShorterIntervalIsAlreadyDue() {
        var session = SamplingSession(isForeground: false)
        var clock = SamplingClock()
        var gate = SamplingRequestGate()

        let initial = gate.plan(clock: &clock, step: session.step)
        XCTAssertTrue(initial.sample)
        XCTAssertFalse(gate.retrying)
        XCTAssertTrue(gate.accept(tryUnwrap(initial.flight)))
        clock.recordSleep(initial.sleepNanoseconds)

        var slept = initial.sleepNanoseconds
        while slept < 1_500_000_000 {
            let plan = gate.plan(clock: &clock, step: session.step)
            XCTAssertFalse(plan.sample)
            XCTAssertFalse(gate.retrying)
            clock.recordSleep(plan.sleepNanoseconds)
            slept += plan.sleepNanoseconds
        }

        session.setForeground(true)
        let resumed = gate.plan(clock: &clock, step: session.step)
        XCTAssertTrue(resumed.sample, "existing Clock due-on-shorter-interval is unchanged")
        XCTAssertFalse(gate.retrying, "Clock due is not a manual retry")
        XCTAssertLessThanOrEqual(resumed.sleepNanoseconds, SamplingClock.wakeSliceNanoseconds)
    }

    // MARK: - Matrix 8

    func testColdStartIsNotRetrying() {
        var world = World()
        let initial = world.plan()
        XCTAssertTrue(initial.sample)
        XCTAssertFalse(world.gate.retrying)
        XCTAssertFalse(SamplingRetryChrome.showsPendingLine(retrying: world.gate.retrying))
        XCTAssertEqual(SamplingRetryChrome.loadStateDuringRetry(.sampling), .sampling)
    }

    func testInvalidateRejectsAcceptAndStartsNoSecondFlight() {
        var world = World()
        let initial = world.plan()
        let flight = tryUnwrap(initial.flight)
        world.gate.requestManualRetry()
        XCTAssertTrue(world.gate.retrying)

        world.gate.invalidate()
        XCTAssertFalse(world.gate.retrying)
        XCTAssertFalse(world.gate.accept(flight))
        XCTAssertEqual(world.beginCount, 1)

        world.gate.requestManualRetry()
        XCTAssertFalse(world.gate.retrying, "quit/cancel must not leave retrying stuck")
        XCTAssertFalse(world.plan().sample)
        XCTAssertEqual(world.beginCount, 1, "0 second flight after invalidate")
    }

    // MARK: - Matrix 9

    func testManualAndClockDueOnSamePlanBeginOnce() {
        var world = World()
        world.consumeInitial()

        var slept: UInt64 = 0
        while slept < 1_500_000_000 {
            let plan = world.plan()
            XCTAssertFalse(plan.sample)
            world.clock.recordSleep(plan.sleepNanoseconds)
            slept += plan.sleepNanoseconds
        }

        world.gate.requestManualRetry()
        let fused = world.plan()
        XCTAssertTrue(fused.sample)
        XCTAssertEqual(world.beginCount, 2)
        XCTAssertTrue(world.gate.retrying)
        XCTAssertFalse(world.plan().sample)
        XCTAssertTrue(world.acceptCurrent())
        XCTAssertEqual(gapUntilNextSample(&world), 1_500_000_000)
    }

    // MARK: - Clock regression without a manual request

    func testGateWithoutManualRequestMatchesBareClockElapsedRemainAndWake() {
        assertBareClockParity(isForeground: true)
        assertBareClockParity(isForeground: false)
    }

    func testWakeSliceAndPaceConstantsAreUnchanged() {
        XCTAssertEqual(SamplingClock.wakeSliceNanoseconds, 400_000_000)
        XCTAssertEqual(SamplingPace.foregroundSleepNanoseconds, 1_500_000_000)
        XCTAssertEqual(SamplingPace.backgroundSleepNanoseconds, 3_000_000_000)
    }

    // MARK: - Helpers

    private struct World {
        var gate = SamplingRequestGate()
        var clock = SamplingClock()
        var session: SamplingSession
        private(set) var beginCount = 0
        private(set) var currentFlight: SamplingFlight?

        init(isForeground: Bool = true) {
            session = SamplingSession(isForeground: isForeground)
        }

        var step: SamplingStep { session.step }

        mutating func plan() -> SamplingGatePlan {
            let plan = gate.plan(clock: &clock, step: step)
            if plan.sample {
                beginCount += 1
                currentFlight = plan.flight
            }
            return plan
        }

        mutating func consumeInitial() {
            let initial = plan()
            XCTAssertTrue(initial.sample)
            XCTAssertFalse(gate.retrying)
            XCTAssertTrue(acceptCurrent())
        }

        mutating func acceptCurrent() -> Bool {
            guard let currentFlight else { return false }
            return gate.accept(currentFlight)
        }
    }

    private func gapUntilNextSample(_ world: inout World) -> UInt64 {
        var slept: UInt64 = 0
        for _ in 0..<40 {
            let plan = world.plan()
            if plan.sample {
                XCTAssertTrue(world.acceptCurrent())
                return slept
            }
            XCTAssertLessThanOrEqual(plan.sleepNanoseconds, SamplingClock.wakeSliceNanoseconds)
            world.clock.recordSleep(plan.sleepNanoseconds)
            slept += plan.sleepNanoseconds
        }
        XCTFail("clock never came due")
        return slept
    }

    private func assertBareClockParity(isForeground: Bool) {
        var bare = SamplingClock()
        var gatedClock = SamplingClock()
        var gate = SamplingRequestGate()
        var session = SamplingSession(isForeground: isForeground)

        for tick in 0..<48 {
            let stepNow = session.step
            let barePlan = bare.plan(step: stepNow)
            let gatePlan = gate.plan(clock: &gatedClock, step: stepNow)
            XCTAssertEqual(barePlan.sample, gatePlan.sample, "sample tick \(tick)")
            XCTAssertEqual(barePlan.sleepNanoseconds, gatePlan.sleepNanoseconds, "sleep tick \(tick)")
            XCTAssertEqual(bare.elapsed, gatedClock.elapsed, "elapsed tick \(tick)")
            XCTAssertEqual(
                barePlan.sleepNanoseconds,
                min(SamplingClock.wakeSliceNanoseconds, remaining(step: stepNow, elapsed: bare.elapsed)),
                "wake slice tick \(tick)"
            )
            XCTAssertFalse(gate.retrying)
            if gatePlan.sample {
                XCTAssertNotNil(gatePlan.flight)
                XCTAssertTrue(gate.accept(tryUnwrap(gatePlan.flight)))
            } else {
                XCTAssertNil(gatePlan.flight)
            }

            if tick == 12 {
                session.setForeground(!isForeground)
            }
            bare.recordSleep(barePlan.sleepNanoseconds)
            gatedClock.recordSleep(gatePlan.sleepNanoseconds)
        }
    }

    private func remaining(step: SamplingStep, elapsed: UInt64) -> UInt64 {
        step.sleepNanoseconds > elapsed ? step.sleepNanoseconds - elapsed : step.sleepNanoseconds
    }

    private func tryUnwrap<T>(_ value: T?, file: StaticString = #filePath, line: UInt = #line) -> T {
        guard let value else {
            XCTFail("expected non-nil", file: file, line: line)
            fatalError("expected non-nil")
        }
        return value
    }
}

final class SamplingRetryChromeTests: XCTestCase {
    func testLockedRetryCopyAndPendingLine() {
        XCTAssertEqual(SamplingRetryChrome.buttonTitle, "重试")
        XCTAssertEqual(SamplingRetryChrome.pendingLine, "正在重试…")
        XCTAssertEqual(SamplingRetryChrome.buttonReference, "点重试再试")
        XCTAssertEqual(SamplingRetryChrome.overviewFailureMessage, "这轮采样没有回来，点重试再试。")
        XCTAssertEqual(SamplingRetryChrome.processListFailedMessage, "这轮没读到进程列表，点重试再试。")
        XCTAssertTrue(SamplingRetryChrome.isButtonEnabled(retrying: false))
        XCTAssertFalse(SamplingRetryChrome.isButtonEnabled(retrying: true))
        XCTAssertFalse(SamplingRetryChrome.showsPendingLine(retrying: false))
        XCTAssertTrue(SamplingRetryChrome.showsPendingLine(retrying: true))
    }

    func testButtonReferenceRewriteLeavesTitlesAndNonPointingCopy() {
        XCTAssertEqual(
            SamplingRetryChrome.messageByUpdatingButtonReference(CPUPageCopy.failureMessage),
            SamplingRetryChrome.overviewFailureMessage
        )
        XCTAssertEqual(
            SamplingRetryChrome.messageByUpdatingButtonReference(NetworkPageCopy.failureMessage),
            SamplingRetryChrome.overviewFailureMessage
        )
        XCTAssertEqual(
            SamplingRetryChrome.messageByUpdatingButtonReference(DiskPageCopy.failureMessage),
            SamplingRetryChrome.overviewFailureMessage
        )
        XCTAssertEqual(
            SamplingRetryChrome.messageByUpdatingButtonReference("这轮没读到进程列表，点重新采样再试。"),
            SamplingRetryChrome.processListFailedMessage
        )
        XCTAssertEqual(
            SamplingRetryChrome.messageByUpdatingButtonReference(DiskPageCopy.failureTitle),
            DiskPageCopy.failureTitle,
            "磁盘主句「稍后重试」不是按钮指称"
        )
        XCTAssertEqual(
            SamplingRetryChrome.messageByUpdatingButtonReference("总览还没回来，列表先空着。"),
            "总览还没回来，列表先空着。"
        )
        XCTAssertEqual(CPUPageCopy.failureTitle, "暂时读不到 CPU 数据")
        XCTAssertEqual(DiskPageCopy.failureTitle, "暂时读不到磁盘数据，稍后重试")
    }

    func testFailureLoadStateDoesNotBecomeSamplingSkeleton() {
        XCTAssertEqual(SamplingRetryChrome.loadStateDuringRetry(.failed), .failed)
        XCTAssertNotEqual(SamplingRetryChrome.loadStateDuringRetry(.failed), .sampling)

        let phase = MemoryTablePhaseResolver.resolve(
            page: .memory,
            loadState: SamplingRetryChrome.loadStateDuringRetry(.failed),
            processCount: 0,
            visibleCount: 0,
            hasActiveNameFilter: false,
            risingOnly: false,
            processListFailed: false
        )
        XCTAssertEqual(phase, .failed)
    }

    func testProcessListFailedKeepsReadyLoadState() {
        XCTAssertEqual(SamplingRetryChrome.loadStateDuringRetry(.ready), .ready)
        let phase = MemoryTablePhaseResolver.resolve(
            page: .memory,
            loadState: SamplingRetryChrome.loadStateDuringRetry(.ready),
            processCount: 0,
            visibleCount: 0,
            hasActiveNameFilter: false,
            risingOnly: false,
            processListFailed: true
        )
        XCTAssertEqual(phase, .processListFailed)
    }

    func testPageCopyUsesLockedRetryWords() {
        XCTAssertEqual(CPUPageCopy.retry, SamplingRetryChrome.buttonTitle)
        XCTAssertEqual(CPUPageCopy.failureMessage, SamplingRetryChrome.overviewFailureMessage)
        XCTAssertEqual(NetworkPageCopy.retry, SamplingRetryChrome.buttonTitle)
        XCTAssertEqual(NetworkPageCopy.failureMessage, SamplingRetryChrome.overviewFailureMessage)
        XCTAssertEqual(DiskPageCopy.retry, SamplingRetryChrome.buttonTitle)
        XCTAssertEqual(DiskPageCopy.failureTitle, "暂时读不到磁盘数据，稍后重试")
        XCTAssertEqual(DiskPageCopy.failureMessage, SamplingRetryChrome.overviewFailureMessage)
        XCTAssertEqual(CPUPageCopy.sampling, "正在采样…")
        XCTAssertEqual(CPUPageCopy.failureTitle, "暂时读不到 CPU 数据")
        XCTAssertFalse(CPUPageCopy.retry.contains("重新采样"))
        XCTAssertFalse(CPUPageCopy.failureMessage.contains("点重新采样再试"))
    }

    func testColdStartSkeletonIsNotRetryChrome() {
        XCTAssertFalse(SamplingRetryChrome.showsPendingLine(retrying: false))
        XCTAssertEqual(SamplingRetryChrome.loadStateDuringRetry(.sampling), .sampling)
        XCTAssertNotEqual(SamplingRetryChrome.pendingLine, CPUPageCopy.sampling)
        XCTAssertEqual(SamplingRetryChrome.buttonTitle, CPUPageCopy.retry)
    }

    func testChromeHasNoSecondPageVariant() {
        XCTAssertEqual(SamplingRetryChrome.buttonTitle, "重试")
        XCTAssertEqual(SamplingRetryChrome.pendingLine, "正在重试…")
        XCTAssertEqual(SamplingRetryChrome.buttonReference, "点重试再试")
        XCTAssertFalse(SamplingRetryChrome.pendingLine.contains("泄漏"))
        XCTAssertFalse(SamplingRetryChrome.buttonTitle.lowercased().contains("leak"))
        XCTAssertFalse(SamplingRetryChrome.pendingLine.contains("危险"))
    }
}
