import XCTest
@testable import SamplingCore

/// Hour ranking sums present minute buckets. It does not pad gaps, and it does not
/// replace `ProcessEnergyWindow`.
final class EnergyMinuteLedgerTests: XCTestCase {
    private let origin = Date(timeIntervalSince1970: 1_700_000_040)

    func testSingleTickIsMissingAndIsNotDisplayedAsZero() {
        var ledger = ProcessEnergyMinuteLedger()
        let rates = push(&ledger, energy: 0, wakeups: 0, at: 0)
        XCTAssertNotNil(rates)
        XCTAssertNil(rates?.watts)
        XCTAssertNil(rates?.wakeupsPerSecond)
        XCTAssertEqual(ProcessEnergyText.watts(rates?.watts), "—")
        XCTAssertNotEqual(ProcessEnergyText.watts(rates?.watts), "0.0 W")
    }

    func testShortSpanUsesActualSecondsAndNotAnHourOrPerMinuteAverage() {
        var ledger = ProcessEnergyMinuteLedger()
        _ = push(&ledger, energy: 0, wakeups: 0, at: 0)
        let rates = push(&ledger, energy: 10_000_000_000, wakeups: 20, at: 10)
        XCTAssertEqual(rates?.watts ?? -1, 1, accuracy: 1e-9)
        XCTAssertEqual(rates?.wakeupsPerSecond ?? -1, 2, accuracy: 1e-9)
        XCTAssertNotEqual(rates?.watts ?? -1, 10.0 / 3600.0)
        XCTAssertNotEqual(rates?.watts ?? -1, 0.5)
    }

    func testZeroDeltaStaysZeroAndOneSideCanStayZero() {
        var ledger = ProcessEnergyMinuteLedger()
        _ = push(&ledger, energy: 80_000_000_000, wakeups: 8, at: 0)
        let idle = push(&ledger, energy: 80_000_000_000, wakeups: 8, at: 15)
        XCTAssertEqual(idle?.watts ?? -1, 0, accuracy: 1e-9)
        XCTAssertEqual(idle?.wakeupsPerSecond ?? -1, 0, accuracy: 1e-9)
        XCTAssertNotNil(idle?.watts)
        XCTAssertEqual(ProcessEnergyText.watts(idle?.watts), "0.0 W")
        XCTAssertNotEqual(ProcessEnergyText.watts(idle?.watts), "—")

        var mixed = ProcessEnergyMinuteLedger()
        _ = push(&mixed, pid: 3, energy: 0, wakeups: 5, at: 0)
        let oneSide = push(&mixed, pid: 3, energy: 0, wakeups: 15, at: 10)
        XCTAssertEqual(oneSide?.watts ?? -1, 0, accuracy: 1e-9)
        XCTAssertEqual(oneSide?.wakeupsPerSecond ?? -1, 1, accuracy: 1e-9)
        XCTAssertNotNil(oneSide?.watts)
    }

    func testSameMinuteIntervalsAccumulateInsteadOfKeepingTheLastOne() {
        var ledger = ProcessEnergyMinuteLedger()
        _ = push(&ledger, energy: 0, wakeups: 0, at: 0)
        _ = push(&ledger, energy: 10_000_000_000, wakeups: 10, at: 10)
        let rates = push(&ledger, energy: 10_000_000_000, wakeups: 10, at: 20)
        XCTAssertEqual(rates?.watts ?? -1, 0.5, accuracy: 1e-9)
        XCTAssertEqual(rates?.wakeupsPerSecond ?? -1, 0.5, accuracy: 1e-9)
        XCTAssertNotEqual(rates?.watts ?? -1, 0)
        XCTAssertNotEqual(rates?.watts ?? -1, 1)
    }

    func testPresentMinutesAreNotAveragedAndAGapIsNotPaddedToAnHour() {
        var ledger = ProcessEnergyMinuteLedger()
        _ = push(&ledger, energy: 0, wakeups: 0, at: 0)
        _ = push(&ledger, energy: 10_000_000_000, wakeups: 10, at: 10)
        let rates = push(&ledger, energy: 10_000_000_000, wakeups: 10, at: 60)
        XCTAssertEqual(rates?.watts ?? -1, 10.0 / 60.0, accuracy: 1e-9)
        XCTAssertEqual(rates?.wakeupsPerSecond ?? -1, 10.0 / 60.0, accuracy: 1e-9)
        XCTAssertNotEqual(rates?.watts ?? -1, 0.5)
        XCTAssertNotEqual(rates?.watts ?? -1, 10.0 / 3600.0)
    }

