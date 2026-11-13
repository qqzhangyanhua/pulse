import XCTest
@testable import SamplingCore

/// Paused-process records. These tests do not send a signal or touch UserDefaults.
final class PausedProcessLedgerTests: XCTestCase {
    func testRecordKeepsPidAndStartTime() {
        var ledger = PausedProcessLedger()
        ledger.record(pid: 42, startTimeSeconds: 1_700_000_000)
        XCTAssertEqual(
            ledger.records,
            [PausedProcessRecord(pid: 42, startTimeSeconds: 1_700_000_000)]
        )
    }

    func testRecordingTheSamePidReplacesTheStartTime() {
        var ledger = PausedProcessLedger()
        ledger.record(pid: 42, startTimeSeconds: 1)
        ledger.record(pid: 42, startTimeSeconds: 2)
        ledger.record(pid: 7, startTimeSeconds: 9)
        XCTAssertEqual(
            ledger.records,
            [
                PausedProcessRecord(pid: 42, startTimeSeconds: 2),
                PausedProcessRecord(pid: 7, startTimeSeconds: 9),
            ]
        )
    }

    func testManualResumeDropsThatRecord() {
        var ledger = PausedProcessLedger()
        ledger.record(pid: 42, startTimeSeconds: 1_700_000_000)
        ledger.record(pid: 7, startTimeSeconds: 99)
        ledger.resume(pid: 42)
        XCTAssertEqual(ledger.records, [PausedProcessRecord(pid: 7, startTimeSeconds: 99)])
    }

    func testClearDropsEveryRecord() {
        var ledger = PausedProcessLedger()
        ledger.record(pid: 42, startTimeSeconds: 1_700_000_000)
        ledger.record(pid: 7, startTimeSeconds: 99)
        ledger.clear()
        XCTAssertTrue(ledger.records.isEmpty)
    }

    func testLaunchReconcileResumesMatchingStartTimeAndDiscardsReusedPid() {
        var ledger = PausedProcessLedger()
        ledger.record(pid: 42, startTimeSeconds: 100)
        ledger.record(pid: 7, startTimeSeconds: 200)
        ledger.record(pid: 9, startTimeSeconds: 300)
        let outcome = ledger.reconcile(live: [
            PausedProcessRecord(pid: 42, startTimeSeconds: 100),
            PausedProcessRecord(pid: 7, startTimeSeconds: 999),
        ])
        XCTAssertEqual(outcome.resume, [PausedProcessRecord(pid: 42, startTimeSeconds: 100)])
        XCTAssertEqual(
            outcome.discarded,
            [
                PausedProcessRecord(pid: 7, startTimeSeconds: 200),
                PausedProcessRecord(pid: 9, startTimeSeconds: 300),
            ]
        )
        XCTAssertTrue(ledger.records.isEmpty)
    }
}
