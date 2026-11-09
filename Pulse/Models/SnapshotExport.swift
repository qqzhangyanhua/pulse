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
    static let hideNamesChanged = "隐藏进程名已改变。当前预览还没写入文件，请重新保存。"
    static let htmlTitle = "Pulse 采样"

    static func onlyProcessCount(_ count: Int) -> String {
        "当前只有 \(count) 个进程。"
    }
}

/// Frozen fields for one save. Paths, bundle ids, curves, disk, energy, and wakeups are not copied.
struct SnapshotExport: Equatable, Sendable {
    struct Process: Equatable, Sendable {
        let pid: Int32
        let name: String
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
        savedAt: Date
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
            processes: rows.map {
                Process(
                    pid: $0.pid,
                    name: $0.name,
                    memoryBytes: $0.memoryBytes,
                    memorySource: $0.memorySource,
                    cpuPercent: $0.cpuPercent,
                    threadCount: $0.threadCount
                )
            }
        )
    }
}

/// Preview text and HTML share these already formatted strings. No second number format.
struct SnapshotDocument: Equatable, Sendable {
    let previewText: String
    let html: String
    let suggestedFilename: String

    static func make(
        frozen: SnapshotExport,
        hideNames: Bool,
        calendar: Calendar,
        timeZone: TimeZone
    ) -> SnapshotDocument {
        let rendered = render(frozen: frozen, hideNames: hideNames, calendar: calendar, timeZone: timeZone)
        return SnapshotDocument(
            previewText: rendered.lines.joined(separator: "\n"),
            html: html(lines: rendered.lines, processes: rendered.processes),
            suggestedFilename: rendered.filename
        )
    }

    private struct Rendered {
        let lines: [String]
        let processes: [RenderedProcess]
        let filename: String
    }

    private struct RenderedProcess {
        let line: String
        let cells: [String]
    }

    private static func render(
        frozen: SnapshotExport,
        hideNames: Bool,
        calendar: Calendar,
        timeZone: TimeZone
    ) -> Rendered {
        let captured = format(frozen.capturedAt, calendar: calendar, timeZone: timeZone, pattern: "yyyy-MM-dd HH:mm:ss")
        let saved = format(frozen.savedAt, calendar: calendar, timeZone: timeZone, pattern: "yyyy-MM-dd HH:mm:ss")
        let stamp = format(frozen.savedAt, calendar: calendar, timeZone: timeZone, pattern: "yyyyMMdd-HHmmss")
        var lines = [
            SnapshotExportCopy.htmlTitle,
            SnapshotExportCopy.notLive,
            "采样时间：\(captured)",
            "快照生成时间：\(saved)",
            SnapshotExportCopy.rateExplanation,
        ]
        if frozen.samplingFailed {
            lines.append(SnapshotExportCopy.staleSample)
        }
        lines.append(contentsOf: [
            field("已用", ByteFormat.memory(frozen.usedBytes)),
            field("总量", ByteFormat.memory(frozen.totalBytes)),
            field("App", ByteFormat.memory(frozen.appBytes)),
            field("联动", ByteFormat.memory(frozen.wiredBytes)),
            field("被压缩", ByteFormat.memory(frozen.compressedBytes)),
            field("已缓存", ByteFormat.memory(frozen.cachedBytes)),
            field("交换", frozen.swapUsedBytes.map(ByteFormat.memory) ?? SnapshotExportCopy.unavailable),
            field("压力", frozen.pressure.title),
            field("整机 CPU", cpuText(frozen.systemCpuPercent)),
            field("最忙一核", cpuText(frozen.busiestCorePercent)),
            field("网络下行", rateText(frozen.networkInboundBytesPerSecond)),
            field("网络上行", rateText(frozen.networkOutboundBytesPerSecond)),
            field("磁盘读取", rateText(frozen.diskReadBytesPerSecond)),
            field("磁盘写入", rateText(frozen.diskWriteBytesPerSecond)),
            SnapshotExportCopy.rankExplanation,
        ])
        let processes = rankedProcesses(frozen: frozen, hideNames: hideNames)
        if frozen.processListFailed {
            lines.append(SnapshotExportCopy.processListMissing)
        } else if frozen.processes.count < 5 {
            lines.append(SnapshotExportCopy.onlyProcessCount(frozen.processes.count))
        }
        lines.append(contentsOf: processes.map(\.line))
        return Rendered(
            lines: lines,
            processes: processes,
            filename: "Pulse-快照-\(stamp).html"
        )
    }

