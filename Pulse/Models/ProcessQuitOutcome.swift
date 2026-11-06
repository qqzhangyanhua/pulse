import Foundation

/// Latest quit attempt for each pid in this session.
///
/// There is no existing per-pid store to stay compatible with. `QuitPhase`
/// stays the untouched global enum and is not a second copy of these records.
/// `phase` is only `.quitting` or `.failed`. Presence and opportunity are
/// separate fields, so leaving the list does not settle the attempt.
///
/// `identityEvidence` defaults to false. This model has no start time.
/// `true` is a caller-supplied injection for tests; it does not mean the
/// process list can prove the pid is the same instance.
struct ProcessQuitOutcome: Equatable, Sendable {
    static let productionIdentityEvidence = false

    private var records: [Int32: ProcessQuitRecord] = [:]
    private(set) var nextToken: UInt64 = 1
    private var nextForceGeneration: UInt64 = 1
    private(set) var pendingForceConfirmation: ProcessQuitForcePending?

    func record(for pid: Int32) -> ProcessQuitRecord? {
        records[pid]
    }

    var trackedCount: Int { records.count }

    /// A vanished pid is not a new legal list selection.
    static func legalListSelection(_ pid: Int32?, in rows: [ProcessRow]) -> Int32? {
        guard let pid else { return nil }
        return ProcessSelection.acceptedPid(pid, in: rows)
    }

    @discardableResult
    mutating func click(
        _ action: ProcessQuitClick,
        selectedPid: Int32?,
        rows: [ProcessRow]
    ) -> ProcessQuitIssued? {
        switch action {
        case .terminate:
            return beginTerminate(selectedPid: selectedPid, rows: rows)
        case .requestForce:
            beginForceConfirmation(selectedPid: selectedPid, rows: rows)
            return nil
        case .cancelForce(let generation):
            cancelForceConfirmation(generation: generation)
            return nil
        case .confirmForce(let generation):
            return confirmForce(generation: generation, selectedPid: selectedPid, rows: rows)
        }
    }

    mutating func applyPresenceFromRows(_ frame: ProcessQuitPresenceFrame) {
        guard frame.isSuccessfulProcessList else { return }
        for pid in Array(records.keys) {
            guard var record = records[pid] else { continue }
            let present = frame.rows.contains(where: { $0.pid == pid })
            if present {
                switch record.presence {
                case .inRows:
                    break
                case .absentAndUnknown, .currentReappearedUnconfirmed:
                    record.presence = frame.identityEvidence
                        ? .inRows
                        : .currentReappearedUnconfirmed
                }
            } else if record.presence != .absentAndUnknown {
                if let detail = frame.detail, detail.row.pid == pid {
                    record.frozenDetail = detail
                }
                record.presence = .absentAndUnknown
            }
            records[pid] = record
        }
    }

    mutating func complete(pid: Int32, token: UInt64, result: ProcessActionResult) {
        guard var record = records[pid], record.token == token else { return }
        switch result {
        case .requestFailed, .stillRunning:
            guard record.opportunity == .open else { return }
            record.phase = .failed
        case .exited, .notFound:
            guard record.opportunity == .open else { return }
            record.opportunity = .closed
        }
        records[pid] = record
    }

    func project(
        listSelectedPid: Int32?,
        sidebarSubjectPid: Int32?,
        rows: [ProcessRow]
    ) -> ProcessQuitProjection {
        guard let subject = sidebarSubjectPid else {
            return ProcessQuitProjection(
                viewState: .none,
                canRetry: false,
                allowsFreshOperation: false,
                showsQuittingSpinner: false,
                showsFailureCard: false,
                showsAbsentRecord: false,
                absentLabel: nil
            )
        }
        let legalSelf = listSelectedPid == subject
            && Self.legalListSelection(subject, in: rows) != nil
        guard let record = records[subject] else {
            return ProcessQuitProjection(
                viewState: .none,
                canRetry: false,
                allowsFreshOperation: legalSelf,
                showsQuittingSpinner: false,
                showsFailureCard: false,
                showsAbsentRecord: false,
                absentLabel: nil
            )
        }

        if record.presence == .currentReappearedUnconfirmed {
            return ProcessQuitProjection(
                viewState: .liveAsNewProcess,
                canRetry: false,
                allowsFreshOperation: legalSelf,
                showsQuittingSpinner: false,
                showsFailureCard: false,
                showsAbsentRecord: false,
                absentLabel: nil
            )
        }
        if record.presence == .absentAndUnknown {
            return ProcessQuitProjection(
                viewState: .absentFromList,
                canRetry: false,
                allowsFreshOperation: false,
                showsQuittingSpinner: false,
                showsFailureCard: false,
                showsAbsentRecord: true,
                absentLabel: ProcessQuitOutcomeCopy.absentRecordLabel
            )
        }
        if record.opportunity == .closed && record.presence == .inRows {
            return ProcessQuitProjection(
                viewState: .settledInRows,
                canRetry: false,
                allowsFreshOperation: legalSelf,
                showsQuittingSpinner: false,
                showsFailureCard: false,
                showsAbsentRecord: false,
                absentLabel: nil
            )
        }
        if record.opportunity == .open && record.phase == .failed && record.presence == .inRows {
            return ProcessQuitProjection(
                viewState: .failedStillPresent,
                canRetry: legalSelf,
                allowsFreshOperation: false,
                showsQuittingSpinner: false,
                showsFailureCard: true,
                showsAbsentRecord: false,
                absentLabel: nil
            )
        }
        return ProcessQuitProjection(
            viewState: .quitting,
            canRetry: false,
            allowsFreshOperation: false,
            showsQuittingSpinner: true,
            showsFailureCard: false,
            showsAbsentRecord: false,
            absentLabel: nil
        )
    }

