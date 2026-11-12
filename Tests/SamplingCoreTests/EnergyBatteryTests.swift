import XCTest
@testable import SamplingCore

final class EnergyBatteryTests: XCTestCase {
    func testNoInternalBatteryHidesTheCard() {
        XCTAssertNil(EnergyBattery.card(.absent))
        XCTAssertNil(EnergyBattery.card(reading(
            hasInternalBattery: false,
            percent: 80,
            supply: .battery,
            remainingSeconds: 3_600
        )))
        XCTAssertNil(EnergyBattery.card(reading(
            hasInternalBattery: false,
            percent: 40,
            supply: .adapter,
            charging: true,
            minutesToFull: 20
        )))
    }

    func testMissingPercentIsDashAndZeroIsZero() {
        XCTAssertEqual(EnergyBattery.card(reading(percent: nil))?.percent, "—")
        XCTAssertEqual(EnergyBattery.card(reading(percent: 0))?.percent, "0%")
        XCTAssertEqual(EnergyBattery.card(reading(percent: 42))?.percent, "42%")
    }

    func testPowerCopyIsOnlyBatteryOrAdapter() {
        XCTAssertEqual(EnergyBattery.card(reading(supply: .battery))?.power, "电池")
        XCTAssertEqual(EnergyBattery.card(reading(supply: .adapter))?.power, "电源适配器")
        let battery = EnergyBattery.card(reading(supply: .battery))?.power ?? ""
        let adapter = EnergyBattery.card(reading(supply: .adapter))?.power ?? ""
        XCTAssertFalse(battery.contains("外接电源"))
        XCTAssertFalse(adapter.contains("外接电源"))
        XCTAssertFalse(battery.contains("UPS"))
        XCTAssertFalse(adapter.contains("UPS"))
    }

    func testLowPowerModeIsLabeledOnlyWhenOn() {
        XCTAssertEqual(EnergyBattery.card(reading(lowPowerMode: true))?.lowPowerMode, "低电量模式")
        XCTAssertNil(EnergyBattery.card(reading(lowPowerMode: false))?.lowPowerMode)
    }

    func testOnBatteryFormatsFiniteSecondsAndEstimatesTheSentinels() {
        XCTAssertEqual(time(supply: .battery, remainingSeconds: 0), "剩余 0 秒")
        XCTAssertEqual(time(supply: .battery, remainingSeconds: 45), "剩余 45 秒")
        XCTAssertEqual(time(supply: .battery, remainingSeconds: 59), "剩余 59 秒")
        XCTAssertEqual(time(supply: .battery, remainingSeconds: 90), "剩余 1 分钟")
        XCTAssertEqual(time(supply: .battery, remainingSeconds: 45 * 60), "剩余 45 分钟")
        XCTAssertEqual(time(supply: .battery, remainingSeconds: 3_600), "剩余 1 小时")
        XCTAssertEqual(time(supply: .battery, remainingSeconds: 3_600 + 30 * 60), "剩余 1 小时 30 分钟")
        XCTAssertEqual(time(supply: .battery, remainingSeconds: 3_600 + 90), "剩余 1 小时 1 分钟")
        XCTAssertEqual(time(supply: .battery, remainingSeconds: -1), "正在估算…")
        XCTAssertEqual(time(supply: .battery, remainingSeconds: -2), "正在估算…")
        XCTAssertEqual(time(supply: .battery, remainingSeconds: nil), "正在估算…")
    }

    func testChargingUsesMinutesUntilFull() {
        XCTAssertEqual(
            time(supply: .adapter, charging: true, minutesToFull: 0),
            "充满还需 0 分钟"
        )
        XCTAssertEqual(
            time(supply: .adapter, charging: true, minutesToFull: 45),
            "充满还需 45 分钟"
        )
        XCTAssertEqual(
            time(supply: .adapter, charging: true, minutesToFull: 60),
            "充满还需 1 小时"
        )
        XCTAssertEqual(
            time(supply: .adapter, charging: true, minutesToFull: 90),
            "充满还需 1 小时 30 分钟"
        )
        XCTAssertEqual(
            time(supply: .adapter, charging: true, minutesToFull: nil),
            "正在估算…"
        )
        XCTAssertEqual(
            time(supply: .adapter, charging: true, minutesToFull: -1),
            "正在估算…"
        )
        XCTAssertEqual(
            time(supply: .adapter, charging: true, remainingSeconds: 3_600, minutesToFull: 45),
            "充满还需 45 分钟"
        )
    }

    func testPluggedInAndNotChargingShowsConnectedWithoutATime() {
        let plugged = time(supply: .adapter, charging: false, remainingSeconds: 3_600, minutesToFull: 10)
        XCTAssertEqual(plugged, "已接通电源")
        XCTAssertFalse(plugged.contains("剩余"))
        XCTAssertFalse(plugged.contains("充满"))
    }

    func testOnBatteryIgnoresTheChargingClock() {
        XCTAssertEqual(
            time(supply: .battery, charging: true, remainingSeconds: 45, minutesToFull: 10),
            "剩余 45 秒"
        )
    }

    func testDoesNotEstimateTimeFromPercent() {
        XCTAssertEqual(
            time(percent: 50, supply: .battery, remainingSeconds: -1),
            "正在估算…"
        )
        XCTAssertEqual(
            time(percent: 80, supply: .adapter, charging: true, minutesToFull: nil),
            "正在估算…"
        )
        XCTAssertEqual(
            time(percent: 100, supply: .adapter, charging: false),
            "已接通电源"
        )
    }

    func testUnreadSupplyStaysMissingInsteadOfGuessingASource() {
        let card = EnergyBattery.card(reading(percent: 40, supply: nil, charging: false))
        XCTAssertEqual(card?.percent, "40%")
        XCTAssertEqual(card?.power, "—")
        XCTAssertEqual(card?.time, "正在估算…")
        XCTAssertEqual(
            EnergyBattery.card(reading(supply: nil, charging: true, minutesToFull: 30))?.time,
            "充满还需 30 分钟"
        )
    }

    private func time(
        percent: Int? = 80,
        supply: EnergyBatterySupply?,
        charging: Bool = false,
        lowPowerMode: Bool = false,
        remainingSeconds: Int? = nil,
        minutesToFull: Int? = nil
    ) -> String {
        EnergyBattery.card(reading(
            percent: percent,
            supply: supply,
            charging: charging,
            lowPowerMode: lowPowerMode,
            remainingSeconds: remainingSeconds,
            minutesToFull: minutesToFull
        ))?.time ?? ""
    }

    private func reading(
        hasInternalBattery: Bool = true,
        percent: Int? = 80,
        supply: EnergyBatterySupply? = .battery,
        charging: Bool = false,
        lowPowerMode: Bool = false,
        remainingSeconds: Int? = nil,
        minutesToFull: Int? = nil
    ) -> EnergyBatteryReading {
        EnergyBatteryReading(
            hasInternalBattery: hasInternalBattery,
            percent: percent,
            supply: supply,
            charging: charging,
            lowPowerMode: lowPowerMode,
            remainingSeconds: remainingSeconds,
            minutesToFull: minutesToFull
        )
    }
}
