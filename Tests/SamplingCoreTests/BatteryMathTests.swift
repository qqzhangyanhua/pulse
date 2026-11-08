import XCTest
@testable import SamplingCore

final class BatteryMathTests: XCTestCase {
    func testHealthPercentIsFullChargeOverDesign() {
        let half = BatteryMath.healthPercent(fullChargeCapacity: 2_500, designCapacity: 5_000)
        XCTAssertEqual(half, 0.5)

        let spec = BatteryMath.healthPercent(fullChargeCapacity: 4_500, designCapacity: 5_000)
        XCTAssertEqual(spec ?? -1, 0.9, accuracy: 0.000_000_1)

        let aboveDesign = BatteryMath.healthPercent(fullChargeCapacity: 7_500, designCapacity: 5_000)
        XCTAssertEqual(aboveDesign, 1.5)

        XCTAssertEqual(BatteryMath.healthPercent(fullChargeCapacity: 0, designCapacity: 5_000), 0)
        XCTAssertNil(BatteryMath.healthPercent(fullChargeCapacity: 5_000, designCapacity: 0))
        XCTAssertNil(BatteryMath.healthPercent(fullChargeCapacity: 5_000, designCapacity: -1))
        XCTAssertNil(BatteryMath.healthPercent(fullChargeCapacity: nil, designCapacity: 5_000))
        XCTAssertNil(BatteryMath.healthPercent(fullChargeCapacity: 5_000, designCapacity: nil))
        XCTAssertNil(BatteryMath.healthPercent(fullChargeCapacity: nil, designCapacity: nil))
    }

    func testPowerWattsKeepsTheDischargeSign() {
        XCTAssertEqual(BatteryMath.powerWatts(millivolts: 12_000, milliamps: -1_500), -18)
        XCTAssertEqual(BatteryMath.powerWatts(millivolts: 12_000, milliamps: 2_000), 24)
        XCTAssertEqual(BatteryMath.powerWatts(millivolts: 0, milliamps: -1_500), 0)
        XCTAssertNil(BatteryMath.powerWatts(millivolts: nil, milliamps: -1_500))
        XCTAssertNil(BatteryMath.powerWatts(millivolts: 12_000, milliamps: nil))
        XCTAssertNil(BatteryMath.powerWatts(millivolts: nil, milliamps: nil))
    }

    func testSignedMilliampsUnwrapsANegativeDischargeCurrent() {
        XCTAssertEqual(BatteryMath.signedMilliamps(18_446_744_073_709_550_201), -1_415)
        XCTAssertEqual(BatteryMath.signedMilliamps(1_500), 1_500)
        XCTAssertEqual(BatteryMath.signedMilliamps(0), 0)
    }
}
