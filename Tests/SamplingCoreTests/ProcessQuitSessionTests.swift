import XCTest
@testable import SamplingCore

/// Phase 16 knife 2. Joint sidebar projection over the one `ProcessQuitOutcome` store.
/// Darwin-free. No view, no `ProcessActions`, no sampler instance.
final class ProcessQuitSessionTests: XCTestCase {
    func testLegacyFailureSentencesStayTheExistingCopy() {
        XCTAssertEqual(
            ProcessQuitSessionCopy.terminateFailed,
            "未能退出。可以请系统立即结束该进程。"
        )
        XCTAssertEqual(ProcessQuitSessionCopy.forceFailed, "系统未能结束该进程。")
        XCTAssertNotEqual(ProcessQuitSessionCopy.terminateFailed, "上次退出未成功，可重试。")
        XCTAssertNotEqual(ProcessQuitSessionCopy.forceFailed, "上次强制退出未成功，可重试。")
        XCTAssertFalse(ProcessQuitSessionCopy.terminateFailed.contains("重试退出"))
        XCTAssertFalse(ProcessQuitSessionCopy.forceFailed.contains("重试强制退出"))
    }

    func testInRowsFailureProjectsThatPidOnly() throws {
        var store = ProcessQuitOutcome()
        let rows = [row(1, "A", memory: 40), row(2, "B", memory: 80)]
        let issued = try fail(1, rows: rows, store: &store)
        let live = detail(1, "A", memory: 40, memoryPoints: 3, cpuPoints: 2)
        let side = project(store, list: 1, subject: 1, rows: rows, live: live)

        XCTAssertEqual(side.viewState, .failedStillPresent)
        XCTAssertEqual(side.quitPhase, .failed)
        XCTAssertEqual(side.quitMessage, ProcessQuitSessionCopy.terminateFailed)
        XCTAssertTrue(side.showsFailureCard)
        XCTAssertTrue(side.buttonsEnabled)
        XCTAssertEqual(side.actionPid, 1)
        XCTAssertFalse(side.frozen)
        XCTAssertFalse(side.showsQuittingSpinner)
        XCTAssertFalse(side.showsAbsentRecord)
        XCTAssertNil(side.absentLabel)
        XCTAssertFalse(side.showsSuccessBanner)
        XCTAssertEqual(side.detail, live)
        XCTAssertTrue(side.showsLiveTrend)
        XCTAssertEqual(store.record(for: 1)?.token, issued.token)

        let other = project(store, list: 2, subject: 2, rows: rows, live: detail(2, "B", memory: 80))
        XCTAssertEqual(other.viewState, .none)
        XCTAssertNil(other.quitMessage)
        XCTAssertFalse(other.showsFailureCard)
        XCTAssertEqual(other.detail?.row.pid, 2)
        XCTAssertNotEqual(other.detail?.row.pid, 1)
        XCTAssertEqual(other.actionPid, 2)
        XCTAssertEqual(store.record(for: 1)?.phase, .failed)
    }

    func testDismissKeepsFailureAndReselectShowsItWhileBDoesNot() throws {
        var store = ProcessQuitOutcome()
        let rows = [row(1, "A"), row(2, "B")]
        _ = try fail(1, rows: rows, store: &store)
        let before = try XCTUnwrap(store.record(for: 1))
        let dismissed = ProcessQuitSession.dismissSidebar()
        XCTAssertNil(dismissed.listSelectedPid)
        XCTAssertNil(dismissed.sidebarSubjectPid)
        XCTAssertEqual(try XCTUnwrap(store.record(for: 1)), before)
        XCTAssertEqual(before.opportunity, .open)
        XCTAssertNotEqual(before.phase, .quitting)

        let hidden = project(store, list: nil, subject: nil, rows: rows, live: nil)
        XCTAssertEqual(hidden.viewState, .none)
        XCTAssertNil(hidden.quitMessage)
        XCTAssertNil(hidden.detail)

        let again = project(store, list: 1, subject: 1, rows: rows, live: nil)
        XCTAssertEqual(again.viewState, .failedStillPresent)
        XCTAssertEqual(again.quitMessage, ProcessQuitSessionCopy.terminateFailed)
        XCTAssertEqual(again.detail?.row.pid, 1)
        XCTAssertTrue(again.buttonsEnabled)

        let bee = project(store, list: 2, subject: 2, rows: rows, live: detail(2, "B"))
        XCTAssertNil(bee.quitMessage)
        XCTAssertEqual(bee.detail?.row.pid, 2)
        XCTAssertFalse(bee.showsFailureCard)
    }

    func testFollowListSelectionDoesNotWriteTheStoreOrSampleAVanishedPid() throws {
        var store = ProcessQuitOutcome()
        let rows = [row(1, "A"), row(2, "B")]
        let issued = try fail(1, rows: rows, store: &store)
        let before = try XCTUnwrap(store.record(for: 1))
        let moved = ProcessQuitSession.followListSelection(
            listSelectedPid: 2,
            sidebarSubjectPid: 1,
            rows: rows
        )
        XCTAssertEqual(moved.listSelectedPid, 2)
        XCTAssertEqual(moved.sidebarSubjectPid, 2)
        XCTAssertEqual(try XCTUnwrap(store.record(for: 1)), before)
        XCTAssertNil(store.record(for: 2))

        let vanished = ProcessQuitSession.followListSelection(
            listSelectedPid: 9,
            sidebarSubjectPid: 1,
            rows: rows
        )
        XCTAssertNil(vanished.listSelectedPid)
        XCTAssertEqual(vanished.sidebarSubjectPid, 1)
        XCTAssertNotEqual(vanished.listSelectedPid, 9)
        XCTAssertEqual(store.record(for: 1)?.token, issued.token)
    }

