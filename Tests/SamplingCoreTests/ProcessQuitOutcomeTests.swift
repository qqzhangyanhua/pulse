import XCTest
@testable import SamplingCore

/// Phase 16 knife 1. Matrix ids are the TECH「测试矩阵」rows.
/// Selection changes are not token cancellation. `identityEvidence` defaults false.
final class ProcessQuitOutcomeTests: XCTestCase {
    // MARK: - Matrix

    /// 1. A failed, select B. B's projection has no A failure. Clicking B does not write A's pid.
    func test01_crossPid_failedA_selectB_clickBDoesNotWriteA() throws {
        var store = ProcessQuitOutcome()
        let rows = [row(pid: 1, name: "A"), row(pid: 2, name: "B")]
        let failure = try fail(pid: 1, rows: rows, store: &store)
        let aBefore = try XCTUnwrap(store.record(for: 1))

        let listSelected: Int32? = 2
        let sidebarSubject: Int32? = 2
        let projected = store.project(
            listSelectedPid: listSelected,
            sidebarSubjectPid: sidebarSubject,
            rows: rows
        )
        XCTAssertEqual(projected.viewState, .none)
        XCTAssertFalse(projected.showsFailureCard)
        XCTAssertFalse(projected.canRetry)
        XCTAssertFalse(projected.showsQuittingSpinner)
        XCTAssertFalse(projected.showsSuccessBanner)
        XCTAssertNil(projected.absentLabel)

        let issued = try XCTUnwrap(store.click(.terminate, selectedPid: listSelected, rows: rows))
        XCTAssertEqual(issued.pid, 2)
        XCTAssertNotEqual(issued.pid, 1)
        XCTAssertEqual(issued.kind, .terminate)
        XCTAssertEqual(try XCTUnwrap(store.record(for: 1)), aBefore)
        XCTAssertEqual(store.record(for: 2)?.pid, 2)
        XCTAssertEqual(store.record(for: 2)?.token, issued.token)
        XCTAssertEqual(listSelected, 2)
        XCTAssertEqual(sidebarSubject, 2)
        XCTAssertNotEqual(failure.token, issued.token)

        let bView = store.project(listSelectedPid: 2, sidebarSubjectPid: 2, rows: rows)
        XCTAssertEqual(bView.viewState, .quitting)
        XCTAssertFalse(bView.showsFailureCard)
        XCTAssertFalse(bView.showsSuccessBanner)
    }

    /// 2. A is in flight. Only the selection moves to B. A's `.exited` / `.notFound` still closes A and writes only A.
    func test02_inflightA_selectB_thenExitedAndNotFoundCloseOnlyA() throws {
        try assertInFlightAThenSelectB(result: .exited)
        try assertInFlightAThenSelectB(result: .notFound)
    }

    /// 3. Repeat click while inRows quitting keeps the token. A later click, including after unconfirmed reappearance, replaces A. B's click does not.
    func test03_repeatInRowsQuittingClickKeepsToken_reappearClickReplaces_oldTokenIgnored() throws {
        var store = ProcessQuitOutcome()
        let pid: Int32 = 7
        let rows = [row(pid: pid, name: "A"), row(pid: 8, name: "B")]
        let first = try XCTUnwrap(store.click(.terminate, selectedPid: pid, rows: rows))
        XCTAssertNil(store.click(.terminate, selectedPid: pid, rows: rows))
        let held = try XCTUnwrap(store.record(for: pid))
        XCTAssertEqual(held.token, first.token)
        XCTAssertEqual(held.phase, .quitting)
        XCTAssertEqual(held.opportunity, .open)
        XCTAssertEqual(held.presence, .inRows)
        XCTAssertEqual(store.trackedCount, 1)

        let other = try XCTUnwrap(store.click(.terminate, selectedPid: 8, rows: rows))
        XCTAssertNotEqual(other.token, first.token)
        XCTAssertEqual(store.record(for: pid)?.token, first.token)
        XCTAssertEqual(store.record(for: 8)?.pid, 8)

        let live = detail(pid: pid, memory: 20, memoryPoints: 2, cpuPoints: 1)
        store.applyPresenceFromRows(ProcessQuitPresenceFrame(rows: [row(pid: 8, name: "B")], detail: live))
        XCTAssertEqual(store.record(for: pid)?.presence, .absentAndUnknown)
        XCTAssertEqual(store.record(for: pid)?.phase, .quitting)
        XCTAssertEqual(store.record(for: pid)?.token, first.token)
        XCTAssertEqual(store.record(for: 8)?.token, other.token)

        store.applyPresenceFromRows(ProcessQuitPresenceFrame(rows: rows))
        let reappeared = try XCTUnwrap(store.record(for: pid))
        XCTAssertEqual(reappeared.presence, .currentReappearedUnconfirmed)
        XCTAssertEqual(reappeared.token, first.token)
        XCTAssertEqual(reappeared.phase, .quitting)
        XCTAssertEqual(reappeared.opportunity, .open)

        let selected: Int32? = pid
        let fresh = try XCTUnwrap(store.click(.terminate, selectedPid: selected, rows: rows))
        XCTAssertNotEqual(fresh.token, first.token)
        XCTAssertEqual(fresh.pid, pid)
        let replaced = try XCTUnwrap(store.record(for: pid))
        XCTAssertEqual(replaced.token, fresh.token)
        XCTAssertEqual(replaced.phase, .quitting)
        XCTAssertEqual(replaced.opportunity, .open)
        XCTAssertEqual(replaced.presence, .inRows)
        XCTAssertEqual(replaced.kind, .terminate)
        XCTAssertNil(replaced.frozenDetail)
        XCTAssertEqual(store.trackedCount, 2)

        store.complete(pid: pid, token: first.token, result: .exited)
        XCTAssertEqual(try XCTUnwrap(store.record(for: pid)), replaced)
        store.complete(pid: pid, token: first.token, result: .notFound)
        XCTAssertEqual(try XCTUnwrap(store.record(for: pid)), replaced)
        XCTAssertEqual(selected, pid)
        XCTAssertEqual(store.record(for: 8)?.token, other.token)
        XCTAssertEqual(store.record(for: 8)?.phase, .quitting)
    }

    /// 4. Failed then absent: phase and opportunity stay, the card is the absent record, the old pid cannot be retried.
    func test04_failedThenAbsent_keepsOpenFailure_absentCard_noOldPidRetry() throws {
        var store = ProcessQuitOutcome()
        let pid: Int32 = 4
        let rows = [row(pid: pid, name: "A", memory: 40)]
        let issued = try fail(pid: pid, rows: rows, store: &store)
        let before = try XCTUnwrap(store.record(for: pid))
        XCTAssertEqual(before.phase, .failed)
        XCTAssertEqual(before.opportunity, .open)
        XCTAssertEqual(before.presence, .inRows)
        let present = store.project(listSelectedPid: pid, sidebarSubjectPid: pid, rows: rows)
        XCTAssertEqual(present.viewState, .failedStillPresent)
        XCTAssertTrue(present.canRetry)
        XCTAssertTrue(present.showsFailureCard)

        let snapshot = detail(pid: pid, name: "A", memory: 40, memoryPoints: 3, cpuPoints: 2)
        store.applyPresenceFromRows(ProcessQuitPresenceFrame(rows: [], detail: snapshot))
        let after = try XCTUnwrap(store.record(for: pid))
        XCTAssertEqual(after.phase, .failed)
        XCTAssertEqual(after.opportunity, .open)
        XCTAssertEqual(after.presence, .absentAndUnknown)
        XCTAssertEqual(after.token, before.token)
        XCTAssertEqual(after.kind, .terminate)
        XCTAssertEqual(after.frozenDetail, snapshot)

        let listSelected: Int32? = nil
        XCTAssertNil(ProcessQuitOutcome.legalListSelection(pid, in: []))
        XCTAssertNil(ProcessSelection.acceptedPid(pid, in: []))
        let card = store.project(listSelectedPid: listSelected, sidebarSubjectPid: pid, rows: [])
        XCTAssertEqual(card.viewState, .absentFromList)
        XCTAssertEqual(card.absentLabel, "已不在列表／上次记录")
        XCTAssertTrue(card.showsAbsentRecord)
        XCTAssertFalse(card.showsQuittingSpinner)
        XCTAssertFalse(card.showsFailureCard)
        XCTAssertFalse(card.canRetry)
        XCTAssertFalse(card.allowsFreshOperation)
        XCTAssertFalse(card.showsSuccessBanner)
        XCTAssertNotEqual(card.viewState, .failedStillPresent)
        XCTAssertNil(store.click(.terminate, selectedPid: pid, rows: []))
        XCTAssertNil(store.click(.requestForce, selectedPid: pid, rows: []))
        XCTAssertEqual(try XCTUnwrap(store.record(for: pid)).token, issued.token)
        XCTAssertEqual(try XCTUnwrap(store.record(for: pid)).phase, .failed)
        XCTAssertNil(listSelected)
    }

    /// 5. Quitting then absent is the absent card. Phase stays quitting and the opportunity stays open.
    func test05_quittingThenAbsent_hidesSpinner_phaseStaysQuitting() throws {
        var store = ProcessQuitOutcome()
        let pid: Int32 = 5
        let rows = [row(pid: pid, name: "A")]
        let issued = try XCTUnwrap(store.click(.terminate, selectedPid: pid, rows: rows))
        let snapshot = detail(pid: pid, memoryPoints: 2, cpuPoints: 2)
        store.applyPresenceFromRows(ProcessQuitPresenceFrame(rows: [], detail: snapshot))
        let record = try XCTUnwrap(store.record(for: pid))
        XCTAssertEqual(record.phase, .quitting)
        XCTAssertEqual(record.opportunity, .open)
        XCTAssertEqual(record.presence, .absentAndUnknown)
        XCTAssertEqual(record.token, issued.token)
        XCTAssertEqual(record.frozenDetail, snapshot)

        let card = store.project(listSelectedPid: nil, sidebarSubjectPid: pid, rows: [])
        XCTAssertEqual(card.viewState, .absentFromList)
        XCTAssertEqual(card.absentLabel, "已不在列表／上次记录")
        XCTAssertFalse(card.showsQuittingSpinner)
        XCTAssertNotEqual(card.viewState, .quitting)
        XCTAssertFalse(card.canRetry)
        XCTAssertFalse(card.showsFailureCard)
        XCTAssertFalse(card.showsSuccessBanner)
        XCTAssertNil(ProcessQuitOutcome.legalListSelection(pid, in: []))
    }

