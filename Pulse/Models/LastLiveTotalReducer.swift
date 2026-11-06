import Foundation

/// Denominator captured for one sidebar subject. Not a quit record and not a sample.
struct FrozenMemoryFieldSemantics: Equatable, Sendable {
    let pid: Int32
    /// Numerator copied from the frozen row at the absence transition.
    /// The projection still reads `detail.row.memoryBytes`; this value does not reject the denominator.
    let memoryBytes: UInt64
    /// Last `totalBytes > 0` seen for this pid during the continuous live stretch. Nil if none existed.
    let physicalTotalBytes: UInt64?
}

/// Positive physical total remembered for the current sidebar subject.
struct LastLiveTotal: Equatable, Sendable {
    let pid: Int32
    let totalBytes: UInt64
}

struct LastLiveTotalState: Equatable, Sendable {
    var lastLive: LastLiveTotal?
    var frozen: FrozenMemoryFieldSemantics?

    static let empty = LastLiveTotalState(lastLive: nil, frozen: nil)
}

enum LastLiveTotalEvent: Equatable, Sendable {
    case live(pid: Int32, totalBytes: UInt64?)
    case subject(Int32?)
    case newLiveSubject(pid: Int32, totalBytes: UInt64?)
    case freeze(pid: Int32, memoryBytes: UInt64)
}

/// Sidebar fields the absence callback compares. List selection is not the subject key.
struct SidebarSubjectBeat: Equatable, Sendable {
    var subjectPid: Int32?
    var showsAbsentRecord: Bool
    var sidebarDetailPid: Int32?
    var sidebarDetailMemoryBytes: UInt64?
    var hasSidebarDetail: Bool
    var liveDetailPid: Int32?
    var listSelectedPid: Int32?
    /// Both series on the sidebar detail are empty.
    var sidebarSeriesEmpty: Bool

    /// Row identity plus empty series, while `vm.detail` has not caught up.
    /// A real detail whose series are still empty is not this placeholder.
    var isRowPlaceholder: Bool {
        guard showsAbsentRecord == false,
              hasSidebarDetail,
              let subjectPid,
              sidebarDetailPid == subjectPid,
              liveDetailPid != subjectPid,
              sidebarSeriesEmpty
        else { return false }
        return true
    }

    /// Present subject whose sidebar detail pid matches `vm.detail`.
    /// The empty-series row placeholder is not this live.
    var isNormalLive: Bool {
        guard showsAbsentRecord == false,
              isRowPlaceholder == false,
              let subjectPid,
              let sidebarDetailPid,
              sidebarDetailPid == subjectPid,
              liveDetailPid == subjectPid
        else { return false }
        return true
    }
}

/// Current-sidebar gate for `.live`. An absent sidebar never produces that event.
struct SidebarLiveGate: Equatable, Sendable {
    var beat: SidebarSubjectBeat
    var snapshotTotalBytes: UInt64?

    init(beat: SidebarSubjectBeat, snapshotTotalBytes: UInt64?) {
        self.beat = beat
        self.snapshotTotalBytes = snapshotTotalBytes
    }

    var isNormalLive: Bool { beat.isNormalLive }
    var subjectPid: Int32? { beat.subjectPid }
}

/// Pure transition for the sidebar's last positive physical total.
/// The projection does not call this, and the value is not published on the dashboard.
enum LastLiveTotalReducer {
    static func step(_ state: LastLiveTotalState, _ event: LastLiveTotalEvent) -> LastLiveTotalState {
        switch event {
        case .live(let pid, let totalBytes):
            guard state.frozen == nil else { return state }
            guard let totalBytes, totalBytes > 0 else { return state }
            if let last = state.lastLive, last.pid != pid { return state }
            var next = state
            next.lastLive = LastLiveTotal(pid: pid, totalBytes: totalBytes)
            return next
        case .subject:
            return .empty
        case .newLiveSubject(let pid, let totalBytes):
            guard let totalBytes, totalBytes > 0 else { return .empty }
            return LastLiveTotalState(
                lastLive: LastLiveTotal(pid: pid, totalBytes: totalBytes),
                frozen: nil
            )
        case .freeze(let pid, let memoryBytes):
            guard state.frozen == nil else { return state }
            let total = state.lastLive?.pid == pid ? state.lastLive?.totalBytes : nil
            var next = state
            next.frozen = FrozenMemoryFieldSemantics(
                pid: pid,
                memoryBytes: memoryBytes,
                physicalTotalBytes: total
            )
            return next
        }
    }

    /// Appear, task, and snapshot callbacks. Already-absent sidebars return nil
    /// so a new snapshot cannot replace the remembered denominator.
    static func eventForCurrentSidebar(_ gate: SidebarLiveGate) -> LastLiveTotalEvent? {
        guard gate.isNormalLive, let pid = gate.subjectPid else { return nil }
        return .live(pid: pid, totalBytes: gate.snapshotTotalBytes)
    }

    /// Sidebar-subject callback. A nil list selection is not a subject change.
    /// Freeze carries the frozen row's bytes and does not read `snapshotTotalBytes`.
    /// While presence is not frozen, a row placeholder becoming the real detail
    /// still emits `.live` so the current snapshot total is observed.
    static func eventsForSidebar(
        previous: SidebarSubjectBeat,
        current: SidebarSubjectBeat,
        snapshotTotalBytes: UInt64?
    ) -> [LastLiveTotalEvent] {
        if previous.subjectPid != current.subjectPid {
            var events: [LastLiveTotalEvent] = [.subject(current.subjectPid)]
            let gate = SidebarLiveGate(beat: current, snapshotTotalBytes: snapshotTotalBytes)
            if let live = eventForCurrentSidebar(gate) {
                events.append(live)
            }
            return events
        }
        guard let pid = current.subjectPid else { return [] }
        if previous.showsAbsentRecord == false,
           current.showsAbsentRecord,
           current.hasSidebarDetail,
           let memoryBytes = current.sidebarDetailMemoryBytes {
            return [.freeze(pid: pid, memoryBytes: memoryBytes)]
        }
        if previous.showsAbsentRecord, current.showsAbsentRecord == false {
            return [.newLiveSubject(pid: pid, totalBytes: snapshotTotalBytes)]
        }
        if current.showsAbsentRecord == false, previous.isNormalLive == false {
            let gate = SidebarLiveGate(beat: current, snapshotTotalBytes: snapshotTotalBytes)
            if let live = eventForCurrentSidebar(gate) {
                return [live]
            }
        }
        return []
    }

    /// Frozen argument for the projection. Absent display never falls through to the
    /// current snapshot: before the sidebar callback locks semantics, the remembered
    /// live total is the denominator; after that, the locked value wins, including nil.
    static func frozenSemanticsForProjection(
        showsAbsentRecord: Bool,
        state: LastLiveTotalState,
        detailPid: Int32,
        detailMemoryBytes: UInt64
    ) -> FrozenMemoryFieldSemantics? {
        guard showsAbsentRecord else { return nil }
        if let frozen = state.frozen { return frozen }
        let total: UInt64?
        if let last = state.lastLive, last.pid == detailPid, last.totalBytes > 0 {
            total = last.totalBytes
        } else {
            total = nil
        }
        return FrozenMemoryFieldSemantics(
            pid: detailPid,
            memoryBytes: detailMemoryBytes,
            physicalTotalBytes: total
        )
    }
}
