import XCTest
@testable import SamplingCore

/// Two-frame energy and idle-wake rates. Literals are the spec, not a second formula.
final class ProcessEnergyLoadTests: XCTestCase {
    func testFirstFrameIsNilAndNotZero() {
        let tick = EnergyTick(
            energyNanojoules: 2_000_000_000,
            interruptWakeups: 8,
            date: Date(timeIntervalSince1970: 10)
        )
        let sample = ProcessEnergyLoad.advance(previous: nil, reading: tick)
        XCTAssertNil(sample.rates.watts)
        XCTAssertNil(sample.rates.wakeupsPerSecond)
        XCTAssertNotEqual(sample.rates.watts, 0)
        XCTAssertNotEqual(sample.rates.wakeupsPerSecond, 0)
        XCTAssertEqual(sample.baseline, tick)
    }

    func testTwoFrameDeltaIsWattsAndWakeupsPerSecond() {
        let previous = EnergyTick(
            energyNanojoules: 1_000_000_000,
            interruptWakeups: 10,
            date: Date(timeIntervalSince1970: 0)
        )
        let current = EnergyTick(
            energyNanojoules: 4_000_000_000,
            interruptWakeups: 16,
            date: Date(timeIntervalSince1970: 2)
        )
        let rates = ProcessEnergyLoad.rates(previous: previous, current: current)
        XCTAssertEqual(rates.watts ?? -1, 1.5, accuracy: 0.000_001)
        XCTAssertEqual(rates.wakeupsPerSecond ?? -1, 3, accuracy: 0.000_001)
        XCTAssertNotEqual(rates.watts ?? -1, 1_500_000_000, accuracy: 1)
    }

    func testIdleDeltaIsRealZeroNotAPlaceholder() {
        let previous = EnergyTick(
            energyNanojoules: 5_000_000_000,
            interruptWakeups: 40,
            date: Date(timeIntervalSince1970: 0)
        )
        let current = EnergyTick(
            energyNanojoules: 5_000_000_000,
            interruptWakeups: 40,
            date: Date(timeIntervalSince1970: 2)
        )
        let rates = ProcessEnergyLoad.rates(previous: previous, current: current)
        XCTAssertEqual(rates.watts ?? -1, 0, accuracy: 0.000_001)
        XCTAssertEqual(rates.wakeupsPerSecond ?? -1, 0, accuracy: 0.000_001)
        XCTAssertNotEqual(rates, .missing)
    }

    func testDecreasedCounterIsNilAndNotNegative() {
        let previous = EnergyTick(
            energyNanojoules: 100,
            interruptWakeups: 10,
            date: Date(timeIntervalSince1970: 1)
        )
        let wrapped = EnergyTick(
            energyNanojoules: 40,
            interruptWakeups: 20,
            date: Date(timeIntervalSince1970: 2)
        )
        let rates = ProcessEnergyLoad.rates(previous: previous, current: wrapped)
        XCTAssertNil(rates.watts)
        XCTAssertNil(rates.wakeupsPerSecond)
        XCTAssertNotEqual(rates.watts, 0)
        XCTAssertNotEqual(rates.wakeupsPerSecond, 0)

        let wakeupsDropped = EnergyTick(
            energyNanojoules: 200,
            interruptWakeups: 4,
            date: Date(timeIntervalSince1970: 2)
        )
        let wakeupRates = ProcessEnergyLoad.rates(previous: previous, current: wakeupsDropped)
        XCTAssertNil(wakeupRates.watts)
        XCTAssertNil(wakeupRates.wakeupsPerSecond)
    }

