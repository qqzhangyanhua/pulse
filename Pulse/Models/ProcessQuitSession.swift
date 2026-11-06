import Foundation

/// Joint sidebar projection for the one session `ProcessQuitOutcome`.
///
/// The dashboard holds that store and calls these functions. This type is not a
/// second quit store, not a view, and not a sampler. Production observations
/// leave identity evidence at the model default.
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
        /// Legal list pid a button may address. Nil means do not call terminate.
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
        let projected = store.project(
            listSelectedPid: context.listSelectedPid,
            sidebarSubjectPid: context.sidebarSubjectPid,
            rows: context.rows
        )
        let subject = context.sidebarSubjectPid
        let record = subject.flatMap { store.record(for: $0) }
        let detail = displayedDetail(store: store, context: context, projected: projected)
        let frozen = projected.showsAbsentRecord
        let message = failureMessage(projected: projected, record: record)
        let phase: QuitPhase
        if projected.showsQuittingSpinner {
            phase = .quitting
        } else if projected.showsFailureCard {
            phase = .failed
        } else {
            phase = .idle
        }
        let buttonsEnabled = projected.canRetry || projected.allowsFreshOperation
        let legalSubject = subject.flatMap { ProcessQuitOutcome.legalListSelection($0, in: context.rows) }
        let actionPid = buttonsEnabled && legalSubject == subject && subject == context.listSelectedPid
            ? subject
            : nil
        let showsLiveTrend = !frozen
            && detail != nil
            && context.listSelectedPid == subject
            && legalSubject != nil
        return Sidebar(
            detail: detail,
            frozen: frozen,
            quitPhase: phase,
            quitMessage: message,
            absentLabel: projected.absentLabel,
            buttonsEnabled: buttonsEnabled,
            showsQuittingSpinner: projected.showsQuittingSpinner,
            showsFailureCard: projected.showsFailureCard,
            showsAbsentRecord: projected.showsAbsentRecord,
            showsSuccessBanner: false,
            showsLiveTrend: showsLiveTrend,
            viewState: projected.viewState,
            actionPid: actionPid
        )
    }

    static func applySample(
        store: inout ProcessQuitOutcome,
        listSelectedPid: Int32?,
        sidebarSubjectPid: Int32?,
        currentLiveDetail: ProcessDetail?,
        observation: Observation
    ) -> SampleEffect {
        let frame = ProcessQuitPresenceFrame(
            rows: observation.rows,
            processListFailed: observation.processListFailed,
            samplingFailed: observation.samplingFailed,
            freshnessInsufficient: observation.freshnessInsufficient,
            detail: observation.detailToFreeze
        )
        store.applyPresenceFromRows(frame)
        guard frame.isSuccessfulProcessList else {
            return SampleEffect(
                listSelectedPid: listSelectedPid,
                sidebarSubjectPid: sidebarSubjectPid,
                liveDetail: currentLiveDetail
            )
        }

        var nextList = listSelectedPid
        if ProcessQuitOutcome.legalListSelection(nextList, in: observation.rows) == nil {
            nextList = nil
        }
        var nextSubject = sidebarSubjectPid
        if let subject = nextSubject {
            let present = observation.rows.contains { $0.pid == subject }
            if !present && store.record(for: subject) == nil {
                nextSubject = nil
            }
        }
        return SampleEffect(
            listSelectedPid: nextList,
            sidebarSubjectPid: nextSubject,
            liveDetail: liveDetail(
                nextList: nextList,
                listSelectedPid: listSelectedPid,
                current: currentLiveDetail,
                incoming: observation.liveDetail
            )
        )
    }

    /// A legal row choice becomes the sidebar subject. Nil does not clear it,
    /// and a pid missing from `rows` is not a sampler target.
    static func followListSelection(
        listSelectedPid: Int32?,
        sidebarSubjectPid: Int32?,
        rows: [ProcessRow]
    ) -> Selection {
        let legal = ProcessQuitOutcome.legalListSelection(listSelectedPid, in: rows)
        return Selection(
            listSelectedPid: legal,
            sidebarSubjectPid: legal ?? sidebarSubjectPid
        )
    }

    /// Sidebar close. The quit store is not an argument, so this cannot settle it.
    static func dismissSidebar() -> Selection {
        Selection(listSelectedPid: nil, sidebarSubjectPid: nil)
    }

    /// Rising-only rewrites the list id only. An in-rows subject clears with the
    /// list. An absent record stays on the sidebar. The store is not mutated.
    static func risingOnlySelection(
        nextListPid: Int32?,
        sidebarSubjectPid: Int32?,
        rows: [ProcessRow],
        store: ProcessQuitOutcome
    ) -> Selection {
        let legal = ProcessQuitOutcome.legalListSelection(nextListPid, in: rows)
        let subject: Int32?
        if let legal {
            subject = legal
        } else if let sidebarSubjectPid,
                  let record = store.record(for: sidebarSubjectPid),
                  record.presence == .absentAndUnknown,
                  ProcessQuitOutcome.legalListSelection(sidebarSubjectPid, in: rows) == nil {
            subject = sidebarSubjectPid
        } else {
            subject = nil
        }
        return Selection(listSelectedPid: legal, sidebarSubjectPid: subject)
    }

    static func ordinaryTerminate(
        store: inout ProcessQuitOutcome,
        listSelectedPid: Int32?,
        sidebarSubjectPid: Int32?,
        rows: [ProcessRow]
    ) -> ProcessQuitIssued? {
        let side = sidebar(
            store,
            Context(
                listSelectedPid: listSelectedPid,
                sidebarSubjectPid: sidebarSubjectPid,
                rows: rows,
                liveDetail: nil
            )
        )
        guard let pid = side.actionPid, pid == listSelectedPid else { return nil }
        return store.click(.terminate, selectedPid: pid, rows: rows)
    }

    static func requestForce(
        store: inout ProcessQuitOutcome,
        listSelectedPid: Int32?,
        sidebarSubjectPid: Int32?,
        rows: [ProcessRow]
    ) -> ForceRequest? {
        guard store.pendingForceConfirmation == nil else { return nil }
        let side = sidebar(
            store,
            Context(
                listSelectedPid: listSelectedPid,
                sidebarSubjectPid: sidebarSubjectPid,
                rows: rows,
                liveDetail: nil
            )
        )
        guard let pid = side.actionPid, pid == listSelectedPid else { return nil }
        store.click(.requestForce, selectedPid: pid, rows: rows)
        guard let pending = store.pendingForceConfirmation, pending.targetPid == pid else { return nil }
        guard let name = rows.first(where: { $0.pid == pid })?.name else {
            store.click(.cancelForce(generation: pending.generation), selectedPid: pid, rows: rows)
            return nil
        }
        return ForceRequest(generation: pending.generation, targetPid: pid, displayName: name)
    }

    static func cancelForce(store: inout ProcessQuitOutcome, generation: UInt64) {
        store.click(.cancelForce(generation: generation), selectedPid: nil, rows: [])
    }

    static func confirmForce(
        store: inout ProcessQuitOutcome,
        generation: UInt64,
        listSelectedPid: Int32?,
        rows: [ProcessRow]
    ) -> ProcessQuitIssued? {
        store.click(.confirmForce(generation: generation), selectedPid: listSelectedPid, rows: rows)
    }

    /// Closed confirmation only. Scaffold until the same generation is consumed.
    static func releaseClosedForceConfirmation(
        store: inout ProcessQuitOutcome,
        generation: UInt64,
        issued: ProcessQuitIssued?
    ) {
        _ = generation
        _ = issued
        _ = store.pendingForceConfirmation
    }

    /// Completion is the issued pid and token. A cancelled task is not a result.
    static func finish(
        store: inout ProcessQuitOutcome,
        pid: Int32,
        token: UInt64,
        result: ProcessActionResult,
        taskCancelled: Bool
    ) {
        guard !taskCancelled else { return }
        store.complete(pid: pid, token: token, result: result)
    }

    private static func failureMessage(
        projected: ProcessQuitProjection,
        record: ProcessQuitRecord?
    ) -> String? {
        guard projected.showsFailureCard, let record else { return nil }
        switch record.kind {
        case .terminate:
            return ProcessQuitSessionCopy.terminateFailed
        case .forceTerminate:
            return ProcessQuitSessionCopy.forceFailed
        }
    }

    private static func displayedDetail(
        store: ProcessQuitOutcome,
        context: Context,
        projected: ProcessQuitProjection
    ) -> ProcessDetail? {
        guard let subject = context.sidebarSubjectPid else { return nil }
        if projected.showsAbsentRecord {
            return store.record(for: subject)?.frozenDetail
        }
        if let live = context.liveDetail, live.row.pid == subject {
            return live
        }
        guard let row = context.rows.first(where: { $0.pid == subject }) else { return nil }
        return ProcessDetail(row: row, memorySeries: [], cpuSeries: [])
    }

    private static func liveDetail(
        nextList: Int32?,
        listSelectedPid: Int32?,
        current: ProcessDetail?,
        incoming: ProcessDetail?
    ) -> ProcessDetail? {
        if let incoming, incoming.row.pid == nextList {
            return incoming
        }
        if nextList == listSelectedPid, let current, current.row.pid == nextList {
            return current
        }
        return nil
    }
}
