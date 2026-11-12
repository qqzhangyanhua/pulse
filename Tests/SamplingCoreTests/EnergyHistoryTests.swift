import XCTest
@testable import SamplingCore

/// Minute averages for the energy-page process-sum curve. Not `SystemCPUHistory`.
final class EnergyHistoryTests: XCTestCase {
    func testNoRecordedMinuteYieldsNoPoints() {
        XCTAssertEqual(EnergyMachineHistory().points, [])
    }

    func testRealZeroStaysZeroAndANilOnlyMinuteStaysNil() {
        var history = EnergyMachineHistory()
        history.record(processWatts: nil, batteryPercent: nil, at: minute(50) + 15)
        XCTAssertEqual(history.points.count, 240)
        XCTAssertEqual(history.points.last?.minuteStart, minute(50))
        XCTAssertNil(history.points.last?.watts)
        XCTAssertNil(history.points.last?.batteryPercent)

        history.record(processWatts: 0, batteryPercent: 0, at: minute(51))
        XCTAssertEqual(history.points.last?.watts, 0)
        XCTAssertEqual(history.points.last?.batteryPercent, 0)
        XCTAssertNil(history.points[history.points.count - 2].watts)
    }

    func testOpenMinuteAveragesNonNilSamplesAndLeavesTheClosedMinute() {
        var history = EnergyMachineHistory()
        let start = minute(80)
        history.record(processWatts: 2, batteryPercent: nil, at: start + 1)
        history.record(processWatts: 4, batteryPercent: 50, at: start + 20)
        history.record(processWatts: nil, batteryPercent: 70, at: start + 40)
        history.record(processWatts: 0, batteryPercent: nil, at: start + 59)
        XCTAssertEqual(history.points.last?.minuteStart, start)
        XCTAssertEqual(history.points.last?.watts, 2)
        XCTAssertEqual(history.points.last?.batteryPercent, 60)

        history.record(processWatts: 8, batteryPercent: nil, at: start + 60)
        XCTAssertEqual(history.points.last?.minuteStart, minute(81))
        XCTAssertEqual(history.points.last?.watts, 8)
        XCTAssertNil(history.points.last?.batteryPercent)
        let closed = history.points[history.points.count - 2]
        XCTAssertEqual(closed.minuteStart, start)
        XCTAssertEqual(closed.watts, 2)
        XCTAssertEqual(closed.batteryPercent, 60)
    }

    func testUnrecordedMinutesInsideTheSpanStayNil() {
        var history = EnergyMachineHistory()
        history.record(processWatts: 5, batteryPercent: 40, at: minute(10) + 59)
        history.record(processWatts: 7, batteryPercent: nil, at: minute(12))
        let points = history.points
        XCTAssertEqual(points.count, 240)
        let gap = points.first { $0.minuteStart == minute(11) }
        XCTAssertNotNil(gap)
        XCTAssertNil(gap?.watts)
        XCTAssertNil(gap?.batteryPercent)
        XCTAssertEqual(points.last?.minuteStart, minute(12))
        XCTAssertEqual(points.last?.watts, 7)
        let earlier = points.first { $0.minuteStart == minute(10) }
        XCTAssertEqual(earlier?.watts, 5)
        XCTAssertEqual(earlier?.batteryPercent, 40)
    }

    func testPointsCoverExactly240MinutesAndDropTheOlderOne() {
        var history = EnergyMachineHistory()
        history.record(processWatts: 9, batteryPercent: nil, at: minute(1_000))
        history.record(processWatts: 4, batteryPercent: nil, at: minute(1_239))
        XCTAssertEqual(history.points.count, 240)
        XCTAssertEqual(history.points.first?.minuteStart, minute(1_000))
        XCTAssertEqual(history.points.first?.watts, 9)
        XCTAssertEqual(history.points.last?.minuteStart, minute(1_239))
        XCTAssertEqual(history.points.last?.watts, 4)
        XCTAssertNil(history.points[1].watts)

        history.record(processWatts: 3, batteryPercent: nil, at: minute(1_240))
        XCTAssertEqual(history.points.count, 240)
        XCTAssertEqual(history.points.first?.minuteStart, minute(1_001))
        XCTAssertNil(history.points.first?.watts)
        XCTAssertFalse(history.points.contains { $0.minuteStart == minute(1_000) })
        XCTAssertEqual(history.points.last?.minuteStart, minute(1_240))
        XCTAssertEqual(history.points.last?.watts, 3)
        let kept = history.points.first { $0.minuteStart == minute(1_239) }
        XCTAssertEqual(kept?.watts, 4)
    }

    private func minute(_ index: Int) -> Date {
        Date(timeIntervalSince1970: Double(index) * 60)
    }
}
