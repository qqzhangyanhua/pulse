import XCTest
@testable import SamplingCore

/// One hour of per-process GPU time. Missing deltas stay out of the total.
final class GPUTimeMinuteLedgerTests: XCTestCase {
    private let origin = Date(timeIntervalSince1970: 1_700_000_040)

    func testSameMinuteDeltasAccumulateInsteadOfKeepingTheLastOne() throws {
        var ledger = GPUTimeMinuteLedger()
        push(&ledger, nanoseconds: 0, at: 0)
        push(&ledger, nanoseconds: 1_000_000_000, at: 10)
        push(&ledger, nanoseconds: 1_500_000_000, at: 20)

        let entry = try XCTUnwrap(ledger.entries.first)
        XCTAssertEqual(entry.nanoseconds, 1_500_000_000)
        XCTAssertEqual(entry.secondsText, "1.5 秒")
        XCTAssertNotEqual(entry.nanoseconds, 500_000_000)
        XCTAssertNotEqual(entry.secondsText, "0.5 秒")
        XCTAssertFalse(entry.exited)
    }

    func testBucketAtExactlyOneHourStaysAndOneSecondLaterDrops() throws {
        var ledger = GPUTimeMinuteLedger()
        push(&ledger, nanoseconds: 0, at: 0)
        push(&ledger, nanoseconds: 12_300_000_000, at: 10)
        pushMissing(&ledger, at: 3_600)

        let kept = try XCTUnwrap(ledger.entries.first)
        XCTAssertEqual(kept.nanoseconds, 12_300_000_000)
        XCTAssertEqual(kept.secondsText, "12.3 秒")
        XCTAssertNotEqual(kept.secondsText, "0.0 秒")

        pushMissing(&ledger, at: 3_601)
        XCTAssertTrue(ledger.entries.isEmpty)
        XCTAssertNil(ledger.entries.first?.nanoseconds)
        XCTAssertNotEqual(ledger.entries.first?.secondsText, "0.0 秒")
    }

    func testMoreThanSixtyBucketsDropsTheOldest() throws {
        var ledger = GPUTimeMinuteLedger()
        push(&ledger, nanoseconds: 0, at: -10)
        for index in 0...60 {
            push(
                &ledger,
                nanoseconds: UInt64(index + 1) * 1_000_000_000,
                at: TimeInterval(index * 60)
            )
        }

        let entry = try XCTUnwrap(ledger.entries.first)
        XCTAssertEqual(entry.nanoseconds, 60_000_000_000)
        XCTAssertEqual(entry.secondsText, "60.0 秒")
        XCTAssertNotEqual(entry.nanoseconds, 61_000_000_000)
        XCTAssertNotEqual(entry.secondsText, "0.0 秒")
    }

    func testPidReuseWithANewStartTimeDoesNotMergeTheOldTotal() throws {
        var ledger = GPUTimeMinuteLedger()
        push(&ledger, nanoseconds: 0, at: 0, start: 100, name: "Mail")
        push(&ledger, nanoseconds: 5_000_000_000, at: 10, start: 100, name: "Mail")
        pushAbsent(&ledger, at: 15)

        let sealed = try XCTUnwrap(ledger.entries.first)
        XCTAssertEqual(sealed.startTimeSeconds, 100)
        XCTAssertEqual(sealed.nanoseconds, 5_000_000_000)
        XCTAssertTrue(sealed.exited)

        push(&ledger, nanoseconds: 50_000_000_000, at: 20, start: 200, name: "Mail")
        push(&ledger, nanoseconds: 52_000_000_000, at: 30, start: 200, name: "Mail")

        let old = try XCTUnwrap(ledger.entries.first { $0.startTimeSeconds == 100 })
        let restarted = try XCTUnwrap(ledger.entries.first { $0.startTimeSeconds == 200 })
        XCTAssertEqual(old.nanoseconds, 5_000_000_000)
        XCTAssertEqual(old.secondsText, "5.0 秒")
        XCTAssertTrue(old.exited)
        XCTAssertEqual(restarted.nanoseconds, 2_000_000_000)
        XCTAssertEqual(restarted.secondsText, "2.0 秒")
        XCTAssertFalse(restarted.exited)
        XCTAssertNotEqual(restarted.nanoseconds, 57_000_000_000)
        XCTAssertNotEqual(restarted.nanoseconds, 7_000_000_000)
    }