    /// 6. processListFailed, sampling failure, and insufficient freshness do not change phase, presence, or opportunity. Even `rows == []`.
    func test06_listFailedAndSamplingFailedAndStaleFreshness_keepPhase() throws {
        let misleading = detail(pid: 6, memory: 777, memoryPoints: 9, cpuPoints: 9)
        try assertObservationIgnored(
            ProcessQuitPresenceFrame(rows: [], processListFailed: true, detail: misleading),
            label: "processListFailed"
        )
        try assertObservationIgnored(
            ProcessQuitPresenceFrame(
                rows: [row(pid: 60, name: "other")],
                processListFailed: true,
                detail: misleading
            ),
            label: "processListFailed with a different pid"
        )
        try assertObservationIgnored(
            ProcessQuitPresenceFrame(rows: [], samplingFailed: true, detail: misleading),
            label: "samplingFailed"
        )
        try assertObservationIgnored(
            ProcessQuitPresenceFrame(rows: [], freshnessInsufficient: true, detail: misleading),
            label: "freshnessInsufficient"
        )
        try assertObservationIgnored(
            ProcessQuitPresenceFrame(
                rows: [],
                processListFailed: true,
                samplingFailed: true,
                freshnessInsufficient: true,
                detail: misleading
            ),
            label: "all three observation failures"
        )

        var store = ProcessQuitOutcome()
        let pid: Int32 = 6
        let rows = [row(pid: pid, name: "A")]
        _ = try fail(pid: pid, rows: rows, store: &store)
        let phaseBefore = try XCTUnwrap(store.record(for: pid)).phase
        store.applyPresenceFromRows(ProcessQuitPresenceFrame(rows: []))
        let afterRealAbsence = try XCTUnwrap(store.record(for: pid))
        XCTAssertEqual(afterRealAbsence.phase, phaseBefore)
        XCTAssertEqual(afterRealAbsence.phase, .failed)
        XCTAssertEqual(afterRealAbsence.presence, .absentAndUnknown)
        XCTAssertEqual(afterRealAbsence.opportunity, .open)
        let absent = store.project(listSelectedPid: pid, sidebarSubjectPid: pid, rows: [])
        XCTAssertFalse(absent.canRetry)
        XCTAssertNotEqual(absent.viewState, .failedStillPresent)
    }

    /// 7. Same pid returns with no identity evidence: live detail, no old failure card.
    func test07_reappearWithoutEvidence_liveAsNewProcess_hidesFailure() throws {
        var store = ProcessQuitOutcome()
        let pid: Int32 = 7
        let rows = [row(pid: pid, name: "A")]
        let issued = try fail(pid: pid, rows: rows, store: &store)
        store.applyPresenceFromRows(ProcessQuitPresenceFrame(rows: [], detail: detail(pid: pid, memoryPoints: 2, cpuPoints: 1)))
        let frame = ProcessQuitPresenceFrame(rows: rows, detail: detail(pid: pid, memory: 5, memoryPoints: 4, cpuPoints: 4))
        XCTAssertFalse(frame.identityEvidence)
        XCTAssertFalse(ProcessQuitOutcome.productionIdentityEvidence)
        store.applyPresenceFromRows(frame)

        let record = try XCTUnwrap(store.record(for: pid))
        XCTAssertEqual(record.presence, .currentReappearedUnconfirmed)
        XCTAssertEqual(record.phase, .failed)
        XCTAssertEqual(record.opportunity, .open)
        XCTAssertEqual(record.token, issued.token)
        let card = store.project(listSelectedPid: pid, sidebarSubjectPid: pid, rows: rows)
        XCTAssertEqual(card.viewState, .liveAsNewProcess)
        XCTAssertFalse(card.showsFailureCard)
        XCTAssertFalse(card.canRetry)
        XCTAssertFalse(card.showsQuittingSpinner)
        XCTAssertFalse(card.showsAbsentRecord)
        XCTAssertNil(card.absentLabel)
        XCTAssertFalse(card.showsSuccessBanner)
        XCTAssertTrue(card.allowsFreshOperation)
        XCTAssertNotEqual(card.viewState, .failedStillPresent)
    }

    /// 8. Quitting, then the pid returns with no identity evidence: live detail, no spinner and no failure card.
    func test08_quittingReappearWithoutEvidence_noSpinnerOnNewProcess() throws {
        var store = ProcessQuitOutcome()
        let pid: Int32 = 8
        let rows = [row(pid: pid, name: "A")]
        let issued = try XCTUnwrap(store.click(.terminate, selectedPid: pid, rows: rows))
        store.applyPresenceFromRows(ProcessQuitPresenceFrame(rows: []))
        store.applyPresenceFromRows(ProcessQuitPresenceFrame(rows: rows))
        let record = try XCTUnwrap(store.record(for: pid))
        XCTAssertEqual(record.presence, .currentReappearedUnconfirmed)
        XCTAssertEqual(record.phase, .quitting)
        XCTAssertEqual(record.opportunity, .open)
        XCTAssertEqual(record.token, issued.token)
        let card = store.project(listSelectedPid: pid, sidebarSubjectPid: pid, rows: rows)
        XCTAssertEqual(card.viewState, .liveAsNewProcess)
        XCTAssertFalse(card.showsQuittingSpinner)
        XCTAssertFalse(card.showsFailureCard)
        XCTAssertFalse(card.canRetry)
        XCTAssertFalse(card.showsSuccessBanner)
        XCTAssertNotEqual(card.viewState, .quitting)
    }

    /// 8b. Injected identity evidence restores only that pid's failure. It does not take the current selection.
    func test08b_identityEvidenceRestoresThatPidOnly_doesNotStealSelection() throws {
        var store = ProcessQuitOutcome()
        let a: Int32 = 81
        let b: Int32 = 82
        let both = [row(pid: a, name: "A"), row(pid: b, name: "B")]
        let issued = try fail(pid: a, rows: both, store: &store)
        let tokenBeforeEvidence = store.nextToken
        store.applyPresenceFromRows(ProcessQuitPresenceFrame(rows: [row(pid: b, name: "B")]))
        XCTAssertEqual(store.record(for: a)?.presence, .absentAndUnknown)

        var listSelected: Int32? = b
        var sidebarSubject: Int32? = b
        store.applyPresenceFromRows(
            ProcessQuitPresenceFrame(rows: [row(pid: b, name: "B")], identityEvidence: true)
        )
        XCTAssertEqual(store.record(for: a)?.presence, .absentAndUnknown)
        XCTAssertEqual(listSelected, b)

        store.applyPresenceFromRows(
            ProcessQuitPresenceFrame(rows: both, identityEvidence: true, detail: detail(pid: a, memoryPoints: 2, cpuPoints: 1))
        )
        XCTAssertEqual(listSelected, b)
        XCTAssertEqual(sidebarSubject, b)
        XCTAssertEqual(store.nextToken, tokenBeforeEvidence)
        XCTAssertNil(store.record(for: b))
        let restored = try XCTUnwrap(store.record(for: a))
        XCTAssertEqual(restored.presence, .inRows)
        XCTAssertEqual(restored.phase, .failed)
        XCTAssertEqual(restored.opportunity, .open)
        XCTAssertEqual(restored.token, issued.token)
        XCTAssertEqual(restored.pid, a)

        let onB = store.project(listSelectedPid: listSelected, sidebarSubjectPid: sidebarSubject, rows: both)
        XCTAssertEqual(onB.viewState, .none)
        XCTAssertFalse(onB.showsFailureCard)
        XCTAssertFalse(onB.canRetry)
        XCTAssertTrue(onB.allowsFreshOperation)

        let lookingAtAWhileBSelected = store.project(listSelectedPid: b, sidebarSubjectPid: a, rows: both)
        XCTAssertEqual(lookingAtAWhileBSelected.viewState, .failedStillPresent)
        XCTAssertFalse(lookingAtAWhileBSelected.canRetry)
        XCTAssertFalse(lookingAtAWhileBSelected.allowsFreshOperation)

        listSelected = a
        sidebarSubject = a
        let reselected = store.project(listSelectedPid: listSelected, sidebarSubjectPid: sidebarSubject, rows: both)
        XCTAssertEqual(reselected.viewState, .failedStillPresent)
        XCTAssertTrue(reselected.canRetry)
        XCTAssertTrue(reselected.showsFailureCard)
        XCTAssertFalse(reselected.showsSuccessBanner)
        XCTAssertNil(store.record(for: b))
    }

    /// 9. Matching `.exited` / `.notFound` closes the opportunity. Freshness cannot revive it. Reappearance still has no failure card.
    func test09_matchingExitedOrNotFoundCloses_freshnessCannotReviveFailure() throws {
        try assertClosedThenReappear(result: .exited)
        try assertClosedThenReappear(result: .notFound)

        var store = ProcessQuitOutcome()
        let pid: Int32 = 9
        let rows = [row(pid: pid, name: "A")]
        let issued = try fail(pid: pid, rows: rows, store: &store)
        store.complete(pid: pid, token: issued.token, result: .exited)
        let record = try XCTUnwrap(store.record(for: pid))
        XCTAssertEqual(record.phase, .failed)
        XCTAssertEqual(record.opportunity, .closed)
        XCTAssertEqual(record.presence, .inRows)
        let settled = store.project(listSelectedPid: pid, sidebarSubjectPid: pid, rows: rows)
        XCTAssertEqual(settled.viewState, .settledInRows)
        XCTAssertFalse(settled.showsFailureCard)
        XCTAssertFalse(settled.canRetry)
        XCTAssertFalse(settled.showsSuccessBanner)
        XCTAssertNil(settled.absentLabel)
    }

