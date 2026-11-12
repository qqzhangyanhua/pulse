import XCTest
@testable import SamplingCore

final class ThermalAdviceThrottleTests: XCTestCase {
    func testFirstCallWithNoPriorUpdateReturnsTrue() {
        XCTAssertTrue(ThermalAdviceThrottle.shouldUpdate(now: 1, lastUpdate: nil))
    }

    func testIntervalOfFiveSecondsOrMoreReturnsTrue() {
        XCTAssertTrue(ThermalAdviceThrottle.shouldUpdate(now: 5, lastUpdate: 0))
        XCTAssertTrue(ThermalAdviceThrottle.shouldUpdate(now: 12, lastUpdate: 7))
        XCTAssertTrue(ThermalAdviceThrottle.shouldUpdate(now: 20, lastUpdate: 10))
    }

    func testIntervalUnderFiveSecondsReturnsFalse() {
        XCTAssertFalse(ThermalAdviceThrottle.shouldUpdate(now: 4, lastUpdate: 0))
        XCTAssertFalse(ThermalAdviceThrottle.shouldUpdate(now: 9, lastUpdate: 5))
        XCTAssertFalse(ThermalAdviceThrottle.shouldUpdate(now: 14.9, lastUpdate: 10))
    }

    func testCallerPublishesAtOneAndSixOnly() {
        var lastUpdate: Double?
        var published: [Double] = []
        for now in [1.0, 2.0, 3.0, 4.0, 5.0, 6.0] {
            guard ThermalAdviceThrottle.shouldUpdate(now: now, lastUpdate: lastUpdate) else { continue }
            published.append(now)
            lastUpdate = now
        }
        XCTAssertEqual(published, [1, 6])
    }
}
