import XCTest
@testable import SamplingCore

/// In-memory public-IP request. Failure keeps no previous address.
final class PublicIPRequestStateTests: XCTestCase {
    private let queriedAt = Date(timeIntervalSince1970: 1_700_000_000)
    private let later = Date(timeIntervalSince1970: 1_700_000_060)

    func testIdleBeginsLoading() {
        XCTAssertEqual(PublicIPRequestState.idle.begin(), .loading)
    }

    func testLoadingSucceedsWithTheAddressAndDate() {
        let state = PublicIPRequestState.loading.succeed(address: "203.0.113.8", at: queriedAt)
        XCTAssertEqual(state, .success(address: "203.0.113.8", queriedAt: queriedAt))
    }

    func testLoadingFails() {
        XCTAssertEqual(PublicIPRequestState.loading.fail(), .failure)
    }

    func testBeginWhileLoadingIsANoOp() {
        XCTAssertEqual(PublicIPRequestState.loading.begin(), .loading)
    }

    func testFailureDropsThePreviousAddress() {
        let shown = PublicIPRequestState.loading.succeed(address: "203.0.113.8", at: queriedAt)
        let failed = shown.fail()
        XCTAssertEqual(failed, .failure)
        guard case .failure = failed else {
            XCTFail("previous address still visible: \(failed)")
            return
        }
    }

    func testRetryFromFailureBeginsLoading() {
        let failed = PublicIPRequestState.success(address: "203.0.113.8", queriedAt: queriedAt).fail()
        XCTAssertEqual(failed.begin(), .loading)
    }

    func testSuccessClickBeginsLoading() {
        let shown = PublicIPRequestState.success(address: "203.0.113.8", queriedAt: queriedAt)
        XCTAssertEqual(shown.begin(), .loading)
    }

    func testSuccessReplacesThePreviousAddress() {
        let first = PublicIPRequestState.loading.succeed(address: "203.0.113.8", at: queriedAt)
        let second = first.succeed(address: "198.51.100.4", at: later)
        XCTAssertEqual(second, .success(address: "198.51.100.4", queriedAt: later))
    }

    func testSuccessAt1430UTCFormatsTheQueriedClock() {
        var calendar = Calendar(identifier: .gregorian)
        let utc = TimeZone(secondsFromGMT: 0)!
        calendar.timeZone = utc
        let date = calendar.date(from: DateComponents(
            timeZone: utc,
            year: 2026,
            month: 11,
            day: 13,
            hour: 14,
            minute: 30
        ))!
        XCTAssertEqual(
            PublicIPRequestState.queriedAtLabel(date, timeZone: utc),
            "查询于 14:30"
        )
    }
}
