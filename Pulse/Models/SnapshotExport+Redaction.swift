import Foundation

/// Which sensitive categories a report leaves out. Each flag defaults to hidden.
struct SnapshotRedaction: Equatable, Sendable {
    var hidesProcessName: Bool
    var hidesUsernamePath: Bool
    var hidesHostname: Bool
    var hidesIPAddress: Bool

    static let `default` = SnapshotRedaction(
        hidesProcessName: true,
        hidesUsernamePath: true,
        hidesHostname: true,
        hidesIPAddress: true
    )

    /// A path contains a username when `Users` or `home` is followed by an account name.
    /// `Shared` is the shared folder, not an account.
    static func containsUsername(_ path: String?) -> Bool {
        guard let path else { return false }
        let parts = path.split(separator: "/", omittingEmptySubsequences: true)
        var index = parts.startIndex
        while index < parts.endIndex {
            let next = parts.index(after: index)
            if (parts[index] == "Users" || parts[index] == "home"), next < parts.endIndex, parts[next] != "Shared" {
                return true
            }
            index = next
        }
        return false
    }

    /// Categories that this render actually withheld, in product order. Nil when nothing was.
    static func disclosure(included: [SnapshotExport.Process], frozen: SnapshotExport, redaction: SnapshotRedaction) -> String? {
        var parts: [String] = []
        if redaction.hidesProcessName, !included.isEmpty {
            parts.append("进程名")
        }
        if redaction.hidesUsernamePath, included.contains(where: { containsUsername($0.executablePath) }) {
            parts.append("带用户名的路径")
        }
        if redaction.hidesHostname, frozen.hostname != nil {
            parts.append("主机名")
        }
        if redaction.hidesIPAddress, frozen.ipAddress != nil {
            parts.append("IP")
        }
        guard !parts.isEmpty else { return nil }
        return "已隐去：" + parts.joined(separator: "、")
    }
}

/// Preview text, HTML, and Markdown share these already formatted strings. No second number format.
struct SnapshotDocument: Equatable, Sendable {
    let previewText: String
    let html: String
    let markdown: String
    let suggestedFilename: String

    static func make(
        frozen: SnapshotExport,
        redaction: SnapshotRedaction = .default,
        calendar: Calendar,
        timeZone: TimeZone
    ) -> SnapshotDocument {
        let rendered = render(frozen: frozen, redaction: redaction, calendar: calendar, timeZone: timeZone)
        let lines = rendered.lines
        return SnapshotDocument(
            previewText: lines.joined(separator: "\n"),
            html: html(lines: lines, processes: rendered.processes),
            markdown: markdown(lines: lines),
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
        redaction: SnapshotRedaction,
        calendar: Calendar,
        timeZone: TimeZone
    ) -> Rendered {
        let captured = format(frozen.capturedAt, calendar: calendar, timeZone: timeZone, pattern: "yyyy-MM-dd HH:mm:ss")
        let saved = format(frozen.savedAt, calendar: calendar, timeZone: timeZone, pattern: "yyyy-MM-dd HH:mm:ss")
        let stamp = format(frozen.savedAt, calendar: calendar, timeZone: timeZone, pattern: "yyyyMMdd-HHmmss")
        let included = includedProcesses(frozen)
        var lines = [SnapshotExportCopy.htmlTitle]
        if let note = SnapshotRedaction.disclosure(included: included, frozen: frozen, redaction: redaction) {
            lines.append(note)
        }
        lines.append(contentsOf: [
            SnapshotExportCopy.notLive,
            "采样时间：\(captured)",
            "快照生成时间：\(saved)",
            SnapshotExportCopy.rateExplanation,
        ])
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
        ])
        if !redaction.hidesHostname, let hostname = frozen.hostname {
            lines.append(field("主机名", hostname))
        }
        if !redaction.hidesIPAddress, let ipAddress = frozen.ipAddress {
            lines.append(field("IP", ipAddress))
        }
        lines.append(SnapshotExportCopy.rankExplanation)
        let processes = renderedProcesses(included, redaction: redaction)
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

    private static func includedProcesses(_ frozen: SnapshotExport) -> [SnapshotExport.Process] {
        guard !frozen.processListFailed else { return [] }
        let ranked = frozen.processes.sorted { lhs, rhs in
            if lhs.memoryBytes != rhs.memoryBytes {
                return lhs.memoryBytes > rhs.memoryBytes
            }
            return lhs.pid < rhs.pid
        }
        return Array(ranked.prefix(5))
    }

    private static func renderedProcesses(
        _ included: [SnapshotExport.Process],
        redaction: SnapshotRedaction
    ) -> [RenderedProcess] {
        included.map { process in
            let name = redaction.hidesProcessName ? SnapshotExportCopy.hiddenName : process.name
            let memory = ByteFormat.memory(process.memoryBytes)
            let source = memorySourceText(process.memorySource)
            let cpu = cpuText(process.cpuPercent)
            let threads = String(process.threadCount)
            var cells = [String(process.pid), name, memory, source, cpu, threads]
            var line = "\(process.pid) · \(name) · \(memory) · \(source) · \(cpu) · \(threads)"
            if !redaction.hidesUsernamePath,
               let path = process.executablePath,
               SnapshotRedaction.containsUsername(path) {
                cells.append(path)
                line += " · \(path)"
            }
            return RenderedProcess(line: line, cells: cells)
        }
    }

    private static func markdown(lines: [String]) -> String {
        guard let title = lines.first else { return "" }
        return (["# \(title)"] + lines.dropFirst().map { String($0) }).joined(separator: "\n\n")
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
            let width = processes.map(\.cells.count).max() ?? 0
            let headings = ["PID", "名称", "内存", "内存来源", "CPU", "线程", "路径"].prefix(width)
            parts.append("<h2>进程</h2><table><thead><tr>")
            for heading in headings {
                parts.append("<th>\(heading)</th>")
            }
            parts.append("</tr></thead><tbody>")
            for process in processes {
                parts.append("<tr>")
                for cell in process.cells {
                    parts.append("<td>\(SnapshotHTMLEscape.text(cell))</td>")
                }
                if process.cells.count < width {
                    for _ in process.cells.count..<width {
                        parts.append("<td></td>")
                    }
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