    func testNilListSelectionDoesNotClearSidebarSubject() throws {
        let rows = [row(1, "A")]
        let kept = ProcessQuitSession.followListSelection(
            listSelectedPid: nil,
            sidebarSubjectPid: 1,
            rows: rows
        )
        XCTAssertNil(kept.listSelectedPid)
        XCTAssertEqual(kept.sidebarSubjectPid, 1)
    }

    func testRisingOnlyClearsInRowsSubjectWithoutSettling() throws {
        var store = ProcessQuitOutcome()
        let rows = [row(1, "A"), row(2, "B")]
        _ = try fail(1, rows: rows, store: &store)
        let before = try XCTUnwrap(store.record(for: 1))
        let cleared = ProcessQuitSession.risingOnlySelection(
            nextListPid: nil,
            sidebarSubjectPid: 1,
            rows: rows,
            store: store
        )
        XCTAssertNil(cleared.listSelectedPid)
        XCTAssertNil(cleared.sidebarSubjectPid)
        XCTAssertEqual(try XCTUnwrap(store.record(for: 1)), before)
        XCTAssertEqual(before.presence, .inRows)
        XCTAssertEqual(before.opportunity, .open)
    }

    func testAbsenceFreezesTheCardAndLaterFramesDoNotAppend() throws {
        var store = ProcessQuitOutcome()
        let rows = [row(1, "A", memory: 111), row(2, "B", memory: 5)]
        _ = try fail(1, rows: rows, store: &store)
        let original = detail(1, "A", memory: 111, memoryPoints: 4, cpuPoints: 3)
        let effect = ProcessQuitSession.applySample(
            store: &store,
            listSelectedPid: 1,
            sidebarSubjectPid: 1,
            currentLiveDetail: original,
            observation: ProcessQuitSession.Observation(
                rows: [row(2, "B", memory: 5)],
                liveDetail: detail(2, "B", memory: 5, memoryPoints: 2, cpuPoints: 2),
                detailToFreeze: original
            )
        )
        XCTAssertNil(effect.listSelectedPid)
        XCTAssertEqual(effect.sidebarSubjectPid, 1)
        XCTAssertNil(effect.liveDetail)
        let record = try XCTUnwrap(store.record(for: 1))
        XCTAssertEqual(record.presence, .absentAndUnknown)
        XCTAssertEqual(record.phase, .failed)
        XCTAssertEqual(record.opportunity, .open)
        XCTAssertEqual(record.frozenDetail, original)

        let longer = detail(1, "A", memory: 999, memoryPoints: 8, cpuPoints: 7)
        let again = ProcessQuitSession.applySample(
            store: &store,
            listSelectedPid: nil,
            sidebarSubjectPid: 1,
            currentLiveDetail: nil,
            observation: ProcessQuitSession.Observation(
                rows: [row(2, "B", memory: 9)],
                liveDetail: longer,
                detailToFreeze: longer
            )
        )
        XCTAssertEqual(again.sidebarSubjectPid, 1)
        XCTAssertNil(again.listSelectedPid)
        let frozen = try XCTUnwrap(store.record(for: 1)?.frozenDetail)
        XCTAssertEqual(frozen, original)
        XCTAssertEqual(frozen.memorySeries.count, 4)
        XCTAssertEqual(frozen.cpuSeries.count, 3)
        XCTAssertLessThan(frozen.memorySeries.count, longer.memorySeries.count)
        XCTAssertEqual(frozen.row.memoryBytes, 111)

        let side = project(store, list: nil, subject: 1, rows: [row(2, "B")], live: longer)
        XCTAssertEqual(side.viewState, .absentFromList)
        XCTAssertTrue(side.frozen)
        XCTAssertEqual(side.detail, original)
        XCTAssertNotEqual(side.detail?.row.memoryBytes, longer.row.memoryBytes)
        XCTAssertEqual(side.absentLabel, "已不在列表／上次记录")
        XCTAssertEqual(side.quitPhase, .idle)
        XCTAssertNil(side.quitMessage)
        XCTAssertFalse(side.showsFailureCard)
        XCTAssertFalse(side.showsQuittingSpinner)
        XCTAssertFalse(side.buttonsEnabled)
        XCTAssertNil(side.actionPid)
        XCTAssertFalse(side.showsLiveTrend)
        XCTAssertFalse(side.showsSuccessBanner)
        XCTAssertNil(
            ProcessQuitSession.ordinaryTerminate(
                store: &store,
                listSelectedPid: nil,
                sidebarSubjectPid: 1,
                rows: [row(2, "B")]
            )
        )
        XCTAssertNil(store.record(for: 2))
        XCTAssertEqual(store.record(for: 1)?.token, record.token)
        XCTAssertEqual(store.record(for: 1)?.presence, .absentAndUnknown)
    }

