import XCTest
@testable import SamplingCore

/// 1-minute energy window. Rates are cumulative counters over the effective span,
/// not the CPU page's already published two-frame fields.
final class EnergyWindowTests: XCTestCase {
    func testSingleTickIsMissingAndIsNotDisplayedAsZero() {
        var window = ProcessEnergyWindow()
        let rates = push(&window, energy: 0, wakeups: 0, at: 0)
        XCTAssertNotNil(rates)
        XCTAssertNil(rates?.watts)
        XCTAssertNil(rates?.wakeupsPerSecond)
        XCTAssertEqual(ProcessEnergyText.watts(rates?.watts), "—")
        XCTAssertEqual(ProcessEnergyText.wakeups(rates?.wakeupsPerSecond), "—")
        XCTAssertNotEqual(ProcessEnergyText.watts(rates?.watts), "0.0 W")
        XCTAssertNotEqual(ProcessEnergyText.wakeups(rates?.wakeupsPerSecond), "0.0 次/秒")
    }

    func testShortWindowUsesTheEffectiveDurationNotSixtySeconds() {
        var window = ProcessEnergyWindow()
        _ = push(&window, energy: 1_000, wakeups: 4, at: 0)
        let rates = push(&window, energy: 5_000_001_000, wakeups: 24, at: 10)
        XCTAssertEqual(rates?.watts ?? -1, 0.5, accuracy: 1e-9)
        XCTAssertEqual(rates?.wakeupsPerSecond ?? -1, 2, accuracy: 1e-9)
        XCTAssertNotEqual(rates?.watts ?? -1, 5_000_000_000.0 / 60.0 / 1e9)
        let oracle = ProcessEnergyLoad.rates(
            previous: tick(energy: 1_000, wakeups: 4, at: 0),
            current: tick(energy: 5_000_001_000, wakeups: 24, at: 10)
        )
        XCTAssertEqual(rates, oracle)
    }

    func testCumulativeWindowIsNotTheLastFrameAndNotTheAverageOfFrameWatts() {
        var window = ProcessEnergyWindow()
        _ = push(&window, energy: 0, wakeups: 0, at: 0)
        _ = push(&window, energy: 10_000_000_000, wakeups: 0, at: 10)
        let rates = push(&window, energy: 10_000_000_000, wakeups: 30, at: 30)
        XCTAssertEqual(rates?.watts ?? -1, 1.0 / 3.0, accuracy: 1e-9)
        XCTAssertEqual(rates?.wakeupsPerSecond ?? -1, 1, accuracy: 1e-9)
        XCTAssertNotEqual(rates?.watts ?? -1, 0.0)
        XCTAssertNotEqual(rates?.watts ?? -1, 0.5)
        XCTAssertNotEqual(rates?.wakeupsPerSecond ?? -1, 1.5)
        let anchor = ProcessEnergyLoad.rates(
            previous: tick(energy: 0, wakeups: 0, at: 0),
            current: tick(energy: 10_000_000_000, wakeups: 30, at: 30)
        )
        XCTAssertEqual(rates, anchor)
    }

    func testExactlySixtySecondsKeepsTheAnchor() {
        var window = ProcessEnergyWindow()
        _ = push(&window, energy: 0, wakeups: 0, at: 0)
        _ = push(&window, energy: 30_000_000_000, wakeups: 30, at: 30)
        let rates = push(&window, energy: 30_000_000_000, wakeups: 120, at: 60)
        XCTAssertEqual(rates?.watts ?? -1, 0.5, accuracy: 1e-9)
        XCTAssertEqual(rates?.wakeupsPerSecond ?? -1, 2, accuracy: 1e-9)
        XCTAssertNotEqual(rates?.watts ?? -1, 0.0)
        XCTAssertNotEqual(rates?.wakeupsPerSecond ?? -1, 3.0)
    }

    func testJustOverSixtySecondsDropsTheOldAnchorAndDoesNotPadTheDenominator() {
        var window = ProcessEnergyWindow()
        _ = push(&window, energy: 0, wakeups: 0, at: 0)
        let rates = push(&window, energy: 61_000_000_000, wakeups: 61, at: 61)
        XCTAssertNil(rates?.watts)
        XCTAssertNil(rates?.wakeupsPerSecond)
        XCTAssertNotEqual(rates?.watts ?? -1, 1.0)
        XCTAssertEqual(ProcessEnergyText.watts(rates?.watts), "—")
    }