    func testLeavingTheListKeepsTheTotalAndMarksTheProcessExited() throws {
        var ledger = GPUTimeMinuteLedger()
        push(&ledger, nanoseconds: 0, at: 0, name: "Mail")
        push(&ledger, nanoseconds: 12_300_000_000, at: 10, name: "Mail")
        pushAbsent(&ledger, at: 15)

        let exited = try XCTUnwrap(ledger.entries.first)
        XCTAssertEqual(exited.pid, 7)
        XCTAssertEqual(exited.name, "Mail")
        XCTAssertTrue(exited.exited)
        XCTAssertEqual(exited.nanoseconds, 12_300_000_000)
        XCTAssertEqual(exited.secondsText, "12.3 秒")
        XCTAssertNotEqual(exited.nanoseconds, 0)
        XCTAssertNotEqual(exited.secondsText, "0.0 秒")
    }

    func testFirstSampleAndOtherMissingDeltasAreSkippedNotStoredAsZero() throws {
        var ledger = GPUTimeMinuteLedger()
        push(&ledger, nanoseconds: 4_000_000_000, at: 0)
        XCTAssertTrue(ledger.entries.isEmpty)
        XCTAssertNotEqual(ledger.entries.first?.secondsText, "0.0 秒")
        XCTAssertNotEqual(ledger.entries.first?.nanoseconds, 0)

        push(&ledger, nanoseconds: 1_000_000_000, at: 10)
        XCTAssertTrue(ledger.entries.isEmpty)

        var counted = GPUTimeMinuteLedger()
        push(&counted, nanoseconds: 0, at: 0)
        push(&counted, nanoseconds: 2_000_000_000, at: 10)
        push(&counted, nanoseconds: 1_000_000_000, at: 20)
        let rewound = try XCTUnwrap(counted.entries.first)
        XCTAssertEqual(rewound.nanoseconds, 2_000_000_000)
        XCTAssertEqual(rewound.secondsText, "2.0 秒")
        XCTAssertNotEqual(rewound.nanoseconds, 0)
        XCTAssertNotEqual(rewound.secondsText, "0.0 秒")

        push(&counted, nanoseconds: 1_400_000_000, at: 30)
        XCTAssertEqual(counted.entries.first?.nanoseconds, 2_400_000_000)
        XCTAssertNotEqual(counted.entries.first?.nanoseconds, 1_400_000_000)

        var disappeared = GPUTimeMinuteLedger()
        push(&disappeared, clients: [client(id: 1, nanoseconds: 0), client(id: 2, nanoseconds: 0)], at: 0)
        push(&disappeared, clients: [client(id: 1, nanoseconds: 1_000_000_000), client(id: 2, nanoseconds: 1_000_000_000)], at: 10)
        push(&disappeared, clients: [client(id: 1, nanoseconds: 1_500_000_000)], at: 20)
        XCTAssertEqual(disappeared.entries.first?.nanoseconds, 2_000_000_000)
        XCTAssertNotEqual(disappeared.entries.first?.nanoseconds, 500_000_000)
        XCTAssertNotEqual(disappeared.entries.first?.nanoseconds, 0)
        push(&disappeared, clients: [client(id: 1, nanoseconds: 2_500_000_000)], at: 30)
        XCTAssertEqual(disappeared.entries.first?.nanoseconds, 3_000_000_000)

        var unreadable = GPUTimeMinuteLedger()
        push(&unreadable, nanoseconds: 0, at: 0)
        push(&unreadable, nanoseconds: 1_000_000_000, at: 10)
        push(&unreadable, clients: [client(id: 1, nanoseconds: nil)], at: 20)
        XCTAssertEqual(unreadable.entries.first?.nanoseconds, 1_000_000_000)
        XCTAssertNotEqual(unreadable.entries.first?.nanoseconds, 0)
        push(&unreadable, nanoseconds: 3_000_000_000, at: 30)
        XCTAssertEqual(unreadable.entries.first?.nanoseconds, 3_000_000_000)
        XCTAssertNotEqual(unreadable.entries.first?.nanoseconds, 2_000_000_000)

        var added = GPUTimeMinuteLedger()
        push(&added, clients: [client(id: 1, nanoseconds: 0)], at: 0)
        push(&added, clients: [client(id: 1, nanoseconds: 1_000_000_000), client(id: 2, nanoseconds: 9_000_000_000)], at: 10)
        XCTAssertEqual(added.entries.first?.nanoseconds, 1_000_000_000)
        XCTAssertNotEqual(added.entries.first?.nanoseconds, 10_000_000_000)
        XCTAssertNotEqual(added.entries.first?.nanoseconds, 0)
        push(&added, clients: [client(id: 1, nanoseconds: 1_000_000_000), client(id: 2, nanoseconds: 9_500_000_000)], at: 20)
        XCTAssertEqual(added.entries.first?.nanoseconds, 1_500_000_000)
    }