    func testQuittingAbsenceIsNeutralFreezeNotASpinner() throws {
        var store = ProcessQuitOutcome()
        let rows = [row(4, "A")]
        let issued = try XCTUnwrap(
            ProcessQuitSession.ordinaryTerminate(
                store: &store,
                listSelectedPid: 4,
                sidebarSubjectPid: 4,
                rows: rows
            )
        )
        let original = detail(4, "A", memoryPoints: 2, cpuPoints: 2)
        _ = ProcessQuitSession.applySample(
            store: &store,
            listSelectedPid: 4,
            sidebarSubjectPid: 4,
            currentLiveDetail: original,
            observation: ProcessQuitSession.Observation(rows: [], detailToFreeze: original)
        )
        let record = try XCTUnwrap(store.record(for: 4))
        XCTAssertEqual(record.phase, .quitting)
        XCTAssertEqual(record.opportunity, .open)
        XCTAssertEqual(record.presence, .absentAndUnknown)
        XCTAssertEqual(record.token, issued.token)
        let side = project(store, list: nil, subject: 4, rows: [], live: nil)
        XCTAssertEqual(side.viewState, .absentFromList)
        XCTAssertFalse(side.showsQuittingSpinner)
        XCTAssertNotEqual(side.quitPhase, .quitting)
        XCTAssertEqual(side.detail, original)
        XCTAssertFalse(side.buttonsEnabled)
        XCTAssertFalse(side.showsSuccessBanner)
    }

    func testFailedObservationsDoNotChangePresencePhaseOrFrozenDetail() throws {
        var store = ProcessQuitOutcome()
        let rows = [row(5, "A", memory: 20)]
        _ = try fail(5, rows: rows, store: &store)
        let original = detail(5, "A", memory: 20, memoryPoints: 3, cpuPoints: 2)
        _ = ProcessQuitSession.applySample(
            store: &store,
            listSelectedPid: 5,
            sidebarSubjectPid: 5,
            currentLiveDetail: original,
            observation: ProcessQuitSession.Observation(rows: [], detailToFreeze: original)
        )
        let frozen = try XCTUnwrap(store.record(for: 5))
        let cases: [ProcessQuitSession.Observation] = [
            ProcessQuitSession.Observation(rows: [], detailToFreeze: detail(5, "A", memory: 1, memoryPoints: 9, cpuPoints: 9), processListFailed: true),
            ProcessQuitSession.Observation(rows: [], samplingFailed: true),
            ProcessQuitSession.Observation(rows: [], freshnessInsufficient: true),
            ProcessQuitSession.Observation(
                rows: [row(5, "A", memory: 999)],
                liveDetail: detail(5, "A", memory: 999, memoryPoints: 6, cpuPoints: 6),
                processListFailed: true
            ),
        ]
        for observation in cases {
            let before = try XCTUnwrap(store.record(for: 5))
            let effect = ProcessQuitSession.applySample(
                store: &store,
                listSelectedPid: nil,
                sidebarSubjectPid: 5,
                currentLiveDetail: nil,
                observation: observation
            )
            XCTAssertEqual(try XCTUnwrap(store.record(for: 5)), before)
            XCTAssertEqual(effect.listSelectedPid, nil)
            XCTAssertEqual(effect.sidebarSubjectPid, 5)
            XCTAssertNil(effect.liveDetail)
            XCTAssertEqual(store.record(for: 5)?.frozenDetail, frozen.frozenDetail)
            XCTAssertEqual(store.record(for: 5)?.presence, .absentAndUnknown)
            XCTAssertEqual(store.record(for: 5)?.phase, .failed)
            XCTAssertEqual(store.record(for: 5)?.opportunity, .open)
        }
    }

    func testSuccessfulListIsTheOnlyObservationThatMarksAbsence() throws {
        var store = ProcessQuitOutcome()
        let rows = [row(6, "A")]
        _ = try fail(6, rows: rows, store: &store)
        let blocked = ProcessQuitSession.Observation(rows: [], processListFailed: true)
        _ = ProcessQuitSession.applySample(
            store: &store,
            listSelectedPid: 6,
            sidebarSubjectPid: 6,
            currentLiveDetail: detail(6, "A"),
            observation: blocked
        )
        XCTAssertEqual(store.record(for: 6)?.presence, .inRows)
        _ = ProcessQuitSession.applySample(
            store: &store,
            listSelectedPid: 6,
            sidebarSubjectPid: 6,
            currentLiveDetail: detail(6, "A", memoryPoints: 2, cpuPoints: 1),
            observation: ProcessQuitSession.Observation(rows: [])
        )
        XCTAssertEqual(store.record(for: 6)?.presence, .absentAndUnknown)
        XCTAssertEqual(store.record(for: 6)?.phase, .failed)
    }