    func testKeptSpanIsShorterThanSixtyWhenThePrefixFallsOutside() {
        var window = ProcessEnergyWindow()
        _ = push(&window, energy: 0, wakeups: 0, at: 0)
        _ = push(&window, energy: 100_000_000_000, wakeups: 10, at: 15)
        let rates = push(&window, energy: 150_000_000_000, wakeups: 120, at: 70)
        XCTAssertEqual(rates?.watts ?? -1, 50.0 / 55.0, accuracy: 1e-9)
        XCTAssertEqual(rates?.wakeupsPerSecond ?? -1, 110.0 / 55.0, accuracy: 1e-9)
        XCTAssertNotEqual(rates?.watts ?? -1, 50.0 / 60.0)
        XCTAssertNotEqual(rates?.watts ?? -1, 150.0 / 70.0)
    }

    func testZeroDeltaStaysZeroOnEitherSide() {
        var window = ProcessEnergyWindow()
        _ = push(&window, energy: 80_000_000_000, wakeups: 8, at: 0)
        let idle = push(&window, energy: 80_000_000_000, wakeups: 8, at: 15)
        XCTAssertEqual(idle?.watts ?? -1, 0, accuracy: 1e-9)
        XCTAssertEqual(idle?.wakeupsPerSecond ?? -1, 0, accuracy: 1e-9)
        XCTAssertNotNil(idle?.watts)
        XCTAssertNotNil(idle?.wakeupsPerSecond)
        XCTAssertEqual(ProcessEnergyText.watts(idle?.watts), "0.0 W")
        XCTAssertEqual(ProcessEnergyText.wakeups(idle?.wakeupsPerSecond), "0.0 次/秒")
        XCTAssertNotEqual(ProcessEnergyText.watts(idle?.watts), "—")

        var mixed = ProcessEnergyWindow()
        _ = push(&mixed, pid: 3, energy: 0, wakeups: 5, at: 0)
        let oneSide = push(&mixed, pid: 3, energy: 0, wakeups: 15, at: 10)
        XCTAssertEqual(oneSide?.watts ?? -1, 0, accuracy: 1e-9)
        XCTAssertEqual(oneSide?.wakeupsPerSecond ?? -1, 1, accuracy: 1e-9)
        XCTAssertNotNil(oneSide?.watts)
    }

    func testMissingReadingKeepsTheSegmentAndTheNextSuccessIncludesTheGap() {
        var window = ProcessEnergyWindow()
        _ = push(&window, energy: 0, wakeups: 0, at: 0)
        _ = push(&window, energy: 10_000_000_000, wakeups: 10, at: 10)
        let missed = pushMissing(&window, at: 20)
        XCTAssertNotNil(missed)
        XCTAssertNil(missed?.watts)
        XCTAssertNil(missed?.wakeupsPerSecond)
        let recovered = push(&window, energy: 40_000_000_000, wakeups: 40, at: 40)
        XCTAssertEqual(recovered?.watts ?? -1, 1, accuracy: 1e-9)
        XCTAssertEqual(recovered?.wakeupsPerSecond ?? -1, 1, accuracy: 1e-9)
        XCTAssertNotEqual(recovered?.watts ?? -1, 30.0 / 20.0)
    }

    func testAGapLongerThanSixtySecondsLeavesOnlyTheNewTick() {
        var window = ProcessEnergyWindow()
        _ = push(&window, energy: 0, wakeups: 0, at: 0)
        _ = push(&window, energy: 10_000_000_000, wakeups: 10, at: 10)
        _ = pushMissing(&window, at: 20)
        let late = push(&window, energy: 90_000_000_000, wakeups: 90, at: 90)
        XCTAssertNil(late?.watts)
        XCTAssertNil(late?.wakeupsPerSecond)
        XCTAssertNotEqual(late?.watts ?? -1, 1.0)
        XCTAssertEqual(ProcessEnergyText.watts(late?.watts), "—")
    }