    func testFailedReadIsNilAndKeepsBaseline() {
        let baseline = EnergyTick(
            energyNanojoules: 1_000_000_000,
            interruptWakeups: 10,
            date: Date(timeIntervalSince1970: 3)
        )
        let denied = ProcessEnergyLoad.advance(previous: baseline, reading: nil)
        XCTAssertEqual(denied.rates, .missing)
        XCTAssertEqual(denied.baseline, baseline)
        XCTAssertNotEqual(denied.rates.watts, 0)

        let next = EnergyTick(
            energyNanojoules: 4_000_000_000,
            interruptWakeups: 16,
            date: Date(timeIntervalSince1970: 5)
        )
        let recovered = ProcessEnergyLoad.advance(previous: denied.baseline, reading: next)
        XCTAssertEqual(recovered.rates.watts ?? -1, 1.5, accuracy: 0.000_001)
        XCTAssertEqual(recovered.rates.wakeupsPerSecond ?? -1, 3, accuracy: 0.000_001)
    }

    func testZeroOrNegativeWallClockIsNil() {
        let date = Date(timeIntervalSince1970: 5)
        let previous = EnergyTick(energyNanojoules: 0, interruptWakeups: 0, date: date)
        let sameInstant = EnergyTick(energyNanojoules: 1_000_000_000, interruptWakeups: 4, date: date)
        XCTAssertEqual(ProcessEnergyLoad.rates(previous: previous, current: sameInstant), .missing)

        let backwards = EnergyTick(
            energyNanojoules: 1_000_000_000,
            interruptWakeups: 4,
            date: Date(timeIntervalSince1970: 4)
        )
        XCTAssertEqual(ProcessEnergyLoad.rates(previous: previous, current: backwards), .missing)
    }

    func testDecreasedCounterAdvancesBaselineSoTheNextFrameCanRecover() {
        let previous = EnergyTick(energyNanojoules: 100, interruptWakeups: 50, date: Date(timeIntervalSince1970: 1))
        let wrapped = EnergyTick(energyNanojoules: 1, interruptWakeups: 2, date: Date(timeIntervalSince1970: 2))
        let first = ProcessEnergyLoad.advance(previous: previous, reading: wrapped)
        XCTAssertEqual(first.rates, .missing)
        XCTAssertEqual(first.baseline, wrapped)

        let later = EnergyTick(
            energyNanojoules: 2_000_000_001,
            interruptWakeups: 8,
            date: Date(timeIntervalSince1970: 4)
        )
        let second = ProcessEnergyLoad.advance(previous: first.baseline, reading: later)
        XCTAssertEqual(second.rates.watts ?? -1, 1, accuracy: 0.000_001)
        XCTAssertEqual(second.rates.wakeupsPerSecond ?? -1, 3, accuracy: 0.000_001)
    }
}

final class ProcessEnergyTextTests: XCTestCase {
    func testMissingIsDashAndRealZeroIsShownInWatts() {
        XCTAssertEqual(ProcessEnergyText.watts(nil), "—")
        XCTAssertEqual(ProcessEnergyText.watts(0), "0.0 W")
        XCTAssertEqual(ProcessEnergyText.watts(1.5), "1.5 W")
        XCTAssertNotEqual(ProcessEnergyText.watts(nil), "0.0 W")
        XCTAssertNotEqual(ProcessEnergyText.watts(0), "—")
        XCTAssertFalse(ProcessEnergyText.watts(1.5).contains("分数"))
    }

    func testWakeupsShowTimesPerSecondAndKeepARealZero() {
        XCTAssertEqual(ProcessEnergyText.wakeups(nil), "—")
        XCTAssertEqual(ProcessEnergyText.wakeups(0), "0.0 次/秒")
        XCTAssertEqual(ProcessEnergyText.wakeups(3), "3.0 次/秒")
        XCTAssertNotEqual(ProcessEnergyText.wakeups(nil), "0.0 次/秒")
        XCTAssertNotEqual(ProcessEnergyText.wakeups(0), "—")
    }
}

final class ProcessEnergyGroupTests: XCTestCase {
    func testMixedMembersKeepThePartialSum() {
        let mixed = ProcessEnergyGroup.sum([1.5, nil])
        XCTAssertEqual(mixed.value ?? -1, 1.5, accuracy: 0.000_001)
        XCTAssertTrue(mixed.isPartial)
    }