    func testReappearanceWithoutEvidenceStaysLiveAndUnconfirmed() throws {
        var store = ProcessQuitOutcome()
        let rows = [row(7, "A", memory: 10), row(8, "B", memory: 4)]
        let failed = try fail(7, rows: rows, store: &store)
        let original = detail(7, "A", memory: 10, memoryPoints: 4, cpuPoints: 2)
        _ = ProcessQuitSession.applySample(
            store: &store,
            listSelectedPid: 7,
            sidebarSubjectPid: 7,
            currentLiveDetail: original,
            observation: ProcessQuitSession.Observation(rows: [row(8, "B")], detailToFreeze: original)
        )
        let cameBack = [row(7, "A", memory: 77), row(8, "B", memory: 4)]
        let live = detail(7, "A", memory: 77, memoryPoints: 1, cpuPoints: 1)
        let effect = ProcessQuitSession.applySample(
            store: &store,
            listSelectedPid: nil,
            sidebarSubjectPid: 7,
            currentLiveDetail: nil,
            observation: ProcessQuitSession.Observation(rows: cameBack, liveDetail: live)
        )
        XCTAssertNil(effect.listSelectedPid)
        XCTAssertEqual(effect.sidebarSubjectPid, 7)
        let record = try XCTUnwrap(store.record(for: 7))
        XCTAssertEqual(record.presence, .currentReappearedUnconfirmed)
        XCTAssertNotEqual(record.presence, .inRows)
        XCTAssertEqual(record.phase, .failed)
        XCTAssertEqual(record.opportunity, .open)
        XCTAssertEqual(record.token, failed.token)
        XCTAssertEqual(record.frozenDetail, original)

        let watching = project(store, list: nil, subject: 7, rows: cameBack, live: nil)
        XCTAssertEqual(watching.viewState, .liveAsNewProcess)
        XCTAssertFalse(watching.frozen)
        XCTAssertFalse(watching.showsFailureCard)
        XCTAssertNil(watching.quitMessage)
        XCTAssertFalse(watching.showsQuittingSpinner)
        XCTAssertNil(watching.absentLabel)
        XCTAssertEqual(watching.detail?.row.memoryBytes, 77)
        XCTAssertNotEqual(watching.detail, original)
        XCTAssertEqual(watching.detail?.memorySeries.count, 0)
        XCTAssertFalse(watching.buttonsEnabled)
        XCTAssertNil(watching.actionPid)
        XCTAssertFalse(watching.showsSuccessBanner)

        let selected = project(store, list: 7, subject: 7, rows: cameBack, live: live)
        XCTAssertEqual(selected.viewState, .liveAsNewProcess)
        XCTAssertEqual(selected.detail, live)
        XCTAssertNotEqual(selected.detail?.memorySeries.count, original.memorySeries.count)
        XCTAssertNil(selected.quitMessage)
        XCTAssertTrue(selected.buttonsEnabled)
        XCTAssertEqual(selected.actionPid, 7)
        XCTAssertTrue(selected.showsLiveTrend)

        let issued = try XCTUnwrap(
            ProcessQuitSession.ordinaryTerminate(
                store: &store,
                listSelectedPid: 7,
                sidebarSubjectPid: 7,
                rows: cameBack
            )
        )
        XCTAssertNotEqual(issued.token, failed.token)
        XCTAssertEqual(issued.pid, 7)
        let replaced = try XCTUnwrap(store.record(for: 7))
        XCTAssertEqual(replaced.presence, .inRows)
        XCTAssertEqual(replaced.phase, .quitting)
        XCTAssertNil(replaced.frozenDetail)
        ProcessQuitSession.finish(
            store: &store,
            pid: 7,
            token: failed.token,
            result: .exited,
            taskCancelled: false
        )
        XCTAssertEqual(try XCTUnwrap(store.record(for: 7)), replaced)
        let otherList = 8
        XCTAssertEqual(otherList, 8)
        XCTAssertNil(store.record(for: 8))
    }

    func testOrdinaryClickTokensRetryAndInFlightDoesNotIssueAgain() throws {
        var store = ProcessQuitOutcome()
        let rows = [row(3, "A"), row(4, "B")]
        let first = try XCTUnwrap(
            ProcessQuitSession.ordinaryTerminate(
                store: &store,
                listSelectedPid: 3,
                sidebarSubjectPid: 3,
                rows: rows
            )
        )
        XCTAssertEqual(first.pid, 3)
        XCTAssertEqual(store.record(for: 3)?.phase, .quitting)
        let quitting = project(store, list: 3, subject: 3, rows: rows, live: nil)
        XCTAssertEqual(quitting.quitPhase, .quitting)
        XCTAssertTrue(quitting.showsQuittingSpinner)
        XCTAssertNil(quitting.quitMessage)
        XCTAssertFalse(quitting.buttonsEnabled)
        XCTAssertNil(quitting.actionPid)
        XCTAssertNil(
            ProcessQuitSession.ordinaryTerminate(
                store: &store,
                listSelectedPid: 3,
                sidebarSubjectPid: 3,
                rows: rows
            )
        )
        XCTAssertEqual(store.record(for: 3)?.token, first.token)
        XCTAssertEqual(store.trackedCount, 1)

        ProcessQuitSession.finish(
            store: &store,
            pid: first.pid,
            token: first.token,
            result: .stillRunning,
            taskCancelled: false
        )
        let failedSide = project(store, list: 3, subject: 3, rows: rows, live: nil)
        XCTAssertEqual(failedSide.quitMessage, ProcessQuitSessionCopy.terminateFailed)
        XCTAssertTrue(failedSide.buttonsEnabled)

        let second = try XCTUnwrap(
            ProcessQuitSession.ordinaryTerminate(
                store: &store,
                listSelectedPid: 3,
                sidebarSubjectPid: 3,
                rows: rows
            )
        )
        XCTAssertNotEqual(second.token, first.token)
        XCTAssertEqual(second.pid, 3)
        ProcessQuitSession.finish(
            store: &store,
            pid: second.pid,
            token: second.token,
            result: .requestFailed,
            taskCancelled: false
        )
        ProcessQuitSession.finish(
            store: &store,
            pid: second.pid,
            token: second.token,
            result: .requestFailed,
            taskCancelled: false
        )
        let again = try XCTUnwrap(store.record(for: 3))
        XCTAssertEqual(again.phase, .failed)
        XCTAssertEqual(again.opportunity, .open)
        XCTAssertEqual(again.token, second.token)
        XCTAssertEqual(
            project(store, list: 3, subject: 3, rows: rows, live: nil).quitMessage,
            ProcessQuitSessionCopy.terminateFailed
        )
        let beforeStale = again
        var selectedNow: Int32? = 4
        selectedNow = 4
        ProcessQuitSession.finish(
            store: &store,
            pid: first.pid,
            token: first.token,
            result: .exited,
            taskCancelled: false
        )
        XCTAssertEqual(try XCTUnwrap(store.record(for: 3)), beforeStale)
        XCTAssertEqual(selectedNow, 4)
        XCTAssertNil(store.record(for: 4))
    }