    func testNilReadingKeepsTheAnchorAndTheNextIntervalIncludesTheGap() {
        var ledger = ProcessEnergyMinuteLedger()
        _ = push(&ledger, energy: 0, wakeups: 0, at: 0)
        let first = push(&ledger, energy: 10_000_000_000, wakeups: 10, at: 10)
        XCTAssertEqual(first?.watts ?? -1, 1, accuracy: 1e-9)
        let missed = pushMissing(&ledger, at: 20)
        XCTAssertEqual(missed?.watts ?? -1, 1, accuracy: 1e-9)
        XCTAssertNotNil(missed?.watts)
        let continued = push(&ledger, energy: 10_000_000_000, wakeups: 10, at: 40)
        XCTAssertEqual(continued?.watts ?? -1, 0.25, accuracy: 1e-9)
        XCTAssertEqual(continued?.wakeupsPerSecond ?? -1, 0.25, accuracy: 1e-9)
        XCTAssertNotEqual(continued?.watts ?? -1, 1)
        XCTAssertNotNil(continued?.watts)
    }

    func testCrossingIntervalIsChargedToTheEndMinute() {
        var ledger = ProcessEnergyMinuteLedger()
        _ = push(&ledger, energy: 0, wakeups: 0, at: 50, now: 50)
        let kept = push(&ledger, energy: 30_000_000_000, wakeups: 30, at: 80, now: 3_650)
        XCTAssertEqual(kept?.watts ?? -1, 1, accuracy: 1e-9)
        XCTAssertEqual(kept?.wakeupsPerSecond ?? -1, 1, accuracy: 1e-9)
        XCTAssertNotNil(kept?.watts)
        let expired = pushMissing(&ledger, at: 3_661)
        XCTAssertNil(expired?.watts)
        XCTAssertNil(expired?.wakeupsPerSecond)
        XCTAssertNotEqual(expired?.watts ?? -1, 1)
    }

    func testCounterDecreaseReplacesTheAnchorAndKeepsEarlierBuckets() {
        var ledger = ProcessEnergyMinuteLedger()
        _ = push(&ledger, energy: 0, wakeups: 0, at: 0)
        _ = push(&ledger, energy: 10_000_000_000, wakeups: 10, at: 10)
        let dropped = push(&ledger, energy: 1, wakeups: 1, at: 20)
        XCTAssertEqual(dropped?.watts ?? -1, 1, accuracy: 1e-9)
        XCTAssertNotNil(dropped?.watts)
        let rebuilt = push(&ledger, energy: 30_000_000_001, wakeups: 31, at: 30)
        XCTAssertEqual(rebuilt?.watts ?? -1, 2, accuracy: 1e-9)
        XCTAssertEqual(rebuilt?.wakeupsPerSecond ?? -1, 2, accuracy: 1e-9)
        XCTAssertNotEqual(rebuilt?.watts ?? -1, 3)
    }

    func testWakeupDecreaseAloneAddsNothing() {
        var ledger = ProcessEnergyMinuteLedger()
        _ = push(&ledger, energy: 0, wakeups: 100, at: 0)
        _ = push(&ledger, energy: 10_000_000_000, wakeups: 110, at: 10)
        let dropped = push(&ledger, energy: 20_000_000_000, wakeups: 40, at: 20)
        XCTAssertEqual(dropped?.watts ?? -1, 1, accuracy: 1e-9)
        XCTAssertEqual(dropped?.wakeupsPerSecond ?? -1, 1, accuracy: 1e-9)
        XCTAssertNotEqual(dropped?.watts ?? -1, 2)
    }

    func testNonPositiveDurationReplacesTheAnchorWithoutAdding() {
        var ledger = ProcessEnergyMinuteLedger()
        _ = push(&ledger, energy: 0, wakeups: 0, at: 0)
        _ = push(&ledger, energy: 10_000_000_000, wakeups: 10, at: 10)
        let sameInstant = push(&ledger, energy: 50_000_000_000, wakeups: 50, at: 10)
        XCTAssertEqual(sameInstant?.watts ?? -1, 1, accuracy: 1e-9)
        XCTAssertNotNil(sameInstant?.watts)
        let next = push(&ledger, energy: 70_000_000_000, wakeups: 70, at: 20)
        XCTAssertEqual(next?.watts ?? -1, 1.5, accuracy: 1e-9)
        XCTAssertEqual(next?.wakeupsPerSecond ?? -1, 1.5, accuracy: 1e-9)
        XCTAssertNotEqual(next?.watts ?? -1, 2)
    }

