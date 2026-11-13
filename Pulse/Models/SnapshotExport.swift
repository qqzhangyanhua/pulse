import Foundation

/// User-facing copy for one frozen sample. The main window still uses 「—」 for missing
/// readings; this document uses 「不可用」 and does not change `CPUPercentText.missing`.
enum SnapshotExportCopy {
    static let noSampleMessage = "暂无可保存的采样，请稍后重试"
    static let notLive = "非实时。采样时间不是现在，也不是打开文件的时间。"
    static let rateExplanation = "CPU、网络和磁盘速率是到采样时间为止的一段差值，不是同一瞬间的读数。"
    static let staleSample = "更晚的采样没有回来。下面仍是上一次已发布的读数，采样时间没有改成快照生成时间。"
    static let unavailable = "不可用"
    static let hiddenName = "已隐藏"
    static let rankExplanation = "名次只按内存占用排列，不表示卡顿原因。"
    static let processListMissing = "进程列表没有读到。"
    static let writeFailure = "没能写入所选位置。这一份采样还在，可以再试。"
    static let redactionChanged = "隐去项已改变。当前预览还没写入文件，请重新保存。"
    static let hideNamesChanged = redactionChanged
    static let htmlTitle = "Pulse 采样"

    static func onlyProcessCount(_ count: Int) -> String {
        "当前只有 \(count) 个进程。"
    }
}

/// Frozen fields for one save. Bundle ids, curves, per-process disk, energy, and wakeups are not copied.
/// Executable paths, the host name, and an address are copied only so redaction can hide them.
struct SnapshotExport: Equatable, Sendable {
    struct Process: Equatable, Sendable {
        let pid: Int32
        let name: String
        let executablePath: String?
        let memoryBytes: UInt64
        let memorySource: ProcessMemorySource
        let cpuPercent: Double?
        let threadCount: Int
    }

    let capturedAt: Date
    let savedAt: Date
    let samplingFailed: Bool
    let processListFailed: Bool
    let usedBytes: UInt64
    let totalBytes: UInt64
    let appBytes: UInt64
    let wiredBytes: UInt64
    let compressedBytes: UInt64
    let cachedBytes: UInt64
    let swapUsedBytes: UInt64?
    let pressure: PressureLevel
    let systemCpuPercent: Double?
    let busiestCorePercent: Double?
    let networkInboundBytesPerSecond: Double?
    let networkOutboundBytesPerSecond: Double?
    let diskReadBytesPerSecond: Double?
    let diskWriteBytesPerSecond: Double?
    /// Noted host name. Nil when the adapter has not recorded one. Not read here.
    let hostname: String?
    /// Address already held in memory. Nil when there is none. Not a new lookup.
    let ipAddress: String?
    let processes: [Process]

    /// `nil` when the published host snapshot is missing. Does not read a clock or sample.
    static func freeze(
        snapshot: MemorySnapshot?,
        rows: [ProcessRow],
        systemCpuPercent: Double?,
        busiestCorePercent: Double?,
        hostNetworkRates: HostNetworkRates,
        hostDiskRates: HostDiskRates,
        samplingFailed: Bool,
        processListFailed: Bool,
        savedAt: Date,
        hostname: String? = nil,
        ipAddress: String? = nil
    ) -> SnapshotExport? {
        guard let snapshot else { return nil }
        return SnapshotExport(
            capturedAt: snapshot.capturedAt,
            savedAt: savedAt,
            samplingFailed: samplingFailed,
            processListFailed: processListFailed,
            usedBytes: snapshot.usedBytes,
            totalBytes: snapshot.totalBytes,
            appBytes: snapshot.breakdown.appBytes,
            wiredBytes: snapshot.breakdown.wiredBytes,
            compressedBytes: snapshot.breakdown.compressedBytes,
            cachedBytes: snapshot.breakdown.cachedBytes,
            swapUsedBytes: snapshot.swapUsedBytes,
            pressure: snapshot.pressure,
            systemCpuPercent: systemCpuPercent,
            busiestCorePercent: busiestCorePercent,
            networkInboundBytesPerSecond: hostNetworkRates.inboundBytesPerSecond,
            networkOutboundBytesPerSecond: hostNetworkRates.outboundBytesPerSecond,
            diskReadBytesPerSecond: hostDiskRates.readBytesPerSecond,
            diskWriteBytesPerSecond: hostDiskRates.writeBytesPerSecond,
            hostname: nonBlank(hostname),
            ipAddress: nonBlank(ipAddress),
            processes: rows.map {
                Process(
                    pid: $0.pid,
                    name: $0.name,
                    executablePath: $0.executablePath,
                    memoryBytes: $0.memoryBytes,
                    memorySource: $0.memorySource,
                    cpuPercent: $0.cpuPercent,
                    threadCount: $0.threadCount
                )
            }
        )
    }

    private static func nonBlank(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
            return nil
        }
        return trimmed
    }
}

/// Preview session for one freeze. Canceling the system panel does not drop it.
struct SnapshotExportSaveAttempt: Equatable, Sendable {
    let id: UUID
    let sessionID: UUID
}

enum SnapshotExportSavePanelDecision: Equatable {
    case ignore
    case cancelled
    case write(String)
}

enum SnapshotExportSavePanelState: Equatable {
    case idle
    case awaiting(UUID)
    case writing(UUID)
}