    func testCompletionUsesPidAndTokenNotTheCurrentSelection() throws {
        var store = ProcessQuitOutcome()
        let rows = [row(1, "A"), row(2, "B")]
        let a = try XCTUnwrap(
            ProcessQuitSession.ordinaryTerminate(
                store: &store,
                listSelectedPid: 1,
                sidebarSubjectPid: 1,
                rows: rows
            )
        )
        let moved = ProcessQuitSession.followListSelection(
            listSelectedPid: 2,
            sidebarSubjectPid: 1,
            rows: rows
        )
        XCTAssertEqual(moved.sidebarSubjectPid, 2)
        let b = try XCTUnwrap(
            ProcessQuitSession.ordinaryTerminate(
                store: &store,
                listSelectedPid: 2,
                sidebarSubjectPid: 2,
                rows: rows
            )
        )
        let bBefore = try XCTUnwrap(store.record(for: 2))
        let listNow: Int32? = 2
        let subjectNow: Int32? = 2
        ProcessQuitSession.finish(
            store: &store,
            pid: a.pid,
            token: a.token,
            result: .exited,
            taskCancelled: false
        )
        XCTAssertEqual(listNow, 2)
        XCTAssertEqual(subjectNow, 2)
        XCTAssertEqual(store.record(for: 1)?.opportunity, .closed)
        XCTAssertEqual(store.record(for: 1)?.phase, .quitting)
        XCTAssertEqual(try XCTUnwrap(store.record(for: 2)), bBefore)
        let bSide = project(store, list: listNow, subject: subjectNow, rows: rows, live: nil)
        XCTAssertEqual(bSide.viewState, .quitting)
        XCTAssertFalse(bSide.showsSuccessBanner)
        XCTAssertNil(bSide.quitMessage)
        let aSide = project(store, list: 1, subject: 1, rows: rows, live: nil)
        XCTAssertEqual(aSide.viewState, .settledInRows)
        XCTAssertNil(aSide.quitMessage)
        XCTAssertFalse(aSide.showsFailureCard)
        XCTAssertFalse(aSide.showsAbsentRecord)
        XCTAssertTrue(aSide.buttonsEnabled)
        _ = b
    }

    func testExitedAndNotFoundCloseWithoutABannerAndRepeatIsIdempotent() throws {
        for result in [ProcessActionResult.exited, .notFound] {
            var store = ProcessQuitOutcome()
            let rows = [row(9, "A")]
            let issued = try XCTUnwrap(
                ProcessQuitSession.ordinaryTerminate(
                    store: &store,
                    listSelectedPid: 9,
                    sidebarSubjectPid: 9,
                    rows: rows
                )
            )
            ProcessQuitSession.finish(
                store: &store,
                pid: issued.pid,
                token: issued.token,
                result: result,
                taskCancelled: false
            )
            let closed = try XCTUnwrap(store.record(for: 9))
            XCTAssertEqual(closed.opportunity, .closed)
            XCTAssertNotEqual(closed.phase, .failed)
            ProcessQuitSession.finish(
                store: &store,
                pid: issued.pid,
                token: issued.token,
                result: result,
                taskCancelled: false
            )
            ProcessQuitSession.finish(
                store: &store,
                pid: issued.pid,
                token: issued.token,
                result: result == .exited ? .notFound : .exited,
                taskCancelled: false
            )
            XCTAssertEqual(try XCTUnwrap(store.record(for: 9)), closed)
            let side = project(store, list: 9, subject: 9, rows: rows, live: nil)
            XCTAssertFalse(side.showsSuccessBanner)
            XCTAssertNil(side.quitMessage)
            XCTAssertFalse(side.showsFailureCard)
            _ = ProcessQuitSession.applySample(
                store: &store,
                listSelectedPid: 9,
                sidebarSubjectPid: 9,
                currentLiveDetail: nil,
                observation: ProcessQuitSession.Observation(freshnessInsufficient: true)
            )
            XCTAssertEqual(try XCTUnwrap(store.record(for: 9)), closed)
            XCTAssertNotEqual(store.record(for: 9)?.phase, .failed)
        }
    }

