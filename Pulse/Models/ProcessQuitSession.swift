import Foundation

/// Compilable stand-in so the phase-16 sidebar tests can run.
/// Behavior is intentionally incomplete: joint projection is not implemented.
enum ProcessQuitSessionCopy {
    static let terminateFailed = "未能退出。可以请系统立即结束该进程。"
    static let forceFailed = "系统未能结束该进程。"
}

enum ProcessQuitSession {
    struct Context: Equatable, Sendable {
        var listSelectedPid: Int32?
        var sidebarSubjectPid: Int32?
        var rows: [ProcessRow]
        var liveDetail: ProcessDetail?
    }

    struct Sidebar: Equatable, Sendable {
        var detail: ProcessDetail?
        var frozen: Bool
        var quitPhase: QuitPhase
        var quitMessage: String?
        var absentLabel: String?
        var buttonsEnabled: Bool
        var showsQuittingSpinner: Bool
        var showsFailureCard: Bool
        var showsAbsentRecord: Bool
        var showsSuccessBanner: Bool
        var showsLiveTrend: Bool
        var viewState: ProcessQuitViewState
        var actionPid: Int32?
    }

    struct Observation: Equatable, Sendable {
        var rows: [ProcessRow] = []
        var liveDetail: ProcessDetail?
        var detailToFreeze: ProcessDetail?
        var processListFailed: Bool = false
        var samplingFailed: Bool = false
        var freshnessInsufficient: Bool = false
    }

    struct SampleEffect: Equatable, Sendable {
        var listSelectedPid: Int32?
        var sidebarSubjectPid: Int32?
        var liveDetail: ProcessDetail?
    }

    struct Selection: Equatable, Sendable {
        var listSelectedPid: Int32?
        var sidebarSubjectPid: Int32?
    }

    struct ForceRequest: Equatable, Sendable {
        var generation: UInt64
        var targetPid: Int32
        var displayName: String
    }

    static func sidebar(_ store: ProcessQuitOutcome, _ context: Context) -> Sidebar {
        _ = (store, context)
        return Sidebar(
            detail: nil,
            frozen: false,
            quitPhase: .idle,
            quitMessage: nil,
            absentLabel: nil,
            buttonsEnabled: false,
            showsQuittingSpinner: false,
            showsFailureCard: false,
            showsAbsentRecord: false,
            showsSuccessBanner: false,
            showsLiveTrend: false,
            viewState: .none,
            actionPid: nil
        )
    }

    static func applySample(
        store: inout ProcessQuitOutcome,
        listSelectedPid: Int32?,
        sidebarSubjectPid: Int32?,
        currentLiveDetail: ProcessDetail?,
        observation: Observation
    ) -> SampleEffect {
        _ = (store, observation)
        return SampleEffect(
            listSelectedPid: listSelectedPid,
            sidebarSubjectPid: sidebarSubjectPid,
            liveDetail: currentLiveDetail
        )
    }

    static func followListSelection(
        listSelectedPid: Int32?,
        sidebarSubjectPid: Int32?,
        rows: [ProcessRow]
    ) -> Selection {
        _ = rows
        return Selection(listSelectedPid: listSelectedPid, sidebarSubjectPid: sidebarSubjectPid)
    }

    static func dismissSidebar() -> Selection {
        Selection(listSelectedPid: nil, sidebarSubjectPid: nil)
    }

    static func risingOnlySelection(
        nextListPid: Int32?,
        sidebarSubjectPid: Int32?,
        rows: [ProcessRow],
        store: ProcessQuitOutcome
    ) -> Selection {
        _ = (rows, store)
        return Selection(listSelectedPid: nextListPid, sidebarSubjectPid: sidebarSubjectPid)
    }

    static func ordinaryTerminate(
        store: inout ProcessQuitOutcome,
        listSelectedPid: Int32?,
        sidebarSubjectPid: Int32?,
        rows: [ProcessRow]
    ) -> ProcessQuitIssued? {
        _ = (store, listSelectedPid, sidebarSubjectPid, rows)
        return nil
    }

    static func requestForce(
        store: inout ProcessQuitOutcome,
        listSelectedPid: Int32?,
        sidebarSubjectPid: Int32?,
        rows: [ProcessRow]
    ) -> ForceRequest? {
        _ = (store, listSelectedPid, sidebarSubjectPid, rows)
        return nil
    }

    static func cancelForce(store: inout ProcessQuitOutcome, generation: UInt64) {
        _ = (store, generation)
    }

    static func confirmForce(
        store: inout ProcessQuitOutcome,
        generation: UInt64,
        listSelectedPid: Int32?,
        rows: [ProcessRow]
    ) -> ProcessQuitIssued? {
        _ = (store, generation, listSelectedPid, rows)
        return nil
    }

    static func finish(
        store: inout ProcessQuitOutcome,
        pid: Int32,
        token: UInt64,
        result: ProcessActionResult,
        taskCancelled: Bool
    ) {
        _ = (store, pid, token, result, taskCancelled)
    }
}