    /// 10. Matching failure stays open. Absent projection cannot retry. The same token is idempotent.
    func test10_matchingFailureStaysOpen_absentCannotRetry_sameTokenIdempotent() throws {
        try assertFailureResult(.stillRunning)
        try assertFailureResult(.requestFailed)

        var store = ProcessQuitOutcome()
        let pid: Int32 = 10
        let rows = [row(pid: pid, name: "A")]
        let issued = try XCTUnwrap(store.click(.terminate, selectedPid: pid, rows: rows))
        store.applyPresenceFromRows(ProcessQuitPresenceFrame(rows: [], detail: detail(pid: pid, memoryPoints: 2, cpuPoints: 1)))
        store.complete(pid: pid, token: issued.token, result: .stillRunning)
        let once = try XCTUnwrap(store.record(for: pid))
        XCTAssertEqual(once.phase, .failed)
        XCTAssertEqual(once.opportunity, .open)
        XCTAssertEqual(once.presence, .absentAndUnknown)
        XCTAssertEqual(once.token, issued.token)
        let absent = store.project(listSelectedPid: nil, sidebarSubjectPid: pid, rows: [])
        XCTAssertEqual(absent.viewState, .absentFromList)
        XCTAssertFalse(absent.canRetry)
        XCTAssertFalse(absent.showsFailureCard)
        XCTAssertFalse(absent.showsSuccessBanner)
        let tokenAfter = store.nextToken
        store.complete(pid: pid, token: issued.token, result: .requestFailed)
        XCTAssertEqual(try XCTUnwrap(store.record(for: pid)), once)
        XCTAssertEqual(store.nextToken, tokenAfter)
        XCTAssertEqual(store.trackedCount, 1)

        // The pid is absent. A rows array that still names it is not a reappearance frame.
        XCTAssertNil(store.click(.terminate, selectedPid: pid, rows: rows))
        XCTAssertNil(store.click(.requestForce, selectedPid: pid, rows: rows))
        XCTAssertEqual(try XCTUnwrap(store.record(for: pid)), once)
        XCTAssertEqual(store.record(for: pid)?.phase, .failed)
        XCTAssertEqual(store.record(for: pid)?.opportunity, .open)
        XCTAssertEqual(store.record(for: pid)?.presence, .absentAndUnknown)
        XCTAssertEqual(store.record(for: pid)?.token, issued.token)
        XCTAssertEqual(store.nextToken, tokenAfter)
        XCTAssertNil(store.pendingForceConfirmation)
        XCTAssertEqual(store.trackedCount, 1)
        let stillAbsent = store.project(listSelectedPid: pid, sidebarSubjectPid: pid, rows: rows)
        XCTAssertEqual(stillAbsent.viewState, .absentFromList)
        XCTAssertFalse(stillAbsent.canRetry)
        XCTAssertFalse(stillAbsent.showsFailureCard)
        XCTAssertFalse(stillAbsent.showsSuccessBanner)
    }

    /// Absence blocks a new quit until a successful reappearance frame. Completion of the current token stays legal.
    func testAbsentRecordRefusesFreshQuitUntilReappearanceFrame() throws {
        try assertInRowsFailedRetryStillOpensOneRecord()
        try assertInRowsQuittingRepeatClickKeepsToken()
        try assertAbsentBlocksFreshTerminate(failedFirst: false)
        try assertAbsentBlocksFreshTerminate(failedFirst: true)
        try assertAbsentBlocksForceRequest()
        try assertAbsentTerminateLeavesPendingForce()
        try assertAbsentCompletionStillSettlesCurrentToken(.stillRunning, phase: .failed, opportunity: .open)
        try assertAbsentCompletionStillSettlesCurrentToken(.requestFailed, phase: .failed, opportunity: .open)
        try assertAbsentCompletionStillSettlesCurrentToken(.exited, phase: .quitting, opportunity: .closed)
        try assertAbsentCompletionStillSettlesCurrentToken(.notFound, phase: .quitting, opportunity: .closed)
        try assertReappearanceThenExplicitClickReplaces()
        try assertForceConfirmWaitsForReappearanceFrame()
    }

    /// 11. Absent + matching `.exited` closes the opportunity without a success banner. Repeat is idempotent. A stale token is dropped.
    func test11_absentExitedClosesWithoutSuccess_repeatIdempotent_staleDropped() throws {
        var store = ProcessQuitOutcome()
        let pid: Int32 = 11
        let rows = [row(pid: pid, name: "A")]
        let issued = try XCTUnwrap(store.click(.terminate, selectedPid: pid, rows: rows))
        store.applyPresenceFromRows(ProcessQuitPresenceFrame(rows: [], detail: detail(pid: pid, memoryPoints: 2, cpuPoints: 2)))
        store.complete(pid: pid, token: issued.token, result: .exited)
        let closed = try XCTUnwrap(store.record(for: pid))
        XCTAssertEqual(closed.opportunity, .closed)
        XCTAssertEqual(closed.presence, .absentAndUnknown)
        XCTAssertEqual(closed.phase, .quitting)
        XCTAssertEqual(closed.token, issued.token)
        let card = store.project(listSelectedPid: nil, sidebarSubjectPid: pid, rows: [])
        XCTAssertEqual(card.viewState, .absentFromList)
        XCTAssertEqual(card.absentLabel, "已不在列表／上次记录")
        XCTAssertNotEqual(card.absentLabel, "已成功")
        XCTAssertFalse(card.absentLabel?.contains("已成功") ?? false)
        XCTAssertFalse(card.showsSuccessBanner)
        XCTAssertFalse(card.showsFailureCard)
        XCTAssertFalse(card.canRetry)
        XCTAssertFalse(card.showsQuittingSpinner)
        store.complete(pid: pid, token: issued.token, result: .exited)
        XCTAssertEqual(try XCTUnwrap(store.record(for: pid)), closed)
        store.complete(pid: pid, token: issued.token, result: .notFound)
        XCTAssertEqual(try XCTUnwrap(store.record(for: pid)), closed)

        var retry = ProcessQuitOutcome()
        let first = try fail(pid: pid, rows: rows, store: &retry)
        let second = try XCTUnwrap(retry.click(.terminate, selectedPid: pid, rows: rows))
        let beforeStale = try XCTUnwrap(retry.record(for: pid))
        retry.complete(pid: pid, token: first.token, result: .exited)
        retry.complete(pid: pid, token: first.token, result: .notFound)
        XCTAssertEqual(try XCTUnwrap(retry.record(for: pid)), beforeStale)
        XCTAssertEqual(beforeStale.token, second.token)
        XCTAssertEqual(beforeStale.opportunity, .open)
        XCTAssertEqual(beforeStale.phase, .quitting)
        XCTAssertNotEqual(first.token, second.token)
    }

    /// 12. Clearing the selection projects none and does not settle the store. Reselect keeps the failure. Closed has no old failure card.
    func test12_clearSelectionKeepsUnsettled_reselectFailure_closedShowsNone() throws {
        var store = ProcessQuitOutcome()
        let pid: Int32 = 12
        let rows = [row(pid: pid, name: "A")]
        _ = try fail(pid: pid, rows: rows, store: &store)
        var listSelected: Int32? = nil
        var sidebarSubject: Int32? = nil
        let cleared = store.project(listSelectedPid: listSelected, sidebarSubjectPid: sidebarSubject, rows: rows)
        XCTAssertEqual(cleared.viewState, .none)
        XCTAssertFalse(cleared.showsFailureCard)
        XCTAssertFalse(cleared.canRetry)
        XCTAssertFalse(cleared.showsSuccessBanner)
        let kept = try XCTUnwrap(store.record(for: pid))
        XCTAssertEqual(kept.phase, .failed)
        XCTAssertEqual(kept.opportunity, .open)
        XCTAssertEqual(kept.presence, .inRows)

        listSelected = pid
        sidebarSubject = pid
        let again = store.project(listSelectedPid: listSelected, sidebarSubjectPid: sidebarSubject, rows: rows)
        XCTAssertEqual(again.viewState, .failedStillPresent)
        XCTAssertTrue(again.canRetry)
        XCTAssertTrue(again.showsFailureCard)

        var left = ProcessQuitOutcome()
        _ = try fail(pid: pid, rows: rows, store: &left)
        store = left
        listSelected = nil
        sidebarSubject = nil
        store.applyPresenceFromRows(ProcessQuitPresenceFrame(rows: []))
        let emptySidebar = store.project(listSelectedPid: listSelected, sidebarSubjectPid: sidebarSubject, rows: [])
        XCTAssertEqual(emptySidebar.viewState, .none)
        let unsettled = try XCTUnwrap(store.record(for: pid))
        XCTAssertEqual(unsettled.phase, .failed)
        XCTAssertEqual(unsettled.opportunity, .open)
        XCTAssertEqual(unsettled.presence, .absentAndUnknown)
        XCTAssertFalse(emptySidebar.showsSuccessBanner)
        XCTAssertNil(ProcessQuitOutcome.legalListSelection(pid, in: []))

        var closed = ProcessQuitOutcome()
        let issued = try XCTUnwrap(closed.click(.terminate, selectedPid: pid, rows: rows))
        closed.complete(pid: pid, token: issued.token, result: .notFound)
        let reselected = closed.project(listSelectedPid: pid, sidebarSubjectPid: pid, rows: rows)
        XCTAssertEqual(reselected.viewState, .settledInRows)
        XCTAssertFalse(reselected.showsFailureCard)
        XCTAssertFalse(reselected.canRetry)
        XCTAssertFalse(reselected.showsAbsentRecord)
        XCTAssertFalse(reselected.showsSuccessBanner)
        closed.applyPresenceFromRows(ProcessQuitPresenceFrame(rows: []))
        closed.applyPresenceFromRows(ProcessQuitPresenceFrame(rows: rows))
        let cameBack = closed.project(listSelectedPid: pid, sidebarSubjectPid: pid, rows: rows)
        XCTAssertEqual(cameBack.viewState, .liveAsNewProcess)
        XCTAssertFalse(cameBack.showsFailureCard)
        XCTAssertFalse(cameBack.canRetry)
        XCTAssertEqual(closed.record(for: pid)?.opportunity, .closed)
        XCTAssertEqual(closed.record(for: pid)?.presence, .currentReappearedUnconfirmed)
    }