    func testCancelledTaskDoesNotFinish() throws {
        var store = ProcessQuitOutcome()
        let rows = [row(10, "A")]
        let issued = try XCTUnwrap(
            ProcessQuitSession.ordinaryTerminate(
                store: &store,
                listSelectedPid: 10,
                sidebarSubjectPid: 10,
                rows: rows
            )
        )
        let before = try XCTUnwrap(store.record(for: 10))
        ProcessQuitSession.finish(
            store: &store,
            pid: issued.pid,
            token: issued.token,
            result: .exited,
            taskCancelled: true
        )
        ProcessQuitSession.finish(
            store: &store,
            pid: issued.pid,
            token: issued.token,
            result: .stillRunning,
            taskCancelled: true
        )
        XCTAssertEqual(try XCTUnwrap(store.record(for: 10)), before)
        XCTAssertEqual(before.phase, .quitting)
        XCTAssertEqual(before.opportunity, .open)
    }

    func testForceRequestCancelAndMovedTargetDoNotQuit() throws {
        var store = ProcessQuitOutcome()
        let rows = [row(1, "Alpha", memory: 3), row(2, "Beta", memory: 4)]
        let failed = try fail(1, rows: rows, store: &store)
        let before = try XCTUnwrap(store.record(for: 1))
        let clock = store.nextToken
        let request = try XCTUnwrap(
            ProcessQuitSession.requestForce(
                store: &store,
                listSelectedPid: 1,
                sidebarSubjectPid: 1,
                rows: rows
            )
        )
        XCTAssertEqual(request.targetPid, 1)
        XCTAssertEqual(request.displayName, "Alpha")
        XCTAssertNotEqual(request.displayName, "Beta")
        XCTAssertEqual(store.record(for: 1)?.phase, .failed)
        XCTAssertEqual(store.record(for: 1)?.token, failed.token)
        XCTAssertEqual(store.nextToken, clock)
        XCTAssertEqual(store.pendingForceConfirmation?.generation, request.generation)
        XCTAssertEqual(
            project(store, list: 1, subject: 1, rows: rows, live: nil).quitMessage,
            ProcessQuitSessionCopy.terminateFailed
        )
        XCTAssertNil(
            ProcessQuitSession.requestForce(
                store: &store,
                listSelectedPid: 1,
                sidebarSubjectPid: 1,
                rows: rows
            )
        )
        XCTAssertEqual(store.pendingForceConfirmation?.generation, request.generation)

        ProcessQuitSession.cancelForce(store: &store, generation: request.generation)
        XCTAssertNil(store.pendingForceConfirmation)
        XCTAssertEqual(try XCTUnwrap(store.record(for: 1)), before)
        XCTAssertNotEqual(store.record(for: 1)?.phase, .quitting)
        XCTAssertEqual(store.record(for: 1)?.opportunity, .open)
        let afterCancel = project(store, list: 1, subject: 1, rows: rows, live: nil)
        XCTAssertTrue(afterCancel.buttonsEnabled)
        XCTAssertEqual(afterCancel.quitMessage, ProcessQuitSessionCopy.terminateFailed)
        XCTAssertFalse(afterCancel.showsSuccessBanner)

        let again = try XCTUnwrap(
            ProcessQuitSession.requestForce(
                store: &store,
                listSelectedPid: 1,
                sidebarSubjectPid: 1,
                rows: rows
            )
        )
        XCTAssertNil(
            ProcessQuitSession.confirmForce(
                store: &store,
                generation: again.generation,
                listSelectedPid: 2,
                rows: rows
            )
        )
        XCTAssertNil(store.record(for: 2))
        XCTAssertEqual(store.record(for: 1)?.phase, .failed)
        XCTAssertEqual(store.record(for: 1)?.token, failed.token)
        XCTAssertNotEqual(store.record(for: 1)?.phase, .quitting)
        XCTAssertNil(store.pendingForceConfirmation)
    }

    func testForceConfirmOnTheSameLegalPidIssuesANewToken() throws {
        var store = ProcessQuitOutcome()
        let rows = [row(1, "Alpha"), row(2, "Beta")]
        let failed = try fail(1, rows: rows, store: &store)
        let request = try XCTUnwrap(
            ProcessQuitSession.requestForce(
                store: &store,
                listSelectedPid: 1,
                sidebarSubjectPid: 1,
                rows: rows
            )
        )
        let issued = try XCTUnwrap(
            ProcessQuitSession.confirmForce(
                store: &store,
                generation: request.generation,
                listSelectedPid: 1,
                rows: rows
            )
        )
        XCTAssertEqual(issued.pid, 1)
        XCTAssertEqual(issued.kind, .forceTerminate)
        XCTAssertNotEqual(issued.token, failed.token)
        XCTAssertNil(store.pendingForceConfirmation)
        XCTAssertEqual(store.record(for: 1)?.phase, .quitting)
        XCTAssertEqual(store.record(for: 1)?.presence, .inRows)
        ProcessQuitSession.finish(
            store: &store,
            pid: issued.pid,
            token: failed.token,
            result: .stillRunning,
            taskCancelled: false
        )
        XCTAssertEqual(store.record(for: 1)?.token, issued.token)
        XCTAssertEqual(store.record(for: 1)?.phase, .quitting)
        ProcessQuitSession.finish(
            store: &store,
            pid: issued.pid,
            token: issued.token,
            result: .stillRunning,
            taskCancelled: false
        )
        XCTAssertEqual(store.record(for: 1)?.phase, .failed)
        XCTAssertEqual(store.record(for: 1)?.kind, .forceTerminate)
        XCTAssertEqual(store.record(for: 1)?.opportunity, .open)
        XCTAssertEqual(
            project(store, list: 1, subject: 1, rows: rows, live: nil).quitMessage,
            ProcessQuitSessionCopy.forceFailed
        )
        XCTAssertNil(store.record(for: 2))
    }