    func testEnergyDecreaseRebuildsTheSegmentBeforeTheNextShortWindow() {
        var window = ProcessEnergyWindow()
        _ = push(&window, energy: 100_000_000_000, wakeups: 10, at: 0)
        let dropped = push(&window, energy: 50_000_000_000, wakeups: 20, at: 10)
        XCTAssertNil(dropped?.watts)
        XCTAssertNil(dropped?.wakeupsPerSecond)
        let rebuilt = push(&window, energy: 80_000_000_000, wakeups: 35, at: 25)
        XCTAssertEqual(rebuilt?.watts ?? -1, 2, accuracy: 1e-9)
        XCTAssertEqual(rebuilt?.wakeupsPerSecond ?? -1, 1, accuracy: 1e-9)
        XCTAssertNotNil(rebuilt?.watts)
    }

    func testWakeupDecreaseAloneRebuildsBothRates() {
        var window = ProcessEnergyWindow()
        _ = push(&window, energy: 0, wakeups: 100, at: 0)
        let dropped = push(&window, energy: 10_000_000_000, wakeups: 40, at: 10)
        XCTAssertNil(dropped?.watts)
        XCTAssertNil(dropped?.wakeupsPerSecond)
        let rebuilt = push(&window, energy: 20_000_000_000, wakeups: 50, at: 20)
        XCTAssertEqual(rebuilt?.watts ?? -1, 1, accuracy: 1e-9)
        XCTAssertEqual(rebuilt?.wakeupsPerSecond ?? -1, 1, accuracy: 1e-9)
        XCTAssertNotEqual(rebuilt?.watts ?? -1, 2.0)
    }

    func testNonPositiveDurationRebuildsTheSegment() {
        var window = ProcessEnergyWindow()
        _ = push(&window, energy: 0, wakeups: 0, at: 10)
        let sameInstant = push(&window, energy: 5_000_000_000, wakeups: 1, at: 10)
        XCTAssertNil(sameInstant?.watts)
        XCTAssertNil(sameInstant?.wakeupsPerSecond)
        let next = push(&window, energy: 9_000_000_000, wakeups: 5, at: 14)
        XCTAssertEqual(next?.watts ?? -1, 1, accuracy: 1e-9)
        XCTAssertEqual(next?.wakeupsPerSecond ?? -1, 1, accuracy: 1e-9)
        XCTAssertNotEqual(next?.watts ?? -1, 2.25)
    }

    func testFailedFrameDoesNotTreatEmptyRowsAsEveryProcessExiting() {
        var window = ProcessEnergyWindow()
        _ = push(&window, energy: 0, wakeups: 0, at: 0)
        _ = push(&window, energy: 10_000_000_000, wakeups: 10, at: 10)
        let failed = window.advance(listed: [:], listSucceeded: false)
        XCTAssertTrue(failed.isEmpty)
        let continued = push(&window, energy: 30_000_000_000, wakeups: 30, at: 30)
        XCTAssertEqual(continued?.watts ?? -1, 1, accuracy: 1e-9)
        XCTAssertEqual(continued?.wakeupsPerSecond ?? -1, 1, accuracy: 1e-9)
        XCTAssertNotNil(continued?.watts)
    }

    func testFailedFrameDoesNotApplyADecreasedReadingEither() {
        var window = ProcessEnergyWindow()
        _ = push(&window, energy: 0, wakeups: 0, at: 0)
        _ = push(&window, energy: 10_000_000_000, wakeups: 10, at: 10)
        let failed = window.advance(
            listed: [7: tick(energy: 1, wakeups: 1, at: 15)],
            listSucceeded: false
        )
        XCTAssertTrue(failed.isEmpty)
        let continued = push(&window, energy: 20_000_000_000, wakeups: 20, at: 20)
        XCTAssertEqual(continued?.watts ?? -1, 1, accuracy: 1e-9)
        XCTAssertEqual(continued?.wakeupsPerSecond ?? -1, 1, accuracy: 1e-9)
    }