    /// 12b. A's in-flight or failure stays on A. B's projection, absence, and click do not change A's token.
    func test12b_crossPid_completionWritesOnlyA_bAbsenceAndClickKeepAToken() throws {
        var store = ProcessQuitOutcome()
        let a: Int32 = 121
        let b: Int32 = 122
        let both = [row(pid: a, name: "A"), row(pid: b, name: "B")]
        let aIssued = try XCTUnwrap(store.click(.terminate, selectedPid: a, rows: both))
        let bIssued = try XCTUnwrap(store.click(.terminate, selectedPid: b, rows: both))
        XCTAssertNotEqual(aIssued.token, bIssued.token)
        XCTAssertEqual(store.record(for: a)?.token, aIssued.token)

        let listSelected: Int32? = b
        let sidebarSubject: Int32? = b
        let bView = store.project(listSelectedPid: listSelected, sidebarSubjectPid: sidebarSubject, rows: both)
        XCTAssertEqual(bView.viewState, .quitting)
        XCTAssertFalse(bView.showsFailureCard)
        let aViewWhileBSelected = store.project(listSelectedPid: b, sidebarSubjectPid: a, rows: both)
        XCTAssertEqual(aViewWhileBSelected.viewState, .quitting)
        XCTAssertFalse(aViewWhileBSelected.showsFailureCard)
        XCTAssertEqual(store.record(for: b)?.pid, b)
        XCTAssertNotEqual(store.record(for: b)?.pid, a)
        XCTAssertNotEqual(store.record(for: a)?.token, store.record(for: b)?.token)

        let bBeforeCompletion = try XCTUnwrap(store.record(for: b))
        store.complete(pid: a, token: aIssued.token, result: .exited)
        let aAfter = try XCTUnwrap(store.record(for: a))
        XCTAssertEqual(aAfter.opportunity, .closed)
        XCTAssertEqual(aAfter.token, aIssued.token)
        XCTAssertEqual(try XCTUnwrap(store.record(for: b)), bBeforeCompletion)
        XCTAssertEqual(listSelected, b)
        XCTAssertEqual(sidebarSubject, b)
        let bAfterA = store.project(listSelectedPid: b, sidebarSubjectPid: b, rows: both)
        XCTAssertEqual(bAfterA, bView)
        XCTAssertEqual(bAfterA.viewState, .quitting)
        XCTAssertEqual(store.record(for: b)?.phase, .quitting)
        XCTAssertEqual(aAfter.phase, .quitting)
        XCTAssertEqual(aAfter.opportunity, .closed)
        XCTAssertEqual(store.record(for: b)?.opportunity, .open)

        let aDetail = detail(pid: a, memory: 3, memoryPoints: 2, cpuPoints: 1)
        store.applyPresenceFromRows(ProcessQuitPresenceFrame(rows: [row(pid: a, name: "A")], detail: aDetail))
        XCTAssertEqual(store.record(for: a)?.token, aIssued.token)
        XCTAssertEqual(store.record(for: a)?.opportunity, .closed)
        XCTAssertEqual(store.record(for: a)?.presence, .inRows)
        let bAbsent = try XCTUnwrap(store.record(for: b))
        XCTAssertEqual(bAbsent.token, bIssued.token)
        XCTAssertEqual(bAbsent.phase, .quitting)
        XCTAssertEqual(bAbsent.presence, .absentAndUnknown)
        XCTAssertNil(bAbsent.frozenDetail)
        XCTAssertEqual(store.record(for: a)?.frozenDetail, nil)

        var failed = ProcessQuitOutcome()
        let aFailed = try fail(pid: a, rows: both, store: &failed)
        let aFailedBefore = try XCTUnwrap(failed.record(for: a))
        let bClick = try XCTUnwrap(failed.click(.terminate, selectedPid: b, rows: both))
        XCTAssertEqual(try XCTUnwrap(failed.record(for: a)), aFailedBefore)
        XCTAssertEqual(failed.record(for: a)?.token, aFailed.token)
        XCTAssertEqual(bClick.pid, b)
        failed.applyPresenceFromRows(ProcessQuitPresenceFrame(rows: [row(pid: a, name: "A")]))
        XCTAssertEqual(failed.record(for: a)?.token, aFailed.token)
        XCTAssertEqual(failed.record(for: a)?.phase, .failed)
        XCTAssertEqual(failed.record(for: a)?.presence, .inRows)
        XCTAssertEqual(failed.record(for: b)?.presence, .absentAndUnknown)
        XCTAssertEqual(failed.record(for: b)?.token, bClick.token)
    }

    /// 13. Force confirmation does not enter quitting until the same legal target is confirmed. Cancel and a stale target keep the old failure.
    func test13_forcePendingCancelAndStaleTarget_doNotEnterQuitting() throws {
        let rows = [row(pid: 1, name: "A"), row(pid: 2, name: "B")]
        var store = ProcessQuitOutcome()
        let failed = try fail(pid: 1, rows: rows, store: &store)
        let before = try XCTUnwrap(store.record(for: 1))
        let tokenClock = store.nextToken
        XCTAssertNil(store.click(.requestForce, selectedPid: 1, rows: rows))
        let pending = try XCTUnwrap(store.pendingForceConfirmation)
        XCTAssertEqual(pending.targetPid, 1)
        let requested = try XCTUnwrap(store.record(for: 1))
        XCTAssertEqual(requested, before)
        XCTAssertEqual(requested.phase, .failed)
        XCTAssertNotEqual(requested.phase, .quitting)
        XCTAssertEqual(store.nextToken, tokenClock)
        let stillFailed = store.project(listSelectedPid: 1, sidebarSubjectPid: 1, rows: rows)
        XCTAssertEqual(stillFailed.viewState, .failedStillPresent)
        XCTAssertNotEqual(stillFailed.viewState, .quitting)
        XCTAssertTrue(stillFailed.canRetry)

        XCTAssertNil(store.click(.requestForce, selectedPid: 1, rows: rows))
        XCTAssertEqual(store.pendingForceConfirmation, pending)
        XCTAssertNil(store.click(.cancelForce(generation: pending.generation &+ 1), selectedPid: 1, rows: rows))
        XCTAssertEqual(store.pendingForceConfirmation, pending)
        XCTAssertNil(store.click(.confirmForce(generation: pending.generation &+ 9), selectedPid: 1, rows: rows))
        XCTAssertEqual(store.pendingForceConfirmation, pending)
        XCTAssertEqual(try XCTUnwrap(store.record(for: 1)).phase, .failed)

        XCTAssertNil(store.click(.cancelForce(generation: pending.generation), selectedPid: 1, rows: rows))
        XCTAssertNil(store.pendingForceConfirmation)
        XCTAssertEqual(try XCTUnwrap(store.record(for: 1)), before)
        XCTAssertEqual(store.nextToken, tokenClock)
        XCTAssertTrue(store.project(listSelectedPid: 1, sidebarSubjectPid: 1, rows: rows).canRetry)
        XCTAssertNotEqual(store.record(for: 1)?.phase, .quitting)

        XCTAssertNil(store.click(.requestForce, selectedPid: 1, rows: rows))
        let confirmGeneration = try XCTUnwrap(store.pendingForceConfirmation).generation
        let issued = try XCTUnwrap(
            store.click(.confirmForce(generation: confirmGeneration), selectedPid: 1, rows: rows)
        )
        XCTAssertEqual(issued.pid, 1)
        XCTAssertEqual(issued.kind, .forceTerminate)
        XCTAssertNotEqual(issued.token, failed.token)
        XCTAssertNil(store.pendingForceConfirmation)
        let quitting = try XCTUnwrap(store.record(for: 1))
        XCTAssertEqual(quitting.phase, .quitting)
        XCTAssertEqual(quitting.kind, .forceTerminate)
        XCTAssertEqual(quitting.opportunity, .open)
        XCTAssertEqual(quitting.presence, .inRows)
        XCTAssertEqual(quitting.token, issued.token)
        XCTAssertNil(store.record(for: 2))
        XCTAssertNil(store.click(.requestForce, selectedPid: 1, rows: rows))
        XCTAssertNil(store.pendingForceConfirmation)
        XCTAssertEqual(store.record(for: 1)?.token, issued.token)

        store.complete(pid: 1, token: failed.token, result: .stillRunning)
        store.complete(pid: 1, token: failed.token, result: .exited)
        XCTAssertEqual(try XCTUnwrap(store.record(for: 1)), quitting)
        store.complete(pid: 1, token: issued.token, result: .stillRunning)
        let forceFailed = try XCTUnwrap(store.record(for: 1))
        XCTAssertEqual(forceFailed.phase, .failed)
        XCTAssertEqual(forceFailed.opportunity, .open)
        XCTAssertEqual(forceFailed.kind, .forceTerminate)
        XCTAssertEqual(forceFailed.token, issued.token)
        XCTAssertTrue(store.project(listSelectedPid: 1, sidebarSubjectPid: 1, rows: rows).canRetry)

        var moved = ProcessQuitOutcome()
        let old = try fail(pid: 1, rows: rows, store: &moved)
        XCTAssertNil(moved.click(.requestForce, selectedPid: 1, rows: rows))
        let generation = try XCTUnwrap(moved.pendingForceConfirmation).generation
        let selected: Int32? = 2
        XCTAssertNil(moved.click(.confirmForce(generation: generation), selectedPid: selected, rows: rows))
        XCTAssertNil(moved.record(for: 2))
        XCTAssertEqual(moved.record(for: 1)?.phase, .failed)
        XCTAssertEqual(moved.record(for: 1)?.token, old.token)
        XCTAssertNotEqual(moved.record(for: 1)?.phase, .quitting)
        XCTAssertEqual(selected, 2)
        XCTAssertNil(moved.pendingForceConfirmation)

        var missing = ProcessQuitOutcome()
        let missingToken = try fail(pid: 1, rows: rows, store: &missing)
        XCTAssertNil(missing.click(.requestForce, selectedPid: 1, rows: rows))
        let missingGeneration = try XCTUnwrap(missing.pendingForceConfirmation).generation
        XCTAssertNil(
            missing.click(
                .confirmForce(generation: missingGeneration),
                selectedPid: 1,
                rows: [row(pid: 2, name: "B")]
            )
        )
        XCTAssertEqual(missing.record(for: 1)?.phase, .failed)
        XCTAssertEqual(missing.record(for: 1)?.token, missingToken.token)
        XCTAssertNil(missing.record(for: 2))
        XCTAssertNotEqual(missing.record(for: 1)?.phase, .quitting)

        var superseded = ProcessQuitOutcome()
        _ = try fail(pid: 1, rows: rows, store: &superseded)
        XCTAssertNil(superseded.click(.requestForce, selectedPid: 1, rows: rows))
        let staleGeneration = try XCTUnwrap(superseded.pendingForceConfirmation).generation
        let ordinary = try XCTUnwrap(superseded.click(.terminate, selectedPid: 1, rows: rows))
        XCTAssertEqual(ordinary.kind, .terminate)
        XCTAssertNil(
            superseded.click(.confirmForce(generation: staleGeneration), selectedPid: 1, rows: rows)
        )
        let afterSupersede = try XCTUnwrap(superseded.record(for: 1))
        XCTAssertEqual(afterSupersede.token, ordinary.token)
        XCTAssertEqual(afterSupersede.kind, .terminate)
        XCTAssertEqual(afterSupersede.phase, .quitting)
        XCTAssertEqual(superseded.trackedCount, 1)

        var busy = ProcessQuitOutcome()
        let busyIssued = try XCTUnwrap(busy.click(.terminate, selectedPid: 1, rows: rows))
        XCTAssertNil(busy.click(.requestForce, selectedPid: 1, rows: rows))
        XCTAssertNil(busy.pendingForceConfirmation)
        XCTAssertEqual(busy.record(for: 1)?.token, busyIssued.token)
        XCTAssertNil(busy.click(.terminate, selectedPid: 1, rows: rows))
        XCTAssertEqual(busy.trackedCount, 1)
    }