    func testAbsentForceConfirmKeepsKnifeOneGuardUntilReappearance() throws {
        var store = ProcessQuitOutcome()
        let rows = [row(48, "A")]
        let failed = try fail(48, rows: rows, store: &store)
        let request = try XCTUnwrap(
            ProcessQuitSession.requestForce(
                store: &store,
                listSelectedPid: 48,
                sidebarSubjectPid: 48,
                rows: rows
            )
        )
        _ = ProcessQuitSession.applySample(
            store: &store,
            listSelectedPid: 48,
            sidebarSubjectPid: 48,
            currentLiveDetail: detail(48, "A"),
            observation: ProcessQuitSession.Observation(rows: [])
        )
        XCTAssertEqual(store.record(for: 48)?.presence, .absentAndUnknown)
        let clock = store.nextToken
        XCTAssertNil(
            ProcessQuitSession.confirmForce(
                store: &store,
                generation: request.generation,
                listSelectedPid: 48,
                rows: rows
            )
        )
        XCTAssertEqual(store.pendingForceConfirmation?.generation, request.generation)
        XCTAssertEqual(store.record(for: 48)?.presence, .absentAndUnknown)
        XCTAssertNotEqual(store.record(for: 48)?.presence, .inRows)
        XCTAssertEqual(store.record(for: 48)?.phase, .failed)
        XCTAssertEqual(store.record(for: 48)?.token, failed.token)
        XCTAssertEqual(store.nextToken, clock)
        XCTAssertNil(
            ProcessQuitSession.requestForce(
                store: &store,
                listSelectedPid: 48,
                sidebarSubjectPid: 48,
                rows: rows
            )
        )

        _ = ProcessQuitSession.applySample(
            store: &store,
            listSelectedPid: nil,
            sidebarSubjectPid: 48,
            currentLiveDetail: nil,
            observation: ProcessQuitSession.Observation(rows: rows)
        )
        XCTAssertEqual(store.record(for: 48)?.presence, .currentReappearedUnconfirmed)
        XCTAssertNotEqual(store.record(for: 48)?.presence, .inRows)
        let issued = try XCTUnwrap(
            ProcessQuitSession.confirmForce(
                store: &store,
                generation: request.generation,
                listSelectedPid: 48,
                rows: rows
            )
        )
        XCTAssertEqual(issued.pid, 48)
        XCTAssertEqual(issued.kind, .forceTerminate)
        XCTAssertNotEqual(issued.token, failed.token)
        XCTAssertEqual(store.record(for: 48)?.presence, .inRows)
        XCTAssertEqual(store.record(for: 48)?.phase, .quitting)
        let watching = project(store, list: 48, subject: 48, rows: rows, live: nil)
        XCTAssertEqual(watching.viewState, .quitting)
        XCTAssertNil(watching.quitMessage)
        XCTAssertFalse(watching.showsFailureCard)
    }

    func testClosedAbsenceStaysNeutralUntilSidebarChangesSubject() throws {
        var store = ProcessQuitOutcome()
        let rows = [row(11, "A")]
        let issued = try XCTUnwrap(
            ProcessQuitSession.ordinaryTerminate(
                store: &store,
                listSelectedPid: 11,
                sidebarSubjectPid: 11,
                rows: rows
            )
        )
        let original = detail(11, "A", memoryPoints: 2, cpuPoints: 2)
        _ = ProcessQuitSession.applySample(
            store: &store,
            listSelectedPid: 11,
            sidebarSubjectPid: 11,
            currentLiveDetail: original,
            observation: ProcessQuitSession.Observation(rows: [], detailToFreeze: original)
        )
        ProcessQuitSession.finish(
            store: &store,
            pid: issued.pid,
            token: issued.token,
            result: .exited,
            taskCancelled: false
        )
        let side = project(store, list: nil, subject: 11, rows: [], live: nil)
        XCTAssertEqual(side.viewState, .absentFromList)
        XCTAssertEqual(side.absentLabel, ProcessQuitOutcomeCopy.absentRecordLabel)
        XCTAssertNil(side.quitMessage)
        XCTAssertFalse(side.showsFailureCard)
        XCTAssertFalse(side.showsQuittingSpinner)
        XCTAssertFalse(side.buttonsEnabled)
        XCTAssertFalse(side.showsSuccessBanner)
        XCTAssertEqual(side.detail, original)
        XCTAssertEqual(store.record(for: 11)?.opportunity, .closed)
        let kept = try XCTUnwrap(store.record(for: 11))
        let dismissed = ProcessQuitSession.dismissSidebar()
        XCTAssertNil(dismissed.sidebarSubjectPid)
        XCTAssertEqual(try XCTUnwrap(store.record(for: 11)), kept)
        let empty = project(store, list: nil, subject: nil, rows: [], live: nil)
        XCTAssertEqual(empty.viewState, .none)
        XCTAssertNil(empty.absentLabel)
    }