struct SnapshotExportSession {
    let id: UUID
    let frozen: SnapshotExport
    private(set) var redaction: SnapshotRedaction
    private(set) var phase: Phase
    private(set) var savePanel: SnapshotExportSavePanelState
    let calendar: Calendar
    let timeZone: TimeZone

    enum Phase: Equatable {
        case preview
        case writeFailed
        case needsResave
        case saved
    }

    /// `hideNames` still selects only the process-name category. Omitted, every category stays hidden.
    init(
        frozen: SnapshotExport,
        hideNames: Bool? = nil,
        redaction: SnapshotRedaction = .default,
        calendar: Calendar,
        timeZone: TimeZone,
        id: UUID = UUID()
    ) {
        var policy = redaction
        if let hideNames {
            policy.hidesProcessName = hideNames
        }
        self.id = id
        self.frozen = frozen
        self.redaction = policy
        self.phase = .preview
        self.savePanel = .idle
        self.calendar = calendar
        self.timeZone = timeZone
    }

    var hideNames: Bool { redaction.hidesProcessName }

    var document: SnapshotDocument {
        SnapshotDocument.make(
            frozen: frozen,
            redaction: redaction,
            calendar: calendar,
            timeZone: timeZone
        )
    }

    var banner: String? {
        switch phase {
        case .preview:
            return nil
        case .writeFailed:
            return SnapshotExportCopy.writeFailure
        case .needsResave:
            return SnapshotExportCopy.redactionChanged
        case .saved:
            return "已保存"
        }
    }

    mutating func setHideNames(_ hide: Bool) {
        setRedaction(\.hidesProcessName, hide)
    }

    mutating func setHidesUsernamePath(_ hide: Bool) {
        setRedaction(\.hidesUsernamePath, hide)
    }

    mutating func setHidesHostname(_ hide: Bool) {
        setRedaction(\.hidesHostname, hide)
    }

    mutating func setHidesIPAddress(_ hide: Bool) {
        setRedaction(\.hidesIPAddress, hide)
    }

    private mutating func setRedaction(_ keyPath: WritableKeyPath<SnapshotRedaction, Bool>, _ hide: Bool) {
        guard redaction[keyPath: keyPath] != hide else { return }
        redaction[keyPath: keyPath] = hide
        if phase == .saved {
            phase = .needsResave
        }
    }

    /// The system save panel was dismissed. The sheet and the frozen frame stay.
    mutating func cancelSavePanel() {}

    mutating func noteWriteFailed() {
        phase = .writeFailed
    }

    mutating func noteWriteSucceeded() {
        phase = .saved
    }

    mutating func beginSavePanel() -> SnapshotExportSaveAttempt? {
        guard savePanel == .idle else { return nil }
        let attemptID = UUID()
        savePanel = .awaiting(attemptID)
        return SnapshotExportSaveAttempt(id: attemptID, sessionID: id)
    }

    mutating func receiveSavePanel(
        _ attempt: SnapshotExportSaveAttempt,
        confirmed: Bool
    ) -> SnapshotExportSavePanelDecision {
        guard attempt.sessionID == id, case .awaiting(let openID) = savePanel, openID == attempt.id else {
            return .ignore
        }
        if !confirmed {
            savePanel = .idle
            return .cancelled
        }
        savePanel = .writing(attempt.id)
        return .write(document.html)
    }

    mutating func finishSavePanel(_ attempt: SnapshotExportSaveAttempt, succeeded: Bool) {
        guard attempt.sessionID == id, case .writing(let openID) = savePanel, openID == attempt.id else {
            return
        }
        savePanel = .idle
        phase = succeeded ? .saved : .writeFailed
    }
}

/// One preview at a time. Save-panel callbacks are accepted only for the attempt that opened them.
struct SnapshotExportSaveGate {
    private(set) var session: SnapshotExportSession?

    mutating func present(_ session: SnapshotExportSession) {
        self.session = session
    }

    mutating func dismiss() {
        session = nil
    }

    mutating func setHideNames(_ hide: Bool) {
        session?.setHideNames(hide)
    }

    mutating func setHidesUsernamePath(_ hide: Bool) {
        session?.setHidesUsernamePath(hide)
    }

    mutating func setHidesHostname(_ hide: Bool) {
        session?.setHidesHostname(hide)
    }

    mutating func setHidesIPAddress(_ hide: Bool) {
        session?.setHidesIPAddress(hide)
    }

    mutating func noteWriteSucceeded() {
        session?.noteWriteSucceeded()
    }

    mutating func noteWriteFailed() {
        session?.noteWriteFailed()
    }

    mutating func beginSavePanel() -> SnapshotExportSaveAttempt? {
        guard var current = session else { return nil }
        guard let attempt = current.beginSavePanel() else { return nil }
        session = current
        return attempt
    }

    mutating func receiveSavePanel(
        _ attempt: SnapshotExportSaveAttempt,
        confirmed: Bool
    ) -> SnapshotExportSavePanelDecision {
        guard var current = session else { return .ignore }
        let decision = current.receiveSavePanel(attempt, confirmed: confirmed)
        session = current
        return decision
    }

    mutating func finishSavePanel(_ attempt: SnapshotExportSaveAttempt, succeeded: Bool) {
        guard var current = session else { return }
        current.finishSavePanel(attempt, succeeded: succeeded)
        session = current
    }
}
