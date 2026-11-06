import XCTest
@testable import SamplingCore

/// Phase 13 step 2: Darwin-free retry apply / sleep-wait / empty chrome.
/// VM writeback uses these same functions. No Sampler, no Views.
final class SamplingRetryApplyTests: XCTestCase {
    func testManualRetryDoesNotClearFailurePhase() {
        var gate = SamplingRequestGate()
        let held = SamplingRetryApply.Held(
            loadState: .failed,
            samplingFailed: true,
            processListFailed: false,
            hasSnapshot: false
        )
        gate.requestManualRetry()
        XCTAssertTrue(gate.retrying)
        let next = SamplingRetryApply.afterManualRetry(held)
        XCTAssertEqual(next, held)
        XCTAssertEqual(next.loadState, .failed)
        XCTAssertNotEqual(next.loadState, .sampling)
        XCTAssertTrue(next.samplingFailed)
        XCTAssertFalse(next.hasSnapshot)
    }

    func testProcessListFailureStaysReadyOnRetryClick() {
        let held = SamplingRetryApply.Held(
            loadState: .ready,
            samplingFailed: true,
            processListFailed: true,
            hasSnapshot: true
        )
        let next = SamplingRetryApply.afterManualRetry(held)
        XCTAssertEqual(next.loadState, .ready)
        XCTAssertTrue(next.processListFailed)
        XCTAssertTrue(next.hasSnapshot)
        XCTAssertTrue(next.samplingFailed)
    }

    func testJoinAcceptsCurrentFlightOnceAndIgnoresStale() {
        var gate = SamplingRequestGate()
        var clock = SamplingClock()
        let step = SamplingPace.step(isForeground: true)
        let started = gate.plan(clock: &clock, step: step)
        XCTAssertTrue(started.sample)
        let flight = tryUnwrap(started.flight)

        gate.requestManualRetry()
        XCTAssertTrue(gate.retrying)
        XCTAssertFalse(gate.plan(clock: &clock, step: step).sample)

        var held = SamplingRetryApply.Held(
            loadState: .failed,
            samplingFailed: true,
            processListFailed: false,
            hasSnapshot: false
        )
        XCTAssertNil(
            SamplingRetryApply.apply(held, accepted: false, sampleSucceeded: true),
            "stale / cancelled must not write"
        )
        XCTAssertEqual(held.loadState, .failed)

        XCTAssertFalse(gate.accept(SamplingFlight(id: flight.id &+ 7)))
        XCTAssertTrue(gate.accept(flight))
        XCTAssertFalse(gate.retrying)

        let applied = tryUnwrap(
            SamplingRetryApply.apply(held, accepted: true, sampleSucceeded: true)
        )
        XCTAssertEqual(applied.loadState, .ready)
        XCTAssertFalse(applied.samplingFailed)
        XCTAssertTrue(applied.hasSnapshot)
        XCTAssertFalse(gate.accept(flight), "one apply per flight")
    }

    func testAcceptFailureWithoutSnapshotStaysFailed() {
        let held = SamplingRetryApply.Held(
            loadState: .failed,
            samplingFailed: true,
            processListFailed: false,
            hasSnapshot: false
        )
        let applied = tryUnwrap(
            SamplingRetryApply.apply(held, accepted: true, sampleSucceeded: false)
        )
        XCTAssertEqual(applied.loadState, .failed)
        XCTAssertTrue(applied.samplingFailed)
        XCTAssertFalse(applied.hasSnapshot)
        XCTAssertFalse(applied.processListFailed)
    }

    func testAcceptFailureWithSnapshotKeepsReady() {
        let held = SamplingRetryApply.Held(
            loadState: .ready,
            samplingFailed: false,
            processListFailed: false,
            hasSnapshot: true
        )
        let applied = tryUnwrap(
            SamplingRetryApply.apply(held, accepted: true, sampleSucceeded: false)
        )
        XCTAssertEqual(applied.loadState, .ready)
        XCTAssertTrue(applied.samplingFailed)
        XCTAssertTrue(applied.hasSnapshot)
    }

    func testCancelledSleepDoesNotRecordPlannedSlice() {
        XCTAssertNil(
            SamplingSleepWait.recordableNanoseconds(
                planned: 400_000_000,
                consumed: 12_000_000,
                completed: false,
                loopCancelled: true
            )
        )
        XCTAssertEqual(
            SamplingSleepWait.recordableNanoseconds(
                planned: 400_000_000,
                consumed: 12_000_000,
                completed: false,
                loopCancelled: false
            ),
            12_000_000
        )
        XCTAssertEqual(
            SamplingSleepWait.recordableNanoseconds(
                planned: 400_000_000,
                consumed: 12_000_000,
                completed: true,
                loopCancelled: false
            ),
            400_000_000
        )
        XCTAssertNotEqual(
            SamplingSleepWait.recordableNanoseconds(
                planned: 400_000_000,
                consumed: 0,
                completed: false,
                loopCancelled: false
            ),
            400_000_000,
            "interrupted wait must not record the leftover planned slice"
        )
    }

    func testEmptyChromeIsOneSource() {
        let idle = SamplingRetryEmptyChrome(retrying: false)
        XCTAssertEqual(idle.buttonTitle, "重试")
        XCTAssertTrue(idle.isButtonEnabled)
        XCTAssertNil(idle.pendingMessage)

        let pending = SamplingRetryEmptyChrome(retrying: true)
        XCTAssertEqual(pending.buttonTitle, "重试")
        XCTAssertFalse(pending.isButtonEnabled)
        XCTAssertEqual(pending.pendingMessage, "正在重试…")
    }

    private func tryUnwrap<T>(_ value: T?, file: StaticString = #filePath, line: UInt = #line) -> T {
        guard let value else {
            XCTFail("expected non-nil", file: file, line: line)
            fatalError("expected non-nil")
        }
        return value
    }
}
