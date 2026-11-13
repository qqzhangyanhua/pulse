import XCTest
@testable import SamplingCore

/// Chip-temperature projection. Sensors, frame outcome, and page transition in;
/// the current value, its text, and this visit's success flag out. No IOKit.
final class ChipTemperaturePageTests: XCTestCase {
    func testHottestPMUtdieBeatsTheCalibrationSensor() {
        let page = succeed([
            sensor("PMU tdie0", 44.7),
            sensor("PMU tdie1", 45.4),
            sensor("PMU tdie10", 44.9),
            sensor("PMU tcal", 51.9),
        ])

        XCTAssertEqual(page.celsius, 45.4)
        XCTAssertEqual(page.text, "45 °C")
        XCTAssertTrue(page.visitSucceeded)
        XCTAssertNotEqual(page.celsius, 51.9)
    }

    func testDuplicateNamesStillTakeTheMaximumAndUnrelatedSensorsAreIgnored() {
        let page = succeed([
            sensor("PMU tdie1", 44.2),
            sensor("PMU tdie1", 46.2),
            sensor("PMU tdie1", 43.0),
            sensor("PMU tdev1", 60),
            sensor("PMU TP1s", 70),
            sensor("gas gauge battery", 39),
            sensor("NAND CH0 temp", 38),
            sensor("GPU MTR Temp Sensor", 80),
            sensor("pmu tdie0", 90),
        ])

        XCTAssertEqual(page.celsius, 46.2)
        XCTAssertEqual(page.text, "46 °C")
    }

    func testNoFiniteChipSensorStaysADashAndStillSucceedsTheVisit() {
        let onlyOther = succeed([
            sensor("gas gauge battery", 40),
            sensor("NAND CH0 temp", 39),
            sensor("GPU MTR Temp Sensor", 70),
            sensor("pmu tdie0", 88),
        ])
        XCTAssertNil(onlyOther.celsius)
        XCTAssertEqual(onlyOther.text, CPUPercentText.missing)
        XCTAssertTrue(onlyOther.visitSucceeded)

        let nonFinite = succeed([
            sensor("PMU tdie0", .nan),
            sensor("PMU tdie1", .infinity),
            sensor("PMU tdie2", -.infinity),
            sensor(nil, 30),
            sensor("PMU tdie3", nil),
        ])
        XCTAssertNil(nonFinite.celsius)
        XCTAssertEqual(nonFinite.text, CPUPercentText.missing)
        XCTAssertTrue(nonFinite.visitSucceeded)
    }

    func testHalfAwayFromZeroDisplaysAnIntegerDegree() {
        XCTAssertEqual(succeed([sensor("PMU tdie0", 44.5)]).text, "45 °C")
        XCTAssertEqual(succeed([sensor("PMU tdie0", 44.4)]).text, "44 °C")
        XCTAssertEqual(succeed([sensor("PMU tdie0", -44.5)]).text, "-45 °C")
        XCTAssertEqual(succeed([sensor("PMU tdie0", 0)]).celsius, 0)
        XCTAssertEqual(succeed([sensor("PMU tdie0", 0)]).text, "0 °C")
    }

    func testAValueFromBeforeThisVisitIsNotShown() {
        let stale = ChipTemperaturePageState(celsius: 40, visitSucceeded: false)
        XCTAssertEqual(stale.text, CPUPercentText.missing)
    }

    func testJustEnteredDropsThePreviousVisitBeforeThisFrame() {
        let previous = succeed([sensor("PMU tdie0", 45.4)])

        let waiting = ChipTemperaturePageProjection.apply(
            sensors: [sensor("PMU tdie0", 70)],
            frame: .pending,
            sampledAt: Date(timeIntervalSince1970: 2),
            current: previous,
            transition: .justEntered
        )
        XCTAssertNil(waiting.celsius)
        XCTAssertFalse(waiting.visitSucceeded)
        XCTAssertEqual(waiting.text, CPUPercentText.missing)

        let failed = ChipTemperaturePageProjection.apply(
            sensors: [sensor("PMU tdie0", 70)],
            frame: .failed,
            sampledAt: Date(timeIntervalSince1970: 2),
            current: previous,
            transition: .justEntered
        )
        XCTAssertNil(failed.celsius)
        XCTAssertFalse(failed.visitSucceeded)
        XCTAssertEqual(failed.text, CPUPercentText.missing)

        let entered = succeed(
            [sensor("PMU tdie0", 41.2)],
            at: 3,
            current: previous,
            transition: .justEntered
        )
        XCTAssertEqual(entered.celsius, 41.2)
        XCTAssertEqual(entered.text, "41 °C")
        XCTAssertTrue(entered.visitSucceeded)
    }

