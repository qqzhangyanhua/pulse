import XCTest
@testable import SamplingCore

/// Pure decode of an `IOPMCopyAssertionsByProcess`-shaped dictionary.
final class SleepAssertionTests: XCTestCase {
    func testSeveralHeldAssertionsSortAndDropInactive() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let raw: [AnyHashable: Any] = [
            20: [
                [
                    "AssertType": "PreventUserIdleSystemSleep",
                    "Process Name": "caffeinate",
                    "AssertStartWhen": now.addingTimeInterval(-90),
                    "AssertLevel": 255,
                ],
                [
                    "AssertType": "PreventUserIdleDisplaySleep",
                    "Process Name": "caffeinate",
                    "AssertStartWhen": now.addingTimeInterval(-5),
                    "AssertLevel": 255,
                ],
                [
                    "AssertType": "PreventUserIdleSystemSleep",
                    "Process Name": "caffeinate",
                    "AssertStartWhen": now.addingTimeInterval(-10),
                    "AssertLevel": 0,
                ],
                [
                    "AssertType": "UserIsActive",
                    "Process Name": "caffeinate",
                    "AssertStartWhen": now.addingTimeInterval(-3),
                    "AssertTimedOutWhen": now,
                ],
            ],
            7: [
                [
                    "AssertType": "PreventSystemSleep",
                    "Process Name": "powerd",
                    "AssertStartWhen": now.addingTimeInterval(-3661),
                    "AssertLevel": 255,
                ],
            ],
        ]

        let rows = SleepAssertionDecoder.rows(from: raw, now: now)

        XCTAssertEqual(rows.map(\.id), ["7#0", "20#0", "20#1"])
        XCTAssertEqual(rows.map(\.pid), [7, 20, 20])
        XCTAssertEqual(rows.map(\.name), ["powerd", "caffeinate", "caffeinate"])
        XCTAssertEqual(rows.map(\.typeText), ["阻止进入睡眠", "阻止显示器睡眠", "阻止系统睡眠"])
        XCTAssertEqual(rows.map(\.durationText), ["1 小时 1 分钟", "5 秒", "1 分钟"])
    }

    func testUnknownTypeStaysARowWithACalmLabel() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let raw: [AnyHashable: Any] = [
            NSNumber(value: 42): [
                [
                    "AssertType": "SomeFutureAssertion",
                    "Process Name": "helper",
                    "AssertStartWhen": now.addingTimeInterval(-1),
                ] as [String: Any],
            ],
        ]

        let rows = SleepAssertionDecoder.rows(from: raw, now: now)

        XCTAssertEqual(rows.map(\.pid), [42])
        XCTAssertEqual(rows.map(\.name), ["helper"])
        XCTAssertEqual(rows.map(\.typeText), ["其它"])
        XCTAssertEqual(rows.map(\.durationText), ["1 秒"])
        XCTAssertEqual(rows.map(\.id), ["42#0"])
    }

    func testMissingFieldsStayMissingAndSkipAKeyThatIsNotAPid() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let raw: [AnyHashable: Any] = [
            9: [
                [
                    "Process Name": "   ",
                    "AssertLevel": 255,
                ] as [String: Any],
            ],
            "not-a-pid": [
                [
                    "AssertType": "PreventSystemSleep",
                    "Process Name": "skipped",
                ] as [String: Any],
            ],
            11: [
                [
                    "AssertType": "PreventUserIdleDisplaySleep",
                    "AssertStartWhen": now.addingTimeInterval(30),
                ] as [String: Any],
            ],
            12: [
                [
                    "AssertType": "NoIdleSleepAssertion",
                    "Process Name": "caffeinate",
                    "AssertStartWhen": now,
                ] as [String: Any],
            ],
        ]

        let rows = SleepAssertionDecoder.rows(from: raw, now: now)

        XCTAssertEqual(rows.map(\.pid), [9, 11, 12])
        XCTAssertEqual(rows.map(\.name), ["—", "—", "caffeinate"])
        XCTAssertEqual(rows.map(\.typeText), ["—", "阻止显示器睡眠", "阻止系统睡眠"])
        XCTAssertEqual(rows.map(\.durationText), ["—", "—", "0 秒"])
    }
}