    func testLeavingTheListDeletesTheSegmentAndThePidReturnsWithoutABaseline() {
        var window = ProcessEnergyWindow()
        _ = push(&window, energy: 0, wakeups: 0, at: 0)
        _ = push(&window, energy: 10_000_000_000, wakeups: 10, at: 10)
        let gone = window.advance(listed: [:], listSucceeded: true)
        XCTAssertTrue(gone.isEmpty)
        let returned = push(&window, energy: 10_000_000_000, wakeups: 10, at: 20)
        XCTAssertNil(returned?.watts)
        XCTAssertNil(returned?.wakeupsPerSecond)
        XCTAssertNotEqual(returned?.watts ?? -1, 0.5)
        let fresh = push(&window, energy: 20_000_000_000, wakeups: 20, at: 30)
        XCTAssertEqual(fresh?.watts ?? -1, 1, accuracy: 1e-9)
        XCTAssertNotEqual(fresh?.watts ?? -1, 20.0 / 30.0)
    }

    func testTwoPidsKeepSeparateSegments() {
        var window = ProcessEnergyWindow()
        let first = window.advance(
            listed: [
                1: tick(energy: 0, wakeups: 0, at: 0),
                2: tick(energy: 4_000_000_000, wakeups: 1, at: 0),
            ],
            listSucceeded: true
        )
        XCTAssertNil(first[1]?.watts)
        XCTAssertNil(first[2]?.watts)
        let second = window.advance(
            listed: [
                1: tick(energy: 10_000_000_000, wakeups: 10, at: 10),
                2: tick(energy: 4_000_000_000, wakeups: 1, at: 10),
            ],
            listSucceeded: true
        )
        XCTAssertEqual(second[1]?.watts ?? -1, 1, accuracy: 1e-9)
        XCTAssertEqual(second[1]?.wakeupsPerSecond ?? -1, 1, accuracy: 1e-9)
        XCTAssertEqual(second[2]?.watts ?? -1, 0, accuracy: 1e-9)
        XCTAssertEqual(second[2]?.wakeupsPerSecond ?? -1, 0, accuracy: 1e-9)
        XCTAssertNotNil(second[2]?.watts)
    }

    func testCPUTwoFrameAdvanceStillMissesThenKeepsARealZeroAndAFailedRead() {
        let start = tick(energy: 5_000_000_000, wakeups: 2, at: 0)
        let first = ProcessEnergyLoad.advance(previous: nil, reading: start)
        XCTAssertNil(first.rates.watts)
        XCTAssertNil(first.rates.wakeupsPerSecond)
        XCTAssertEqual(first.baseline, start)
        let idle = ProcessEnergyLoad.advance(
            previous: first.baseline,
            reading: tick(energy: 5_000_000_000, wakeups: 2, at: 10)
        )
        XCTAssertEqual(idle.rates.watts ?? -1, 0, accuracy: 1e-9)
        XCTAssertEqual(idle.rates.wakeupsPerSecond ?? -1, 0, accuracy: 1e-9)
        XCTAssertNotNil(idle.rates.watts)
        let missed = ProcessEnergyLoad.advance(previous: start, reading: nil)
        XCTAssertNil(missed.rates.watts)
        XCTAssertEqual(missed.baseline, start)
        let decreased = ProcessEnergyLoad.rates(
            previous: start,
            current: tick(energy: 1, wakeups: 9, at: 10)
        )
        XCTAssertNil(decreased.watts)
        XCTAssertNil(decreased.wakeupsPerSecond)
    }

    private func tick(energy: UInt64, wakeups: UInt64, at seconds: TimeInterval) -> EnergyTick {
        EnergyTick(
            energyNanojoules: energy,
            interruptWakeups: wakeups,
            date: Date(timeIntervalSince1970: 1_700_000_000).addingTimeInterval(seconds)
        )
    }

    @discardableResult
    private func push(
        _ window: inout ProcessEnergyWindow,
        pid: Int32 = 7,
        energy: UInt64,
        wakeups: UInt64,
        at seconds: TimeInterval,
        listSucceeded: Bool = true
    ) -> ProcessEnergyRates? {
        window.advance(
            listed: [pid: tick(energy: energy, wakeups: wakeups, at: seconds)],
            listSucceeded: listSucceeded
        )[pid]
    }

    private func pushMissing(
        _ window: inout ProcessEnergyWindow,
        pid: Int32 = 7,
        at seconds: TimeInterval
    ) -> ProcessEnergyRates? {
        _ = seconds
        return window.advance(listed: [pid: nil], listSucceeded: true)[pid]
    }
}