    func testJustLeftDoesNotPublishThisFrame() {
        let current = succeed([sensor("PMU tdie0", 45.4)])
        let left = ChipTemperaturePageProjection.apply(
            sensors: [sensor("PMU tdie0", 80)],
            frame: .succeeded,
            sampledAt: Date(timeIntervalSince1970: 2),
            current: current,
            transition: .justLeft
        )

        XCTAssertEqual(left.celsius, 45.4)
        XCTAssertEqual(left.text, "45 °C")
        XCTAssertTrue(left.visitSucceeded)
        XCTAssertNotEqual(left.celsius, 80)
    }

    func testStayedFailureKeepsTheValueAndANewVisitStaysADash() {
        let current = succeed([sensor("PMU tdie0", 44.4)])
        XCTAssertEqual(current.text, "44 °C")

        let failed = ChipTemperaturePageProjection.apply(
            sensors: [sensor("PMU tdie0", 90)],
            frame: .failed,
            sampledAt: Date(timeIntervalSince1970: 2),
            current: current,
            transition: .stayed
        )
        XCTAssertEqual(failed.celsius, 44.4)
        XCTAssertEqual(failed.text, "44 °C")
        XCTAssertTrue(failed.visitSucceeded)

        let before = ChipTemperaturePageProjection.apply(
            sensors: [sensor("PMU tdie0", 90)],
            frame: .failed,
            sampledAt: Date(timeIntervalSince1970: 1),
            current: .initial,
            transition: .stayed
        )
        XCTAssertNil(before.celsius)
        XCTAssertFalse(before.visitSucceeded)
        XCTAssertEqual(before.text, CPUPercentText.missing)

        let pending = ChipTemperaturePageProjection.apply(
            sensors: [sensor("PMU tdie0", 90)],
            frame: .pending,
            sampledAt: Date(timeIntervalSince1970: 1),
            current: .initial,
            transition: .stayed
        )
        XCTAssertNil(pending.celsius)
        XCTAssertFalse(pending.visitSucceeded)
        XCTAssertEqual(pending.text, CPUPercentText.missing)

        let laterPending = ChipTemperaturePageProjection.apply(
            frame: .pending,
            sampledAt: Date(timeIntervalSince1970: 3),
            current: current,
            transition: .stayed
        )
        XCTAssertEqual(laterPending.celsius, 44.4)
        XCTAssertEqual(laterPending.text, "44 °C")
    }

    func testSuccessfulMissClearsTheValueAndKeepsTheVisitSucceeded() {
        let current = succeed([sensor("PMU tdie0", 45)])
        let missing = succeed([sensor("PMU tcal", 51.9)], current: current)
        XCTAssertNil(missing.celsius)
        XCTAssertEqual(missing.text, CPUPercentText.missing)
        XCTAssertTrue(missing.visitSucceeded)
    }

    func testCopyNamesChipTemperatureWithoutAlarmWords() {
        XCTAssertEqual(ChipTemperatureCopy.title, "芯片温度")
        for forbidden in ["CPU 温度", "GPU 温度", "核心温度", "SMC 温度", "过热", "危险"] {
            XCTAssertFalse(ChipTemperatureCopy.title.contains(forbidden), forbidden)
        }
    }

    private func succeed(
        _ sensors: [ChipTemperatureSensor],
        at time: TimeInterval = 1,
        current: ChipTemperaturePageState = .initial,
        transition: ChipTemperaturePageTransition = .stayed
    ) -> ChipTemperaturePageState {
        ChipTemperaturePageProjection.apply(
            sensors: sensors,
            frame: .succeeded,
            sampledAt: Date(timeIntervalSince1970: time),
            current: current,
            transition: transition
        )
    }

    private func sensor(_ name: String?, _ celsius: Double?) -> ChipTemperatureSensor {
        ChipTemperatureSensor(productName: name, celsius: celsius)
    }
}