    /// 14. The first absence copies the whole detail. Later frames do not add points. The frozen row stays the original value.
    func test14_firstAbsenceFreezesDetail_laterFramesDoNotAddPoints() throws {
        var store = ProcessQuitOutcome()
        let pid: Int32 = 14
        let rows = [row(pid: pid, name: "A", memory: 111)]
        _ = try fail(pid: pid, rows: rows, store: &store)
        XCTAssertNil(store.record(for: pid)?.frozenDetail)

        let original = detail(pid: pid, name: "A", memory: 111, memoryPoints: 4, cpuPoints: 3)
        var live = original
        store.applyPresenceFromRows(ProcessQuitPresenceFrame(rows: [], detail: live))
        live = detail(pid: pid, name: "A", memory: 999, memoryPoints: 8, cpuPoints: 7)
        let frozen = try XCTUnwrap(store.record(for: pid)?.frozenDetail)
        XCTAssertEqual(frozen, original)
        XCTAssertEqual(frozen.memorySeries.count, original.memorySeries.count)
        XCTAssertEqual(frozen.cpuSeries.count, original.cpuSeries.count)
        XCTAssertEqual(frozen.memorySeries, original.memorySeries)
        XCTAssertEqual(frozen.cpuSeries, original.cpuSeries)
        XCTAssertEqual(frozen.row, original.row)
        XCTAssertEqual(frozen.row.memoryBytes, 111)
        XCTAssertLessThanOrEqual(frozen.memorySeries.count, original.memorySeries.count)
        XCTAssertFalse(frozen.memorySeries.count > original.memorySeries.count)

        store.applyPresenceFromRows(ProcessQuitPresenceFrame(rows: [], detail: live))
        let still = try XCTUnwrap(store.record(for: pid)?.frozenDetail)
        XCTAssertEqual(still, original)
        XCTAssertEqual(still.memorySeries.count, original.memorySeries.count)
        XCTAssertEqual(still.cpuSeries.count, original.cpuSeries.count)
        XCTAssertEqual(still.memorySeries, original.memorySeries)
        XCTAssertEqual(still.cpuSeries, original.cpuSeries)
        XCTAssertLessThan(still.memorySeries.count, live.memorySeries.count)
        XCTAssertLessThan(still.cpuSeries.count, live.cpuSeries.count)
        XCTAssertLessThanOrEqual(still.memorySeries.count, original.memorySeries.count)
        XCTAssertEqual(still.row.memoryBytes, original.row.memoryBytes)
        XCTAssertNotEqual(still.row.memoryBytes, live.row.memoryBytes)
        XCTAssertEqual(still.row.pid, pid)
        XCTAssertEqual(still.row.name, original.row.name)
        XCTAssertNotEqual(still.row, live.row)

        let someoneElse = detail(pid: 99, name: "Z", memory: 5, memoryPoints: 6, cpuPoints: 6)
        store.applyPresenceFromRows(ProcessQuitPresenceFrame(rows: [], detail: someoneElse))
        let owned = try XCTUnwrap(store.record(for: pid)?.frozenDetail)
        XCTAssertEqual(owned, original)
        XCTAssertEqual(owned.row.pid, pid)
        XCTAssertNotEqual(owned.row.pid, someoneElse.row.pid)
        XCTAssertEqual(owned.memorySeries.count, 4)
        XCTAssertEqual(store.record(for: pid)?.phase, .failed)
        XCTAssertEqual(store.record(for: pid)?.opportunity, .open)
    }

    /// 15. New state names do not use the banned wording.
    func test15_stateNamesOmitBannedWords() {
        let names = ProcessQuitViewState.allCasesForTest.map(viewStateName)
            + [
                phaseName(.quitting),
                phaseName(.failed),
                presenceName(.inRows),
                presenceName(.absentAndUnknown),
                presenceName(.currentReappearedUnconfirmed),
                opportunityName(.open),
                opportunityName(.closed),
                kindName(.terminate),
                kindName(.forceTerminate),
                ProcessQuitOutcomeCopy.absentRecordLabel,
            ]
        let banned = ["泄漏", "leak", "危险", "危急"]
        for name in names {
            for word in banned {
                XCTAssertFalse(
                    name.lowercased().contains(word.lowercased()),
                    "\(name) contains \(word)"
                )
            }
            XCTAssertFalse(name.lowercased().contains("success"))
        }
        XCTAssertEqual(ProcessQuitOutcomeCopy.absentRecordLabel, "已不在列表／上次记录")
        XCTAssertFalse(ProcessQuitOutcomeCopy.absentRecordLabel.contains("已成功"))
    }

    /// 16. Phase and presence stay orthogonal. One phase value cannot stand in for absence.
    func test16_orthogonalPhaseAndPresence_counterexamples() throws {
        var quittingAbsent = ProcessQuitOutcome()
        let pid: Int32 = 16
        let rows = [row(pid: pid, name: "A"), row(pid: 17, name: "B")]
        let inflight = try XCTUnwrap(quittingAbsent.click(.terminate, selectedPid: pid, rows: rows))
        quittingAbsent.applyPresenceFromRows(ProcessQuitPresenceFrame(rows: [row(pid: 17, name: "B")]))
        let counter1 = try XCTUnwrap(quittingAbsent.record(for: pid))
        XCTAssertEqual(counter1.phase, .quitting)
        XCTAssertEqual(counter1.presence, .absentAndUnknown)
        XCTAssertEqual(counter1.token, inflight.token)
        let counter1View = quittingAbsent.project(listSelectedPid: nil, sidebarSubjectPid: pid, rows: [row(pid: 17, name: "B")])
        XCTAssertEqual(counter1View.viewState, .absentFromList)
        XCTAssertNotEqual(counter1View.viewState, .quitting)
        quittingAbsent.complete(pid: pid, token: inflight.token, result: .exited)
        XCTAssertEqual(quittingAbsent.record(for: pid)?.opportunity, .closed)
        XCTAssertEqual(quittingAbsent.record(for: pid)?.phase, .quitting)
        XCTAssertEqual(quittingAbsent.record(for: pid)?.presence, .absentAndUnknown)

        var failedAbsent = ProcessQuitOutcome()
        _ = try fail(pid: pid, rows: rows, store: &failedAbsent)
        failedAbsent.applyPresenceFromRows(ProcessQuitPresenceFrame(rows: [row(pid: 17, name: "B")]))
        let counter2 = try XCTUnwrap(failedAbsent.record(for: pid))
        XCTAssertEqual(counter2.phase, .failed)
        XCTAssertEqual(counter2.opportunity, .open)
        XCTAssertEqual(counter2.presence, .absentAndUnknown)
        XCTAssertEqual(
            failedAbsent.project(listSelectedPid: nil, sidebarSubjectPid: pid, rows: []).viewState,
            .absentFromList
        )

        failedAbsent.applyPresenceFromRows(ProcessQuitPresenceFrame(rows: rows))
        let counter3 = try XCTUnwrap(failedAbsent.record(for: pid))
        XCTAssertEqual(counter3.phase, .failed)
        XCTAssertEqual(counter3.presence, .currentReappearedUnconfirmed)
        XCTAssertEqual(counter3.opportunity, .open)
        XCTAssertEqual(
            failedAbsent.project(listSelectedPid: pid, sidebarSubjectPid: pid, rows: rows).viewState,
            .liveAsNewProcess
        )

        var failedFrame = ProcessQuitOutcome()
        _ = try fail(pid: pid, rows: rows, store: &failedFrame)
        let beforeFrame = try XCTUnwrap(failedFrame.record(for: pid))
        failedFrame.applyPresenceFromRows(
            ProcessQuitPresenceFrame(rows: [], processListFailed: true)
        )
        let counter4 = try XCTUnwrap(failedFrame.record(for: pid))
        XCTAssertEqual(counter4.phase, beforeFrame.phase)
        XCTAssertEqual(counter4.presence, .inRows)
        XCTAssertEqual(counter4.opportunity, .open)
        XCTAssertEqual(counter4, beforeFrame)

        var switched = ProcessQuitOutcome()
        let bIssued = try fail(pid: 17, rows: rows, store: &switched)
        let aIssued = try XCTUnwrap(switched.click(.terminate, selectedPid: pid, rows: rows))
        let listSelected: Int32? = 17
        let sidebarSubject: Int32? = 17
        let bBefore = try XCTUnwrap(switched.record(for: 17))
        let bViewBefore = switched.project(listSelectedPid: listSelected, sidebarSubjectPid: sidebarSubject, rows: rows)
        switched.complete(pid: pid, token: aIssued.token, result: .notFound)
        XCTAssertEqual(switched.record(for: pid)?.opportunity, .closed)
        XCTAssertEqual(switched.record(for: pid)?.token, aIssued.token)
        XCTAssertEqual(try XCTUnwrap(switched.record(for: 17)), bBefore)
        XCTAssertEqual(switched.record(for: 17)?.token, bIssued.token)
        XCTAssertEqual(listSelected, 17)
        XCTAssertEqual(sidebarSubject, 17)
        XCTAssertEqual(
            switched.project(listSelectedPid: listSelected, sidebarSubjectPid: sidebarSubject, rows: rows),
            bViewBefore
        )
        XCTAssertEqual(bViewBefore.viewState, .failedStillPresent)
    }