    func testAllMissingStaysNilWithoutAPartialMark() {
        let missing = ProcessEnergyGroup.sum([nil, nil])
        XCTAssertNil(missing.value)
        XCTAssertFalse(missing.isPartial)
        XCTAssertNil(ProcessEnergyGroup.sum([]).value)
        XCTAssertFalse(ProcessEnergyGroup.sum([]).isPartial)
    }

    func testCompleteMembersAreNotPartialAndARealZeroStillAdds() {
        let complete = ProcessEnergyGroup.sum([1.5, 2.5])
        XCTAssertEqual(complete.value ?? -1, 4, accuracy: 0.000_001)
        XCTAssertFalse(complete.isPartial)

        let zeros = ProcessEnergyGroup.sum([0, 2])
        XCTAssertEqual(zeros.value ?? -1, 2, accuracy: 0.000_001)
        XCTAssertFalse(zeros.isPartial)
    }

    func testPartialSumKeepsZeroWhenAnotherMemberIsMissing() {
        XCTAssertNil(AppGroupProjection.sum([0, nil]))
        let partial = ProcessEnergyGroup.sum([0, nil])
        XCTAssertEqual(partial.value ?? -1, 0, accuracy: 0.000_001)
        XCTAssertTrue(partial.isPartial)
        XCTAssertNotEqual(partial.value, nil)
    }

    func testPartialCaptionIsTheDetailMark() {
        XCTAssertEqual(ProcessEnergyText.caption(isPartial: true), "部分读数")
        XCTAssertEqual(ProcessEnergyText.caption(isPartial: false), "")
        XCTAssertEqual(ProcessEnergyText.impactTitle, "能耗影响")
        XCTAssertEqual(ProcessEnergyText.wakeTitle, "唤醒")
    }

    func testAppGroupSumsPresentMembersAndMarksPartialReadings() {
        let mixed = AppGroupProjection.combine([
            energyRow(pid: 1, watts: 1.5, wakeups: nil),
            energyRow(pid: 2, watts: nil, wakeups: 4),
        ])
        XCTAssertEqual(mixed.energyWatts ?? -1, 1.5, accuracy: 0.000_001)
        XCTAssertTrue(mixed.energyReadingIsPartial)
        XCTAssertEqual(mixed.wakeupsPerSecond ?? -1, 4, accuracy: 0.000_001)
        XCTAssertTrue(mixed.wakeupReadingIsPartial)
        XCTAssertEqual(ProcessEnergyText.caption(isPartial: mixed.energyReadingIsPartial), "部分读数")
        XCTAssertEqual(ProcessEnergyText.caption(isPartial: mixed.wakeupReadingIsPartial), "部分读数")

        let missing = AppGroupProjection.combine([
            energyRow(pid: 3, watts: nil, wakeups: nil),
            energyRow(pid: 4, watts: nil, wakeups: nil),
        ])
        XCTAssertNil(missing.energyWatts)
        XCTAssertNil(missing.wakeupsPerSecond)
        XCTAssertFalse(missing.energyReadingIsPartial)
        XCTAssertFalse(missing.wakeupReadingIsPartial)

        let complete = AppGroupProjection.combine([
            energyRow(pid: 5, watts: 0, wakeups: 2),
            energyRow(pid: 6, watts: 1, wakeups: 3),
        ])
        XCTAssertEqual(complete.energyWatts ?? -1, 1, accuracy: 0.000_001)
        XCTAssertEqual(complete.wakeupsPerSecond ?? -1, 5, accuracy: 0.000_001)
        XCTAssertFalse(complete.energyReadingIsPartial)
        XCTAssertFalse(complete.wakeupReadingIsPartial)
    }

    private func energyRow(pid: Int32, watts: Double?, wakeups: Double?) -> ProcessRow {
        ProcessRow(
            pid: pid,
            name: "Chrome",
            bundleIdentifier: nil,
            executablePath: nil,
            cpuPercent: 1,
            memoryBytes: 10,
            threadCount: 1,
            energyWatts: watts,
            wakeupsPerSecond: wakeups
        )
    }
}

