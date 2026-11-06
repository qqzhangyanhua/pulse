import Foundation

/// Session store for the latest quit attempt of each pid.
///
/// Names are local to this file. There is no existing per-pid store to stay
/// compatible with: `QuitPhase` stays the untouched global enum and is not a
/// second copy of this record. Scaffold only — transitions are filled in after
/// the red tests exist.
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
        _ = (action, selectedPid, rows, nextForceGeneration)
        return nil
    }

    mutating func applyPresenceFromRows(_ frame: ProcessQuitPresenceFrame) {
        _ = frame
    }

    mutating func complete(pid: Int32, token: UInt64, result: ProcessActionResult) {
        _ = (pid, token, result)
    }

    func project(
        listSelectedPid: Int32?,
        sidebarSubjectPid: Int32?,
        rows: [ProcessRow]
    ) -> ProcessQuitProjection {
        _ = (listSelectedPid, sidebarSubjectPid, rows, records, nextToken, pendingForceConfirmation)
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
}

struct ProcessQuitRecord: Equatable, Sendable {
    let pid: Int32
    var kind: ProcessQuitKind
    var phase: ProcessQuitPhase
    var token: UInt64
    var opportunity: ProcessQuitOpportunity
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