    func testBucketAtExactlyOneHourStaysAndOneSecondLaterDrops() {
        var ledger = ProcessEnergyMinuteLedger()
        _ = push(&ledger, energy: 0, wakeups: 0, at: 0)
        _ = push(&ledger, energy: 10_000_000_000, wakeups: 10, at: 10)
        let kept = pushMissing(&ledger, at: 3_600)
        XCTAssertEqual(kept?.watts ?? -1, 1, accuracy: 1e-9)
        XCTAssertNotNil(kept?.watts)
        let dropped = pushMissing(&ledger, at: 3_601)
        XCTAssertNil(dropped?.watts)
        XCTAssertNil(dropped?.wakeupsPerSecond)
        XCTAssertEqual(ProcessEnergyText.watts(dropped?.watts), "—")
        XCTAssertNotEqual(dropped?.watts ?? -1, 0)
    }

    func testMoreThanSixtyBucketsDropsTheOldest() {
        var ledger = ProcessEnergyMinuteLedger()
        _ = push(&ledger, energy: 0, wakeups: 0, at: -10, now: -10)
        var rates: ProcessEnergyRates?
        for index in 0...60 {
            let at = TimeInterval(index * 60)
            rates = push(
                &ledger,
                energy: UInt64(index + 1) * 1_000_000_000,
                wakeups: UInt64(index + 1) * 60,
                at: at,
                now: 3_600
            )
        }
        XCTAssertEqual(rates?.watts ?? -1, 1.0 / 60.0, accuracy: 1e-9)
        XCTAssertEqual(rates?.wakeupsPerSecond ?? -1, 1, accuracy: 1e-9)
        XCTAssertNotEqual(rates?.watts ?? -1, 61.0 / 3610.0)
        XCTAssertNotEqual(rates?.wakeupsPerSecond ?? -1, 3600.0 / 3550.0)
    }

    func testFailedListDoesNotMutateBucketsOrApplyADecrease() {
        var ledger = ProcessEnergyMinuteLedger()
        _ = push(&ledger, energy: 0, wakeups: 0, at: 0)
        _ = push(&ledger, energy: 10_000_000_000, wakeups: 10, at: 10)
        let failed = ledger.advance(listed: [:], now: origin.addingTimeInterval(15), listSucceeded: false)
        XCTAssertTrue(failed.isEmpty)
        let decreased = ledger.advance(
            listed: [7: tick(energy: 1, wakeups: 1, at: 15)],
            now: origin.addingTimeInterval(15),
            listSucceeded: false
        )
        XCTAssertTrue(decreased.isEmpty)
        let continued = push(&ledger, energy: 30_000_000_000, wakeups: 30, at: 30)
        XCTAssertEqual(continued?.watts ?? -1, 1, accuracy: 1e-9)
        XCTAssertEqual(continued?.wakeupsPerSecond ?? -1, 1, accuracy: 1e-9)
    }

    func testLeavingTheListDropsBucketsAndThePidReturnsWithoutAnAnchor() {
        var ledger = ProcessEnergyMinuteLedger()
        _ = push(&ledger, energy: 0, wakeups: 0, at: 0)
        _ = push(&ledger, energy: 10_000_000_000, wakeups: 10, at: 10)
        let gone = ledger.advance(listed: [:], now: origin.addingTimeInterval(15), listSucceeded: true)
        XCTAssertTrue(gone.isEmpty)
        let returned = push(&ledger, energy: 10_000_000_000, wakeups: 10, at: 20)
        XCTAssertNil(returned?.watts)
        XCTAssertNil(returned?.wakeupsPerSecond)
        XCTAssertNotEqual(returned?.watts ?? -1, 0.5)
        let fresh = push(&ledger, energy: 20_000_000_000, wakeups: 20, at: 30)
        XCTAssertEqual(fresh?.watts ?? -1, 1, accuracy: 1e-9)
        XCTAssertNotEqual(fresh?.watts ?? -1, 20.0 / 30.0)
    }