final class ProcessEnergyColumnTests: XCTestCase {
    func testCPUPageAddsEnergyAndIdleWakeColumns() {
        XCTAssertEqual(
            ProcessColumnTitle.cpuPage,
            ["名称", "CPU", "内存", "能耗影响", "唤醒", "线程"]
        )
        XCTAssertEqual(ProcessColumnTitle.energy, ProcessEnergyText.impactTitle)
        XCTAssertEqual(ProcessColumnTitle.wakeups, ProcessEnergyText.wakeTitle)
        XCTAssertTrue(ProcessColumnTitle.cpuPage.contains(ProcessColumnTitle.memory))
        XCTAssertFalse(ProcessColumnTitle.networkPage.contains(ProcessEnergyText.impactTitle))
        XCTAssertFalse(ProcessColumnTitle.diskPage.contains(ProcessEnergyText.impactTitle))
        XCTAssertFalse(ProcessColumnTitle.diskPage.contains(ProcessEnergyText.wakeTitle))
    }
}

final class ProcessEnergySortTests: XCTestCase {
    func testMissingEnergySortsBelowARealZeroInBothDirections() {
        let rows = [
            energyRow(pid: 3, watts: nil, wakeups: 1),
            energyRow(pid: 1, watts: 0, wakeups: nil),
            energyRow(pid: 2, watts: 1.5, wakeups: 4),
        ]
        let descending = ProcessTableSort(column: .energy, descending: true)
        let ascending = ProcessTableSort(column: .energy, descending: false)
        XCTAssertEqual(descending.ordered(rows).map(\.pid), [2, 1, 3])
        XCTAssertEqual(ascending.ordered(rows).map(\.pid), [3, 1, 2])
        XCTAssertEqual(rows[0].energyWatts ?? -1, -1)
        XCTAssertLessThan(rows[0].energyWatts ?? -1, 0)

        let wakeDescending = ProcessTableSort(column: .wakeups, descending: true)
        let wakeAscending = ProcessTableSort(column: .wakeups, descending: false)
        XCTAssertEqual(wakeDescending.ordered(rows).map(\.pid), [2, 3, 1])
        XCTAssertEqual(wakeAscending.ordered(rows).map(\.pid), [1, 3, 2])
    }

    func testEnergyColumnClickStartsDescendingAndToggles() {
        let baseline = ProcessTableSort.defaultSort(for: .cpu)
        let energy = baseline.selecting(.energy)
        XCTAssertEqual(energy, ProcessTableSort(column: .energy, descending: true))
        XCTAssertEqual(energy.selecting(.energy), ProcessTableSort(column: .energy, descending: false))
        let wakeups = energy.selecting(.wakeups)
        XCTAssertEqual(wakeups, ProcessTableSort(column: .wakeups, descending: true))
        XCTAssertEqual(wakeups.selecting(.wakeups), ProcessTableSort(column: .wakeups, descending: false))
    }

    func testEqualEnergyBreaksTiesByPidAscending() {
        let rows = [
            energyRow(pid: 30, watts: 1.5, wakeups: 2),
            energyRow(pid: 10, watts: 1.5, wakeups: 2),
            energyRow(pid: 20, watts: 1.5, wakeups: 2),
        ]
        let descending = ProcessTableSort(column: .energy, descending: true)
        let ascending = ProcessTableSort(column: .wakeups, descending: false)
        XCTAssertEqual(descending.ordered(rows).map(\.pid), [10, 20, 30])
        XCTAssertEqual(ascending.ordered(rows).map(\.pid), [10, 20, 30])
    }

    private func energyRow(pid: Int32, watts: Double?, wakeups: Double?) -> ProcessRow {
        ProcessRow(
            pid: pid,
            name: "p\(pid)",
            bundleIdentifier: nil,
            executablePath: nil,
            cpuPercent: nil,
            memoryBytes: 1,
            threadCount: 1,
            energyWatts: watts,
            wakeupsPerSecond: wakeups
        )
    }
}
