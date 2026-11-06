import XCTest
@testable import SamplingCore

final class ThermalNoticeTests: XCTestCase {
    func testOnlySeriousAndCriticalProduceTheNotice() {
        let expected: [(ThermalCondition, String?)] = [
            (.nominal, nil),
            (.fair, nil),
            (.serious, "系统正在降频以控制温度"),
            (.critical, "系统正在降频以控制温度"),
            (.unknown, nil),
        ]
        for (condition, message) in expected {
            XCTAssertEqual(ThermalNotice.message(for: condition), message, "\(condition)")
        }
    }

    func testNoticeCopyAvoidsAlarmWords() {
        let copies = [ThermalCondition.serious, .critical].compactMap {
            ThermalNotice.message(for: $0)
        }
        XCTAssertEqual(copies.count, 2)
        let banned = ["泄漏", "危险", "过热"]
        for copy in copies {
            for word in banned {
                XCTAssertFalse(copy.contains(word), "\(copy) contains \(word)")
            }
        }
    }
}