    func testEveryListedPidGetsARateAndPidsStaySeparate() {
        var ledger = ProcessEnergyMinuteLedger()
        let first = ledger.advance(
            listed: [
                1: tick(energy: 0, wakeups: 0, at: 0),
                2: tick(energy: 4_000_000_000, wakeups: 1, at: 0),
            ],
            now: origin,
            listSucceeded: true
        )
        XCTAssertEqual(first.count, 2)
        XCTAssertEqual(first[1], .missing)
        XCTAssertEqual(first[2], .missing)
        let second = ledger.advance(
            listed: [
                1: tick(energy: 10_000_000_000, wakeups: 10, at: 10),
                2: nil,
            ],
            now: origin.addingTimeInterval(10),
            listSucceeded: true
        )
        XCTAssertEqual(second.count, 2)
        XCTAssertEqual(second[1]?.watts ?? -1, 1, accuracy: 1e-9)
        XCTAssertEqual(second[1]?.wakeupsPerSecond ?? -1, 1, accuracy: 1e-9)
        XCTAssertNil(second[2]?.watts)
        XCTAssertNotNil(second[2])
        let onlyFirst = ledger.advance(
            listed: [1: tick(energy: 20_000_000_000, wakeups: 20, at: 20)],
            now: origin.addingTimeInterval(20),
            listSucceeded: true
        )
        XCTAssertEqual(onlyFirst.count, 1)
        XCTAssertNil(onlyFirst[2])
        XCTAssertEqual(onlyFirst[1]?.watts ?? -1, 1, accuracy: 1e-9)
    }

    func testHourRatesGroupLikeAnyRateTableAndAGapIsNotPartialForOneProcess() throws {
        var ledger = ProcessEnergyMinuteLedger()
        _ = ledger.advance(
            listed: [
                20: tick(energy: 0, wakeups: 0, at: 0),
                10: tick(energy: 0, wakeups: 0, at: 0),
            ],
            now: origin,
            listSucceeded: true
        )
        let rates = ledger.advance(
            listed: [
                20: tick(energy: 2_000_000_000, wakeups: 4, at: 10),
                10: nil,
            ],
            now: origin.addingTimeInterval(10),
            listSucceeded: true
        )
        let mailLead = row(20, "Mail", memory: 200, decoyWatts: 7)
        let mailOther = row(10, "Mail", memory: 100, decoyWatts: 99)
        let grouped = EnergyPage.display(
            rows: [mailLead, mailOther],
            windowRates: rates,
            grouped: true
        )
        let reading = try XCTUnwrap(grouped.readings[20])
        XCTAssertEqual(reading.watts ?? -1, 0.2, accuracy: 1e-9)
        XCTAssertEqual(reading.wakeupsPerSecond ?? -1, 0.4, accuracy: 1e-9)
        XCTAssertTrue(reading.energyReadingIsPartial)
        XCTAssertTrue(reading.wakeupReadingIsPartial)
        XCTAssertEqual(ProcessEnergyText.caption(isPartial: true), "部分读数")
        XCTAssertEqual(grouped.rows.first { $0.name == "Mail" }?.energyWatts, 7)

        let alone = EnergyPage.display(
            rows: [mailLead],
            windowRates: [20: try XCTUnwrap(rates[20])],
            grouped: false
        )
        XCTAssertEqual(alone.readings[20]?.energyReadingIsPartial, false)
        XCTAssertEqual(alone.readings[20]?.wakeupReadingIsPartial, false)
        XCTAssertEqual(ProcessEnergyText.watts(alone.readings[20]?.watts), "0.2 W")
    }

    private func tick(energy: UInt64, wakeups: UInt64, at seconds: TimeInterval) -> EnergyTick {
        EnergyTick(
            energyNanojoules: energy,
            interruptWakeups: wakeups,
            date: origin.addingTimeInterval(seconds)
        )
    }

    @discardableResult
    private func push(
        _ ledger: inout ProcessEnergyMinuteLedger,
        pid: Int32 = 7,
        energy: UInt64,
        wakeups: UInt64,
        at seconds: TimeInterval,
        now: TimeInterval? = nil,
        listSucceeded: Bool = true
    ) -> ProcessEnergyRates? {
        ledger.advance(
            listed: [pid: tick(energy: energy, wakeups: wakeups, at: seconds)],
            now: origin.addingTimeInterval(now ?? seconds),
            listSucceeded: listSucceeded
        )[pid]
    }

    private func pushMissing(
        _ ledger: inout ProcessEnergyMinuteLedger,
        pid: Int32 = 7,
        at seconds: TimeInterval
    ) -> ProcessEnergyRates? {
        ledger.advance(
            listed: [pid: nil],
            now: origin.addingTimeInterval(seconds),
            listSucceeded: true
        )[pid]
    }

    private func row(_ pid: Int32, _ name: String, memory: UInt64, decoyWatts: Double) -> ProcessRow {
        ProcessRow(
            pid: pid,
            name: name,
            bundleIdentifier: nil,
            executablePath: nil,
            cpuPercent: 1,
            memoryBytes: memory,
            threadCount: 1,
            energyWatts: decoyWatts,
            wakeupsPerSecond: decoyWatts
        )
    }
}
