import XCTest
@testable import SamplingCore

final class SamplingPaceTests: XCTestCase {
    func testForegroundStaysAtOneAndAHalfSeconds() {
        let step = SamplingPace.step(isForeground: true)
        XCTAssertTrue(step.samples)
        XCTAssertEqual(step.sleepNanoseconds, 1_500_000_000)
    }

    func testBackgroundKeepsSamplingAtASlowerPace() {
        let foreground = SamplingPace.step(isForeground: true)
        let background = SamplingPace.step(isForeground: false)
        XCTAssertTrue(background.samples)
        XCTAssertEqual(background.sleepNanoseconds, 3_000_000_000)
        XCTAssertGreaterThan(background.sleepNanoseconds, foreground.sleepNanoseconds)
        XCTAssertLessThanOrEqual(background.sleepNanoseconds, 5_000_000_000)
    }

    func testSetForegroundKeepsSamplingAndChangesInterval() {
        var session = SamplingSession()
        var plans: [SamplingStep] = []

        func oneTick() {
            let step = session.step
            XCTAssertTrue(step.samples)
            plans.append(step)
        }

        oneTick()
        session.setForeground(false)
        oneTick()
        oneTick()
        session.setForeground(true)
        oneTick()

        XCTAssertEqual(plans.map(\.sleepNanoseconds), [
            1_500_000_000,
            3_000_000_000,
            3_000_000_000,
            1_500_000_000,
        ])
        XCTAssertEqual(plans.count, 4)
    }

    func testClockSamplesOnThePaceIntervalAndWakesWithoutASecondPoll() {
        XCTAssertEqual(sampleGaps(isForeground: true), [1_500_000_000, 1_500_000_000])
        XCTAssertEqual(sampleGaps(isForeground: false), [3_000_000_000, 3_000_000_000])
    }

    func testReturningToForegroundSamplesOnceTheShorterIntervalIsAlreadyDue() {
        var clock = SamplingClock()
        var session = SamplingSession(isForeground: false)
        let initial = clock.plan(step: session.step)
        XCTAssertTrue(initial.sample)
        clock.recordSleep(initial.sleepNanoseconds)

        var slept = initial.sleepNanoseconds
        while slept < 1_500_000_000 {
            let plan = clock.plan(step: session.step)
            XCTAssertFalse(plan.sample)
            clock.recordSleep(plan.sleepNanoseconds)
            slept += plan.sleepNanoseconds
        }

        session.setForeground(true)
        let resumed = clock.plan(step: session.step)
        XCTAssertTrue(resumed.sample)
        XCTAssertLessThanOrEqual(resumed.sleepNanoseconds, SamplingClock.wakeSliceNanoseconds)
    }

    private func sampleGaps(isForeground: Bool) -> [UInt64] {
        var clock = SamplingClock()
        let step = SamplingPace.step(isForeground: isForeground)
        var gaps: [UInt64] = []
        var sinceSample: UInt64 = 0
        var seenSamples = 0
        for _ in 0..<40 {
            let plan = clock.plan(step: step)
            if plan.sample {
                if seenSamples > 0 {
                    gaps.append(sinceSample)
                }
                seenSamples += 1
                sinceSample = 0
                if gaps.count == 2 { break }
            } else {
                XCTAssertLessThanOrEqual(plan.sleepNanoseconds, SamplingClock.wakeSliceNanoseconds)
            }
            clock.recordSleep(plan.sleepNanoseconds)
            sinceSample += plan.sleepNanoseconds
        }
        return gaps
    }
}