    private static func rankedProcesses(frozen: SnapshotExport, hideNames: Bool) -> [RenderedProcess] {
        guard !frozen.processListFailed else { return [] }
        let ranked = frozen.processes.sorted { lhs, rhs in
            if lhs.memoryBytes != rhs.memoryBytes {
                return lhs.memoryBytes > rhs.memoryBytes
            }
            return lhs.pid < rhs.pid
        }
        return ranked.prefix(5).map { process in
            let name = hideNames ? SnapshotExportCopy.hiddenName : process.name
            let memory = ByteFormat.memory(process.memoryBytes)
            let source = memorySourceText(process.memorySource)
            let cpu = cpuText(process.cpuPercent)
            let threads = String(process.threadCount)
            let cells = [String(process.pid), name, memory, source, cpu, threads]
            let line = "\(process.pid) · \(name) · \(memory) · \(source) · \(cpu) · \(threads)"
            return RenderedProcess(line: line, cells: cells)
        }
    }

    private static func field(_ label: String, _ value: String) -> String {
        "\(label)：\(value)"
    }

    private static func memorySourceText(_ source: ProcessMemorySource) -> String {
        switch source {
        case .footprint:
            return "内存占用"
        case .resident:
            return "驻留内存"
        }
    }

    private static func cpuText(_ value: Double?) -> String {
        guard let value, value.isFinite else { return SnapshotExportCopy.unavailable }
        return CPUPercentText.string(value)
    }

    private static func rateText(_ value: Double?) -> String {
        guard let value, value.isFinite else { return SnapshotExportCopy.unavailable }
        return NetworkRateText.string(value)
    }

    private static func format(
        _ date: Date,
        calendar: Calendar,
        timeZone: TimeZone,
        pattern: String
    ) -> String {
        var calendar = calendar
        calendar.timeZone = timeZone
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = timeZone
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = pattern
        return formatter.string(from: date)
    }

    private static func html(lines: [String], processes: [RenderedProcess]) -> String {
        var parts = [
            "<html lang=\"zh-Hans\"><head><meta charset=\"utf-8\"><title>",
            SnapshotHTMLEscape.text(SnapshotExportCopy.htmlTitle),
            "</title><style>",
            css,
            "</style></head><body><h1>",
            SnapshotHTMLEscape.text(SnapshotExportCopy.htmlTitle),
            "</h1>",
        ]
        let processLines = Set(processes.map(\.line))
        for line in lines where line != SnapshotExportCopy.htmlTitle && !processLines.contains(line) {
            parts.append("<p>\(SnapshotHTMLEscape.text(line))</p>")
        }
        if !processes.isEmpty {
            parts.append("<h2>进程</h2><table><thead><tr>")
            for heading in ["PID", "名称", "内存", "内存来源", "CPU", "线程"] {
                parts.append("<th>\(heading)</th>")
            }
            parts.append("</tr></thead><tbody>")
            for process in processes {
                parts.append("<tr>")
                for cell in process.cells {
                    parts.append("<td>\(SnapshotHTMLEscape.text(cell))</td>")
                }
                parts.append("</tr>")
            }
            parts.append("</tbody></table>")
        }
        parts.append("</body></html>")
        return parts.joined()
    }

    private static let css = """
    body { font-family: sans-serif; color: #1c1c1e; background: #ffffff; margin: 24px; }
    h1 { font-size: 22px; }
    p { line-height: 1.5; }
    table { border-collapse: collapse; }
    th, td { border: 1px solid #d0d0d4; padding: 6px 8px; text-align: left; }
    """
}

enum SnapshotHTMLEscape {
    static func text(_ raw: String) -> String {
        var out = ""
        out.reserveCapacity(raw.count)
        for scalar in raw.unicodeScalars {
            switch scalar.value {
            case 0:
                out += "&#0;"
            case 0x26:
                out += "&amp;"
            case 0x3C:
                out += "&lt;"
            case 0x3E:
                out += "&gt;"
            case 0x22:
                out += "&quot;"
            case 0x27:
                out += "&#39;"
            case 0x2028:
                out += "&#8232;"
            case 0x2029:
                out += "&#8233;"
            default:
                out.unicodeScalars.append(scalar)
            }
        }
        return out
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
    private(set) var hideNames: Bool
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

    init(
        frozen: SnapshotExport,
        hideNames: Bool = false,
        calendar: Calendar,
        timeZone: TimeZone,
        id: UUID = UUID()
    ) {
        self.id = id
        self.frozen = frozen
        self.hideNames = hideNames
        self.phase = .preview
        self.savePanel = .idle
        self.calendar = calendar
        self.timeZone = timeZone
    }

    var document: SnapshotDocument {
        SnapshotDocument.make(
            frozen: frozen,
            hideNames: hideNames,
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
            return SnapshotExportCopy.hideNamesChanged
        case .saved:
            return "已保存"
        }
    }

    mutating func setHideNames(_ hide: Bool) {
        guard hide != hideNames else { return }
        hideNames = hide
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