    private func isInFlight(_ record: ProcessQuitRecord) -> Bool {
        record.phase == .quitting
            && record.opportunity == .open
            && record.presence == .inRows
    }

    /// Store presence, not the rows argument. A successful reappearance frame
    /// moves this off `.absentAndUnknown` before a new quit is legal.
    private func isAbsent(_ pid: Int32) -> Bool {
        records[pid]?.presence == .absentAndUnknown
    }

    private mutating func beginTerminate(selectedPid: Int32?, rows: [ProcessRow]) -> ProcessQuitIssued? {
        guard let pid = Self.legalListSelection(selectedPid, in: rows) else { return nil }
        if let existing = records[pid], isInFlight(existing) || isAbsent(pid) {
            return nil
        }
        return replaceWithQuitting(pid: pid, kind: .terminate)
    }

    private mutating func beginForceConfirmation(selectedPid: Int32?, rows: [ProcessRow]) {
        guard pendingForceConfirmation == nil else { return }
        guard let pid = Self.legalListSelection(selectedPid, in: rows) else { return }
        if let existing = records[pid], isInFlight(existing) || isAbsent(pid) {
            return
        }
        let generation = nextForceGeneration
        nextForceGeneration &+= 1
        pendingForceConfirmation = ProcessQuitForcePending(generation: generation, targetPid: pid)
    }

    private mutating func cancelForceConfirmation(generation: UInt64) {
        guard pendingForceConfirmation?.generation == generation else { return }
        pendingForceConfirmation = nil
    }

    private mutating func confirmForce(
        generation: UInt64,
        selectedPid: Int32?,
        rows: [ProcessRow]
    ) -> ProcessQuitIssued? {
        guard let pending = pendingForceConfirmation, pending.generation == generation else {
            return nil
        }
        if isAbsent(pending.targetPid) {
            return nil
        }
        pendingForceConfirmation = nil
        let target = pending.targetPid
        guard selectedPid == target, Self.legalListSelection(target, in: rows) != nil else {
            return nil
        }
        if let existing = records[target], isInFlight(existing) {
            return nil
        }
        return replaceWithQuitting(pid: target, kind: .forceTerminate)
    }

    private mutating func replaceWithQuitting(pid: Int32, kind: ProcessQuitKind) -> ProcessQuitIssued {
        if pendingForceConfirmation?.targetPid == pid {
            pendingForceConfirmation = nil
        }
        let token = nextToken
        nextToken &+= 1
        records[pid] = ProcessQuitRecord(
            pid: pid,
            kind: kind,
            phase: .quitting,
            token: token,
            opportunity: .open,
            frozenDetail: nil,
            presence: .inRows
        )
        return ProcessQuitIssued(pid: pid, token: token, kind: kind)
    }
}

struct ProcessQuitRecord: Equatable, Sendable {
    let pid: Int32
    var kind: ProcessQuitKind
    var phase: ProcessQuitPhase
    var token: UInt64
    var opportunity: ProcessQuitOpportunity
    /// Value copy of the detail frame from the first absence. Later frames do not append.
    var frozenDetail: ProcessDetail?
    var presence: ProcessQuitPresence
}

enum ProcessQuitKind: Equatable, Sendable {
    case terminate
    case forceTerminate
}

/// Operation only. Presence and opportunity are other fields.
enum ProcessQuitPhase: Equatable, Sendable {
    case quitting
    case failed
}

enum ProcessQuitOpportunity: Equatable, Sendable {
    case open
    case closed
}

enum ProcessQuitPresence: Equatable, Sendable {
    case inRows
    case absentAndUnknown
    case currentReappearedUnconfirmed
}

enum ProcessQuitViewState: Equatable, Sendable {
    case liveAsNewProcess
    case absentFromList
    case settledInRows
    case failedStillPresent
    case quitting
    case none
}

struct ProcessQuitProjection: Equatable, Sendable {
    var viewState: ProcessQuitViewState
    var canRetry: Bool
    var allowsFreshOperation: Bool
    var showsQuittingSpinner: Bool
    var showsFailureCard: Bool
    var showsAbsentRecord: Bool
    var absentLabel: String?
    var showsSuccessBanner: Bool { false }
}

struct ProcessQuitForcePending: Equatable, Sendable {
    let generation: UInt64
    let targetPid: Int32
}

enum ProcessQuitClick: Equatable, Sendable {
    case terminate
    case requestForce
    case cancelForce(generation: UInt64)
    case confirmForce(generation: UInt64)
}

struct ProcessQuitIssued: Equatable, Sendable {
    let pid: Int32
    let token: UInt64
    let kind: ProcessQuitKind
}

struct ProcessQuitPresenceFrame: Equatable, Sendable {
    var rows: [ProcessRow]
    var processListFailed: Bool
    var samplingFailed: Bool
    var freshnessInsufficient: Bool
    var identityEvidence: Bool
    var detail: ProcessDetail?

    init(
        rows: [ProcessRow],
        processListFailed: Bool = false,
        samplingFailed: Bool = false,
        freshnessInsufficient: Bool = false,
        identityEvidence: Bool = ProcessQuitOutcome.productionIdentityEvidence,
        detail: ProcessDetail? = nil
    ) {
        self.rows = rows
        self.processListFailed = processListFailed
        self.samplingFailed = samplingFailed
        self.freshnessInsufficient = freshnessInsufficient
        self.identityEvidence = identityEvidence
        self.detail = detail
    }

    var isSuccessfulProcessList: Bool {
        !processListFailed && !samplingFailed && !freshnessInsufficient
    }
}

enum ProcessQuitOutcomeCopy {
    static let absentRecordLabel = "已不在列表／上次记录"
}