    func testProjectionPriority_liveAbsentSettledFailedQuittingNone() throws {
        var store = ProcessQuitOutcome()
        let pid: Int32 = 30
        let rows = [row(pid: pid, name: "A")]
        let issued = try fail(pid: pid, rows: rows, store: &store)
        XCTAssertEqual(
            store.project(listSelectedPid: pid, sidebarSubjectPid: pid, rows: rows).viewState,
            .failedStillPresent
        )
        store.applyPresenceFromRows(ProcessQuitPresenceFrame(rows: []))
        XCTAssertEqual(
            store.project(listSelectedPid: nil, sidebarSubjectPid: pid, rows: []).viewState,
            .absentFromList
        )
        store.applyPresenceFromRows(ProcessQuitPresenceFrame(rows: rows))
        XCTAssertEqual(
            store.project(listSelectedPid: pid, sidebarSubjectPid: pid, rows: rows).viewState,
            .liveAsNewProcess
        )
        XCTAssertEqual(
            store.project(listSelectedPid: nil, sidebarSubjectPid: nil, rows: rows).viewState,
            .none
        )

        var closedAbsent = ProcessQuitOutcome()
        let quitting = try XCTUnwrap(closedAbsent.click(.terminate, selectedPid: pid, rows: rows))
        closedAbsent.complete(pid: pid, token: quitting.token, result: .exited)
        closedAbsent.applyPresenceFromRows(ProcessQuitPresenceFrame(rows: []))
        XCTAssertEqual(closedAbsent.record(for: pid)?.opportunity, .closed)
        XCTAssertEqual(
            closedAbsent.project(listSelectedPid: nil, sidebarSubjectPid: pid, rows: []).viewState,
            .absentFromList
        )
        XCTAssertNotEqual(
            closedAbsent.project(listSelectedPid: nil, sidebarSubjectPid: pid, rows: []).viewState,
            .settledInRows
        )

        var spinning = ProcessQuitOutcome()
        _ = try XCTUnwrap(spinning.click(.terminate, selectedPid: pid, rows: rows))
        XCTAssertEqual(
            spinning.project(listSelectedPid: pid, sidebarSubjectPid: pid, rows: rows).viewState,
            .quitting
        )
        XCTAssertTrue(spinning.project(listSelectedPid: pid, sidebarSubjectPid: pid, rows: rows).showsQuittingSpinner)
        XCTAssertFalse(spinning.project(listSelectedPid: pid, sidebarSubjectPid: pid, rows: rows).canRetry)

        _ = issued
        XCTAssertEqual(
            store.project(listSelectedPid: pid, sidebarSubjectPid: 99, rows: rows).viewState,
            .none
        )
    }

    func testIllegalOrMissingSelection_doesNotIssueOrProjectAcross() throws {
        var store = ProcessQuitOutcome()
        let rows = [row(pid: 1, name: "A"), row(pid: 2, name: "B")]
        XCTAssertNil(store.click(.terminate, selectedPid: nil, rows: rows))
        XCTAssertNil(store.click(.terminate, selectedPid: 99, rows: rows))
        XCTAssertNil(store.click(.requestForce, selectedPid: nil, rows: rows))
        XCTAssertNil(store.pendingForceConfirmation)
        XCTAssertNil(ProcessQuitOutcome.legalListSelection(99, in: rows))
        XCTAssertNil(ProcessSelection.acceptedPid(99, in: rows))
        XCTAssertEqual(store.trackedCount, 0)

        _ = try fail(pid: 1, rows: rows, store: &store)
        let cleared = store.project(listSelectedPid: nil, sidebarSubjectPid: nil, rows: rows)
        XCTAssertEqual(cleared.viewState, .none)
        XCTAssertFalse(cleared.showsFailureCard)
        XCTAssertEqual(store.record(for: 1)?.phase, .failed)
        XCTAssertEqual(store.record(for: 1)?.opportunity, .open)

        let missingRows = [row(pid: 2, name: "B")]
        let ghost = store.project(listSelectedPid: 99, sidebarSubjectPid: 99, rows: missingRows)
        XCTAssertEqual(ghost.viewState, .none)
        XCTAssertFalse(ghost.showsFailureCard)
        XCTAssertFalse(ghost.canRetry)
        XCTAssertNil(ProcessQuitOutcome.legalListSelection(99, in: missingRows))
        XCTAssertNil(store.record(for: 99))

        let aWhileMissing = store.project(listSelectedPid: 99, sidebarSubjectPid: 1, rows: missingRows)
        XCTAssertEqual(aWhileMissing.viewState, .failedStillPresent)
        XCTAssertFalse(aWhileMissing.canRetry)
        XCTAssertFalse(aWhileMissing.allowsFreshOperation)
        XCTAssertEqual(store.record(for: 1)?.pid, 1)
    }

    func testOneRecordPerPid_tokensIncreaseGlobally() throws {
        var store = ProcessQuitOutcome()
        let rows = [row(pid: 1, name: "A"), row(pid: 2, name: "B")]
        let first = try XCTUnwrap(store.click(.terminate, selectedPid: 1, rows: rows))
        XCTAssertEqual(first.token, 1)
        store.complete(pid: 1, token: first.token, result: .requestFailed)
        let second = try XCTUnwrap(store.click(.terminate, selectedPid: 1, rows: rows))
        XCTAssertEqual(second.token, 2)
        XCTAssertEqual(store.trackedCount, 1)
        XCTAssertEqual(store.record(for: 1)?.token, 2)
        let third = try XCTUnwrap(store.click(.terminate, selectedPid: 2, rows: rows))
        XCTAssertEqual(third.token, 3)
        XCTAssertEqual(store.nextToken, 4)
        XCTAssertEqual(store.trackedCount, 2)
        XCTAssertEqual(store.record(for: 1)?.token, 2)
        XCTAssertEqual(store.record(for: 2)?.token, 3)
    }

    func testProductionIdentityEvidenceDefaultsFalse() throws {
        let frame = ProcessQuitPresenceFrame(rows: [row(pid: 1, name: "A")])
        XCTAssertFalse(frame.identityEvidence)
        XCTAssertFalse(ProcessQuitOutcome.productionIdentityEvidence)
        XCTAssertEqual(frame.identityEvidence, ProcessQuitOutcome.productionIdentityEvidence)

        var store = ProcessQuitOutcome()
        let rows = [row(pid: 1, name: "A")]
        _ = try fail(pid: 1, rows: rows, store: &store)
        store.applyPresenceFromRows(ProcessQuitPresenceFrame(rows: []))
        store.applyPresenceFromRows(ProcessQuitPresenceFrame(rows: rows))
        XCTAssertEqual(store.record(for: 1)?.presence, .currentReappearedUnconfirmed)
        XCTAssertEqual(
            store.project(listSelectedPid: 1, sidebarSubjectPid: 1, rows: rows).viewState,
            .liveAsNewProcess
        )
    }

    // MARK: - Scenarios

    private func assertInFlightAThenSelectB(result: ProcessActionResult) throws {
        var store = ProcessQuitOutcome()
        let rows = [row(pid: 1, name: "A"), row(pid: 2, name: "B")]
        let bIssued = try fail(pid: 2, rows: rows, store: &store)
        let aIssued = try XCTUnwrap(store.click(.terminate, selectedPid: 1, rows: rows))
        let listSelected: Int32? = 2
        let sidebarSubject: Int32? = 2
        let aBefore = try XCTUnwrap(store.record(for: 1))
        let bBefore = try XCTUnwrap(store.record(for: 2))
        let bProjectionBefore = store.project(
            listSelectedPid: listSelected,
            sidebarSubjectPid: sidebarSubject,
            rows: rows
        )
        XCTAssertEqual(aBefore.token, aIssued.token)
        XCTAssertEqual(aBefore.phase, .quitting)
        XCTAssertEqual(aBefore.opportunity, .open)
        XCTAssertEqual(aBefore.presence, .inRows)
        XCTAssertEqual(bBefore.token, bIssued.token)
        XCTAssertEqual(bBefore.phase, .failed)
        XCTAssertEqual(bProjectionBefore.viewState, .failedStillPresent)
        XCTAssertTrue(bProjectionBefore.canRetry)
        XCTAssertFalse(bProjectionBefore.showsSuccessBanner)

        store.complete(pid: aIssued.pid, token: aIssued.token, result: result)

        let aAfter = try XCTUnwrap(store.record(for: 1))
        let bAfter = try XCTUnwrap(store.record(for: 2))
        XCTAssertEqual(aAfter.token, aIssued.token)
        XCTAssertEqual(aAfter.opportunity, .closed)
        XCTAssertEqual(aAfter.phase, .quitting)
        XCTAssertEqual(aAfter.presence, .inRows)
        XCTAssertEqual(aAfter.pid, 1)
        XCTAssertEqual(bAfter, bBefore)
        XCTAssertEqual(listSelected, 2)
        XCTAssertEqual(sidebarSubject, 2)
        let bProjectionAfter = store.project(
            listSelectedPid: listSelected,
            sidebarSubjectPid: sidebarSubject,
            rows: rows
        )
        XCTAssertEqual(bProjectionAfter, bProjectionBefore)
        XCTAssertEqual(bProjectionAfter.viewState, .failedStillPresent)
        XCTAssertFalse(bProjectionAfter.showsSuccessBanner)
        let aProjection = store.project(listSelectedPid: listSelected, sidebarSubjectPid: 1, rows: rows)
        XCTAssertEqual(aProjection.viewState, .settledInRows)
        XCTAssertFalse(aProjection.showsFailureCard)
        XCTAssertFalse(aProjection.canRetry)
        XCTAssertFalse(aProjection.showsSuccessBanner)
    }

    private func assertObservationIgnored(_ frame: ProcessQuitPresenceFrame, label: String) throws {
        var store = ProcessQuitOutcome()
        let pid: Int32 = 6
        let rows = [row(pid: pid, name: "A")]
        _ = try fail(pid: pid, rows: rows, store: &store)
        let before = try XCTUnwrap(store.record(for: pid))
        let beforeView = store.project(listSelectedPid: pid, sidebarSubjectPid: pid, rows: rows)
        XCTAssertEqual(before.phase, .failed, label)
        XCTAssertTrue(beforeView.canRetry, label)
        XCTAssertEqual(beforeView.viewState, .failedStillPresent, label)
        store.applyPresenceFromRows(frame)
        let after = try XCTUnwrap(store.record(for: pid))
        XCTAssertEqual(after, before, label)
        XCTAssertEqual(after.phase, before.phase, label)
        XCTAssertEqual(after.phase, .failed, label)
        XCTAssertEqual(after.presence, .inRows, label)
        XCTAssertEqual(after.opportunity, .open, label)
        XCTAssertNil(after.frozenDetail, label)
        let afterView = store.project(listSelectedPid: pid, sidebarSubjectPid: pid, rows: rows)
        XCTAssertEqual(afterView, beforeView, label)
        XCTAssertTrue(afterView.canRetry, label)
        XCTAssertEqual(afterView.viewState, .failedStillPresent, label)
        XCTAssertFalse(afterView.showsSuccessBanner, label)
        let emptyRowsView = store.project(listSelectedPid: pid, sidebarSubjectPid: pid, rows: [])
        XCTAssertEqual(emptyRowsView.viewState, .failedStillPresent, label)
        XCTAssertNotEqual(emptyRowsView.viewState, .absentFromList, label)
        XCTAssertFalse(emptyRowsView.showsSuccessBanner, label)
        XCTAssertFalse(emptyRowsView.canRetry, label)
    }