    func testLookingAtBDoesNotActOnFrozenA() throws {
        var store = ProcessQuitOutcome()
        let rows = [row(1, "A"), row(2, "B")]
        let failed = try fail(1, rows: rows, store: &store)
        _ = ProcessQuitSession.applySample(
            store: &store,
            listSelectedPid: 1,
            sidebarSubjectPid: 1,
            currentLiveDetail: detail(1, "A", memoryPoints: 2, cpuPoints: 1),
            observation: ProcessQuitSession.Observation(rows: [row(2, "B")], detailToFreeze: detail(1, "A", memoryPoints: 2, cpuPoints: 1))
        )
        let moved = ProcessQuitSession.followListSelection(
            listSelectedPid: 2,
            sidebarSubjectPid: 1,
            rows: [row(2, "B")]
        )
        XCTAssertEqual(moved.sidebarSubjectPid, 2)
        XCTAssertNil(
            ProcessQuitSession.ordinaryTerminate(
                store: &store,
                listSelectedPid: nil,
                sidebarSubjectPid: 1,
                rows: [row(2, "B")]
            )
        )
        XCTAssertEqual(store.record(for: 1)?.token, failed.token)
        XCTAssertNil(store.record(for: 2))
        let bee = try XCTUnwrap(
            ProcessQuitSession.ordinaryTerminate(
                store: &store,
                listSelectedPid: 2,
                sidebarSubjectPid: 2,
                rows: [row(2, "B")]
            )
        )
        XCTAssertEqual(bee.pid, 2)
        XCTAssertNotEqual(bee.pid, 1)
        XCTAssertEqual(store.record(for: 1)?.token, failed.token)
        XCTAssertEqual(store.record(for: 1)?.phase, .failed)
    }

    func testRisingOnlyKeepsAnAbsentSubjectAndItsRecord() throws {
        var store = ProcessQuitOutcome()
        let rows = [row(1, "A")]
        _ = try fail(1, rows: rows, store: &store)
        _ = ProcessQuitSession.applySample(
            store: &store,
            listSelectedPid: 1,
            sidebarSubjectPid: 1,
            currentLiveDetail: detail(1, "A"),
            observation: ProcessQuitSession.Observation(rows: [])
        )
        let before = try XCTUnwrap(store.record(for: 1))
        let kept = ProcessQuitSession.risingOnlySelection(
            nextListPid: nil,
            sidebarSubjectPid: 1,
            rows: [],
            store: store
        )
        XCTAssertNil(kept.listSelectedPid)
        XCTAssertEqual(kept.sidebarSubjectPid, 1)
        XCTAssertEqual(try XCTUnwrap(store.record(for: 1)), before)
        XCTAssertEqual(before.presence, .absentAndUnknown)
        XCTAssertEqual(before.opportunity, .open)
    }

    func testNoQuitRecordUsesTheLiveRowAndEnablesAFreshClick() throws {
        let store = ProcessQuitOutcome()
        let rows = [row(15, "Plain", memory: 12)]
        let side = project(store, list: 15, subject: 15, rows: rows, live: nil)
        XCTAssertEqual(side.viewState, .none)
        XCTAssertEqual(side.quitPhase, .idle)
        XCTAssertNil(side.quitMessage)
        XCTAssertTrue(side.buttonsEnabled)
        XCTAssertEqual(side.actionPid, 15)
        XCTAssertEqual(side.detail?.row.memoryBytes, 12)
        XCTAssertEqual(side.detail?.memorySeries.count, 0)
        XCTAssertFalse(side.frozen)
        XCTAssertFalse(side.showsSuccessBanner)
    }

    private func project(
        _ store: ProcessQuitOutcome,
        list: Int32?,
        subject: Int32?,
        rows: [ProcessRow],
        live: ProcessDetail?
    ) -> ProcessQuitSession.Sidebar {
        ProcessQuitSession.sidebar(
            store,
            ProcessQuitSession.Context(
                listSelectedPid: list,
                sidebarSubjectPid: subject,
                rows: rows,
                liveDetail: live
            )
        )
    }

    @discardableResult
    private func fail(
        _ pid: Int32,
        rows: [ProcessRow],
        store: inout ProcessQuitOutcome
    ) throws -> ProcessQuitIssued {
        let issued = try XCTUnwrap(store.click(.terminate, selectedPid: pid, rows: rows))
        store.complete(pid: pid, token: issued.token, result: .stillRunning)
        return issued
    }

    private func row(_ pid: Int32, _ name: String, memory: UInt64 = 1_000) -> ProcessRow {
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
        _ pid: Int32,
        _ name: String,
        memory: UInt64 = 1_000,
        memoryPoints: Int = 1,
        cpuPoints: Int = 1
    ) -> ProcessDetail {
        ProcessDetail(
            row: row(pid, name, memory: memory),
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
}