    func testRealZeroDeltaStaysZero() throws {
        var ledger = GPUTimeMinuteLedger()
        push(&ledger, nanoseconds: 5_000_000_000, at: 0)
        push(&ledger, nanoseconds: 5_000_000_000, at: 10)

        let idle = try XCTUnwrap(ledger.entries.first)
        XCTAssertEqual(idle.nanoseconds, 0)
        XCTAssertEqual(idle.secondsText, "0.0 秒")
        XCTAssertNotEqual(idle.secondsText, "—")
        XCTAssertFalse(idle.exited)
    }

    private func client(id: UInt64, nanoseconds: UInt64?) -> GPUShareClientSample {
        GPUShareClientSample(
            id: id,
            pid: 7,
            creatorName: "Mail",
            accumulatedGPUTimeNanoseconds: nanoseconds
        )
    }

    private func push(
        _ ledger: inout GPUTimeMinuteLedger,
        nanoseconds: UInt64,
        at seconds: TimeInterval,
        now: TimeInterval? = nil,
        start: UInt64 = 100,
        name: String = "Mail"
    ) {
        push(
            &ledger,
            clients: [client(id: 1, nanoseconds: nanoseconds)],
            at: seconds,
            now: now,
            start: start,
            name: name
        )
    }

    private func push(
        _ ledger: inout GPUTimeMinuteLedger,
        clients: [GPUShareClientSample],
        at seconds: TimeInterval,
        now: TimeInterval? = nil,
        start: UInt64 = 100,
        name: String = "Mail"
    ) {
        ledger.advance(
            live: [
                GPUTimeLiveSample(
                    pid: 7,
                    startTimeSeconds: start,
                    name: name,
                    clients: clients
                ),
            ],
            at: origin.addingTimeInterval(now ?? seconds),
            listSucceeded: true
        )
    }

    private func pushMissing(
        _ ledger: inout GPUTimeMinuteLedger,
        at seconds: TimeInterval,
        start: UInt64 = 100
    ) {
        ledger.advance(
            live: [
                GPUTimeLiveSample(
                    pid: 7,
                    startTimeSeconds: start,
                    name: "Mail",
                    clients: nil
                ),
            ],
            at: origin.addingTimeInterval(seconds),
            listSucceeded: true
        )
    }

    private func pushAbsent(
        _ ledger: inout GPUTimeMinuteLedger,
        at seconds: TimeInterval
    ) {
        ledger.advance(live: [], at: origin.addingTimeInterval(seconds), listSucceeded: true)
    }
}