    private func assertClosedThenReappear(result: ProcessActionResult) throws {
        var store = ProcessQuitOutcome()
        let pid: Int32 = 9
        let rows = [row(pid: pid, name: "A")]
        let issued = try XCTUnwrap(store.click(.terminate, selectedPid: pid, rows: rows))
        store.complete(pid: pid, token: issued.token, result: result)
        let closed = try XCTUnwrap(store.record(for: pid))
        XCTAssertEqual(closed.opportunity, .closed)
        XCTAssertEqual(closed.phase, .quitting)
        XCTAssertEqual(closed.presence, .inRows)
        let settled = store.project(listSelectedPid: pid, sidebarSubjectPid: pid, rows: rows)
        XCTAssertEqual(settled.viewState, .settledInRows)
        XCTAssertFalse(settled.showsFailureCard)
        XCTAssertFalse(settled.canRetry)
        XCTAssertFalse(settled.showsSuccessBanner)
        XCTAssertFalse(settled.showsAbsentRecord)
        XCTAssertNil(settled.absentLabel)

        let clock = store.nextToken
        store.applyPresenceFromRows(ProcessQuitPresenceFrame(rows: [], freshnessInsufficient: true))
        XCTAssertEqual(try XCTUnwrap(store.record(for: pid)), closed)
        XCTAssertEqual(store.nextToken, clock)
        let stillSettled = store.project(listSelectedPid: pid, sidebarSubjectPid: pid, rows: rows)
        XCTAssertEqual(stillSettled, settled)
        XCTAssertFalse(stillSettled.canRetry)
        XCTAssertNotEqual(store.record(for: pid)?.phase, .failed)

        store.applyPresenceFromRows(ProcessQuitPresenceFrame(rows: []))
        XCTAssertEqual(store.record(for: pid)?.opportunity, .closed)
        XCTAssertEqual(store.record(for: pid)?.phase, .quitting)
        XCTAssertEqual(store.record(for: pid)?.presence, .absentAndUnknown)
        let absent = store.project(listSelectedPid: nil, sidebarSubjectPid: pid, rows: [])
        XCTAssertEqual(absent.viewState, .absentFromList)
        XCTAssertFalse(absent.showsFailureCard)
        XCTAssertFalse(absent.showsSuccessBanner)
        XCTAssertFalse(absent.canRetry)

        store.applyPresenceFromRows(ProcessQuitPresenceFrame(rows: [], freshnessInsufficient: true))
        XCTAssertEqual(store.record(for: pid)?.opportunity, .closed)
        XCTAssertNotEqual(store.record(for: pid)?.phase, .failed)

        store.applyPresenceFromRows(ProcessQuitPresenceFrame(rows: rows))
        XCTAssertEqual(store.record(for: pid)?.presence, .currentReappearedUnconfirmed)
        XCTAssertEqual(store.record(for: pid)?.opportunity, .closed)
        let live = store.project(listSelectedPid: pid, sidebarSubjectPid: pid, rows: rows)
        XCTAssertEqual(live.viewState, .liveAsNewProcess)
        XCTAssertFalse(live.showsFailureCard)
        XCTAssertFalse(live.canRetry)
        XCTAssertFalse(live.showsSuccessBanner)
    }

    private func assertFailureResult(_ result: ProcessActionResult) throws {
        var store = ProcessQuitOutcome()
        let pid: Int32 = 10
        let rows = [row(pid: pid, name: "A")]
        let issued = try XCTUnwrap(store.click(.terminate, selectedPid: pid, rows: rows))
        let clock = store.nextToken
        store.complete(pid: pid, token: issued.token, result: result)
        let failed = try XCTUnwrap(store.record(for: pid))
        XCTAssertEqual(failed.phase, .failed)
        XCTAssertEqual(failed.opportunity, .open)
        XCTAssertEqual(failed.presence, .inRows)
        XCTAssertEqual(failed.token, issued.token)
        XCTAssertEqual(failed.kind, .terminate)
        let card = store.project(listSelectedPid: pid, sidebarSubjectPid: pid, rows: rows)
        XCTAssertEqual(card.viewState, .failedStillPresent)
        XCTAssertTrue(card.canRetry)
        XCTAssertTrue(card.showsFailureCard)
        XCTAssertFalse(card.showsSuccessBanner)
        store.complete(pid: pid, token: issued.token, result: result)
        XCTAssertEqual(try XCTUnwrap(store.record(for: pid)), failed)
        XCTAssertEqual(store.nextToken, clock)
        XCTAssertEqual(store.trackedCount, 1)

        store.applyPresenceFromRows(ProcessQuitPresenceFrame(rows: [], detail: detail(pid: pid, memoryPoints: 1, cpuPoints: 1)))
        let absentRecord = try XCTUnwrap(store.record(for: pid))
        XCTAssertEqual(absentRecord.phase, .failed)
        XCTAssertEqual(absentRecord.opportunity, .open)
        XCTAssertEqual(absentRecord.presence, .absentAndUnknown)
        let absent = store.project(listSelectedPid: nil, sidebarSubjectPid: pid, rows: [])
        XCTAssertEqual(absent.viewState, .absentFromList)
        XCTAssertFalse(absent.canRetry)
        XCTAssertFalse(absent.showsFailureCard)
        XCTAssertTrue(card.canRetry)
        XCTAssertNotEqual(card.canRetry, absent.canRetry)
        store.complete(pid: pid, token: issued.token, result: result)
        XCTAssertEqual(store.record(for: pid)?.phase, .failed)
        XCTAssertEqual(store.record(for: pid)?.opportunity, .open)
        XCTAssertEqual(store.record(for: pid)?.token, issued.token)
        XCTAssertEqual(store.record(for: pid)?.presence, .absentAndUnknown)
    }

    private func assertInRowsFailedRetryStillOpensOneRecord() throws {
        var store = ProcessQuitOutcome()
        let pid: Int32 = 41
        let rows = [row(pid: pid, name: "A")]
        let first = try fail(pid: pid, rows: rows, store: &store)
        let second = try XCTUnwrap(store.click(.terminate, selectedPid: pid, rows: rows))
        XCTAssertNotEqual(second.token, first.token)
        XCTAssertEqual(second.pid, pid)
        store.complete(pid: pid, token: second.token, result: .requestFailed)
        let again = try XCTUnwrap(store.record(for: pid))
        XCTAssertEqual(again.phase, .failed)
        XCTAssertEqual(again.opportunity, .open)
        XCTAssertEqual(again.presence, .inRows)
        XCTAssertEqual(again.token, second.token)
        XCTAssertEqual(store.trackedCount, 1)
        let card = store.project(listSelectedPid: pid, sidebarSubjectPid: pid, rows: rows)
        XCTAssertEqual(card.viewState, .failedStillPresent)
        XCTAssertTrue(card.canRetry)
    }

    private func assertInRowsQuittingRepeatClickKeepsToken() throws {
        var store = ProcessQuitOutcome()
        let pid: Int32 = 42
        let rows = [row(pid: pid, name: "A")]
        let issued = try XCTUnwrap(store.click(.terminate, selectedPid: pid, rows: rows))
        XCTAssertNil(store.click(.terminate, selectedPid: pid, rows: rows))
        XCTAssertNil(store.click(.requestForce, selectedPid: pid, rows: rows))
        let record = try XCTUnwrap(store.record(for: pid))
        XCTAssertEqual(record.token, issued.token)
        XCTAssertEqual(record.phase, .quitting)
        XCTAssertEqual(record.opportunity, .open)
        XCTAssertEqual(record.presence, .inRows)
        XCTAssertEqual(store.nextToken, issued.token &+ 1)
        XCTAssertNil(store.pendingForceConfirmation)
        XCTAssertEqual(store.trackedCount, 1)
    }

    private func assertAbsentBlocksFreshTerminate(failedFirst: Bool) throws {
        var store = ProcessQuitOutcome()
        let pid: Int32 = failedFirst ? 43 : 44
        let rows = [row(pid: pid, name: "A")]
        let issued = try XCTUnwrap(store.click(.terminate, selectedPid: pid, rows: rows))
        if failedFirst {
            store.complete(pid: pid, token: issued.token, result: .stillRunning)
        }
        store.applyPresenceFromRows(
            ProcessQuitPresenceFrame(rows: [], detail: detail(pid: pid, memoryPoints: 2, cpuPoints: 1))
        )
        let before = try XCTUnwrap(store.record(for: pid))
        let clock = store.nextToken
        XCTAssertEqual(before.presence, .absentAndUnknown)
        XCTAssertEqual(before.opportunity, .open)
        XCTAssertEqual(before.token, issued.token)
        XCTAssertEqual(before.phase, failedFirst ? .failed : .quitting)
        XCTAssertNil(store.click(.terminate, selectedPid: pid, rows: rows))
        XCTAssertEqual(try XCTUnwrap(store.record(for: pid)), before)
        XCTAssertEqual(store.nextToken, clock)
        XCTAssertNil(store.pendingForceConfirmation)
        XCTAssertEqual(store.trackedCount, 1)
        let card = store.project(listSelectedPid: pid, sidebarSubjectPid: pid, rows: rows)
        XCTAssertEqual(card.viewState, .absentFromList)
        XCTAssertFalse(card.canRetry)
        XCTAssertFalse(card.showsQuittingSpinner)
        XCTAssertFalse(card.showsFailureCard)
    }

    private func assertAbsentBlocksForceRequest() throws {
        var store = ProcessQuitOutcome()
        let pid: Int32 = 45
        let rows = [row(pid: pid, name: "A")]
        let issued = try fail(pid: pid, rows: rows, store: &store)
        store.applyPresenceFromRows(ProcessQuitPresenceFrame(rows: []))
        let before = try XCTUnwrap(store.record(for: pid))
        let clock = store.nextToken
        XCTAssertNil(store.click(.requestForce, selectedPid: pid, rows: rows))
        XCTAssertNil(store.pendingForceConfirmation)
        XCTAssertEqual(try XCTUnwrap(store.record(for: pid)), before)
        XCTAssertEqual(store.record(for: pid)?.phase, .failed)
        XCTAssertEqual(store.record(for: pid)?.opportunity, .open)
        XCTAssertEqual(store.record(for: pid)?.presence, .absentAndUnknown)
        XCTAssertEqual(store.record(for: pid)?.token, issued.token)
        XCTAssertEqual(store.nextToken, clock)
    }

    private func assertAbsentTerminateLeavesPendingForce() throws {
        var store = ProcessQuitOutcome()
        let pid: Int32 = 49
        let rows = [row(pid: pid, name: "A")]
        let failed = try fail(pid: pid, rows: rows, store: &store)
        XCTAssertNil(store.click(.requestForce, selectedPid: pid, rows: rows))
        let pending = try XCTUnwrap(store.pendingForceConfirmation)
        store.applyPresenceFromRows(ProcessQuitPresenceFrame(rows: []))
        let before = try XCTUnwrap(store.record(for: pid))
        let clock = store.nextToken
        XCTAssertEqual(before.presence, .absentAndUnknown)
        XCTAssertEqual(before.token, failed.token)
        XCTAssertNil(store.click(.terminate, selectedPid: pid, rows: rows))
        XCTAssertEqual(store.pendingForceConfirmation, pending)
        XCTAssertEqual(try XCTUnwrap(store.record(for: pid)), before)
        XCTAssertEqual(store.nextToken, clock)
        XCTAssertEqual(store.record(for: pid)?.phase, .failed)
        XCTAssertEqual(store.record(for: pid)?.opportunity, .open)
    }

    private func assertAbsentCompletionStillSettlesCurrentToken(
        _ result: ProcessActionResult,
        phase: ProcessQuitPhase,
        opportunity: ProcessQuitOpportunity
    ) throws {
        var store = ProcessQuitOutcome()
        let pid: Int32 = 46
        let rows = [row(pid: pid, name: "A")]
        let issued = try XCTUnwrap(store.click(.terminate, selectedPid: pid, rows: rows))
        store.applyPresenceFromRows(ProcessQuitPresenceFrame(rows: []))
        let clock = store.nextToken
        store.complete(pid: pid, token: issued.token, result: result)
        let after = try XCTUnwrap(store.record(for: pid))
        XCTAssertEqual(after.pid, pid)
        XCTAssertEqual(after.token, issued.token)
        XCTAssertEqual(after.kind, .terminate)
        XCTAssertEqual(after.phase, phase)
        XCTAssertEqual(after.opportunity, opportunity)
        XCTAssertEqual(after.presence, .absentAndUnknown)
        XCTAssertEqual(store.nextToken, clock)
        XCTAssertEqual(store.trackedCount, 1)
        XCTAssertNil(store.pendingForceConfirmation)
        let card = store.project(listSelectedPid: nil, sidebarSubjectPid: pid, rows: [])
        XCTAssertEqual(card.viewState, .absentFromList)
        XCTAssertFalse(card.showsSuccessBanner)
        XCTAssertFalse(card.canRetry)
        if opportunity == .open && phase == .failed {
            XCTAssertFalse(card.showsFailureCard)
        }
        if phase == .quitting {
            XCTAssertFalse(card.showsQuittingSpinner)
        }
    }

    private func assertReappearanceThenExplicitClickReplaces() throws {
        var store = ProcessQuitOutcome()
        let pid: Int32 = 47
        let rows = [row(pid: pid, name: "A")]
        let issued = try fail(pid: pid, rows: rows, store: &store)
        store.applyPresenceFromRows(ProcessQuitPresenceFrame(rows: []))
        let absent = try XCTUnwrap(store.record(for: pid))
        XCTAssertEqual(absent.presence, .absentAndUnknown)
        XCTAssertEqual(absent.phase, .failed)
        XCTAssertEqual(absent.opportunity, .open)
        XCTAssertEqual(absent.token, issued.token)

        let frame = ProcessQuitPresenceFrame(rows: rows)
        XCTAssertFalse(frame.identityEvidence)
        store.applyPresenceFromRows(frame)
        let reappeared = try XCTUnwrap(store.record(for: pid))
        XCTAssertEqual(reappeared.presence, .currentReappearedUnconfirmed)
        XCTAssertEqual(reappeared.phase, .failed)
        XCTAssertEqual(reappeared.opportunity, .open)
        XCTAssertEqual(reappeared.token, issued.token)
        XCTAssertEqual(
            store.project(listSelectedPid: pid, sidebarSubjectPid: pid, rows: rows).viewState,
            .liveAsNewProcess
        )

        let fresh = try XCTUnwrap(store.click(.terminate, selectedPid: pid, rows: rows))
        XCTAssertNotEqual(fresh.token, issued.token)
        XCTAssertEqual(fresh.pid, pid)
        XCTAssertEqual(fresh.kind, .terminate)
        let replaced = try XCTUnwrap(store.record(for: pid))
        XCTAssertEqual(replaced.token, fresh.token)
        XCTAssertEqual(replaced.phase, .quitting)
        XCTAssertEqual(replaced.opportunity, .open)
        XCTAssertEqual(replaced.presence, .inRows)
        XCTAssertEqual(store.trackedCount, 1)
        store.complete(pid: pid, token: issued.token, result: .exited)
        store.complete(pid: pid, token: issued.token, result: .stillRunning)
        XCTAssertEqual(try XCTUnwrap(store.record(for: pid)), replaced)
    }

    private func assertForceConfirmWaitsForReappearanceFrame() throws {
        var store = ProcessQuitOutcome()
        let pid: Int32 = 48
        let rows = [row(pid: pid, name: "A")]
        let failed = try fail(pid: pid, rows: rows, store: &store)
        XCTAssertNil(store.click(.requestForce, selectedPid: pid, rows: rows))
        let pending = try XCTUnwrap(store.pendingForceConfirmation)
        XCTAssertEqual(pending.targetPid, pid)
        XCTAssertEqual(store.record(for: pid)?.phase, .failed)
        XCTAssertEqual(store.nextToken, failed.token &+ 1)

        store.applyPresenceFromRows(ProcessQuitPresenceFrame(rows: []))
        let absent = try XCTUnwrap(store.record(for: pid))
        XCTAssertEqual(absent.presence, .absentAndUnknown)
        XCTAssertEqual(absent.phase, .failed)
        XCTAssertEqual(absent.opportunity, .open)
        XCTAssertEqual(absent.token, failed.token)
        let clock = store.nextToken

        XCTAssertNil(
            store.click(.confirmForce(generation: pending.generation), selectedPid: pid, rows: rows)
        )
        XCTAssertEqual(store.pendingForceConfirmation, pending)
        XCTAssertEqual(try XCTUnwrap(store.record(for: pid)), absent)
        XCTAssertEqual(store.nextToken, clock)
        XCTAssertEqual(store.trackedCount, 1)

        store.applyPresenceFromRows(ProcessQuitPresenceFrame(rows: rows))
        let waiting = try XCTUnwrap(store.record(for: pid))
        XCTAssertEqual(waiting.presence, .currentReappearedUnconfirmed)
        XCTAssertEqual(waiting.phase, .failed)
        XCTAssertEqual(waiting.opportunity, .open)
        XCTAssertEqual(waiting.token, failed.token)
        XCTAssertEqual(store.pendingForceConfirmation, pending)
        XCTAssertEqual(store.nextToken, clock)

        let issued = try XCTUnwrap(
            store.click(.confirmForce(generation: pending.generation), selectedPid: pid, rows: rows)
        )
        XCTAssertEqual(issued.pid, pid)
        XCTAssertEqual(issued.kind, .forceTerminate)
        XCTAssertNotEqual(issued.token, failed.token)
        XCTAssertNil(store.pendingForceConfirmation)
        let restarted = try XCTUnwrap(store.record(for: pid))
        XCTAssertEqual(restarted.token, issued.token)
        XCTAssertEqual(restarted.kind, .forceTerminate)
        XCTAssertEqual(restarted.phase, .quitting)
        XCTAssertEqual(restarted.opportunity, .open)
        XCTAssertEqual(restarted.presence, .inRows)
        XCTAssertEqual(store.trackedCount, 1)
        store.complete(pid: pid, token: failed.token, result: .exited)
        XCTAssertEqual(try XCTUnwrap(store.record(for: pid)), restarted)
    }

    @discardableResult
    private func fail(
        pid: Int32,
        rows: [ProcessRow],
        store: inout ProcessQuitOutcome
    ) throws -> ProcessQuitIssued {
        let issued = try XCTUnwrap(store.click(.terminate, selectedPid: pid, rows: rows))
        store.complete(pid: pid, token: issued.token, result: .stillRunning)
        return issued
    }

    private func row(pid: Int32, name: String, memory: UInt64 = 1_000) -> ProcessRow {
        ProcessRow(
            pid: pid,
            name: name,
            bundleIdentifier: nil,
            executablePath: nil,
            cpuPercent: 1,
            memoryBytes: memory,
            threadCount: 2
        )
    }

    private func detail(
        pid: Int32,
        name: String = "proc",
        memory: UInt64 = 1_000,
        memoryPoints: Int = 1,
        cpuPoints: Int = 1
    ) -> ProcessDetail {
        ProcessDetail(
            row: row(pid: pid, name: name, memory: memory),
            memorySeries: series(count: memoryPoints, valueBase: 10),
            cpuSeries: series(count: cpuPoints, valueBase: 80)
        )
    }

    private func series(count: Int, valueBase: Double) -> [ChartSample] {
        guard count > 0 else { return [] }
        return (0..<count).map { index in
            ChartSample(
                id: UInt64(index + 1),
                date: Date(timeIntervalSince1970: TimeInterval(index)),
                value: valueBase + Double(index)
            )
        }
    }

    private func viewStateName(_ state: ProcessQuitViewState) -> String {
        switch state {
        case .liveAsNewProcess: return "liveAsNewProcess"
        case .absentFromList: return "absentFromList"
        case .settledInRows: return "settledInRows"
        case .failedStillPresent: return "failedStillPresent"
        case .quitting: return "quitting"
        case .none: return "none"
        }
    }

    private func phaseName(_ phase: ProcessQuitPhase) -> String {
        switch phase {
        case .quitting: return "quitting"
        case .failed: return "failed"
        }
    }

    private func presenceName(_ presence: ProcessQuitPresence) -> String {
        switch presence {
        case .inRows: return "inRows"
        case .absentAndUnknown: return "absentAndUnknown"
        case .currentReappearedUnconfirmed: return "currentReappearedUnconfirmed"
        }
    }

    private func opportunityName(_ opportunity: ProcessQuitOpportunity) -> String {
        switch opportunity {
        case .open: return "open"
        case .closed: return "closed"
        }
    }

    private func kindName(_ kind: ProcessQuitKind) -> String {
        switch kind {
        case .terminate: return "terminate"
        case .forceTerminate: return "forceTerminate"
        }
    }
}

private extension ProcessQuitViewState {
    static var allCasesForTest: [ProcessQuitViewState] {
        [.liveAsNewProcess, .absentFromList, .settledInRows, .failedStillPresent, .quitting, .none]
    }
}
