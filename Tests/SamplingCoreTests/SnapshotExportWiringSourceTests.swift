import XCTest
@testable import SamplingCore

/// 源码接线，不是 SwiftUI，也不是 VoiceOver 或系统保存面板。
/// 通过只说明冻结函数不采样、按钮不进过滤组、预览和文件共用文档、
/// 预览没有退出或打开文件，「已保存」只出现在成功分支。
final class SnapshotExportWiringSourceTests: XCTestCase {
    func testPackageListsExportModelsAndKeepsTheAppTargetOut() throws {
        let package = try repoText("Package.swift")
        XCTAssertEqual(occurrenceCount(of: "\"Models/SnapshotExport.swift\"", in: package), 1)
        XCTAssertEqual(occurrenceCount(of: "\"Models/SnapshotExportFile.swift\"", in: package), 1)
        XCTAssertTrue(package.contains("\"ViewModels\""))
        XCTAssertTrue(package.contains("\"Views\""))
        XCTAssertFalse(package.contains("SnapshotExportPreview.swift"))
        XCTAssertFalse(package.contains("MemoryDashboardVM+SnapshotExport.swift"))
    }

    func testProjectRegistersTheFourExportFiles() throws {
        let project = try repoText("Pulse.xcodeproj/project.pbxproj")
        let build = try markedSection("PBXBuildFile", in: project)
        let refs = try markedSection("PBXFileReference", in: project)
        let sources = try markedSection("PBXSourcesBuildPhase", in: project)
        let models = try group("Models", path: "path = Models;", in: project)
        let viewModels = try group("ViewModels", path: "path = ViewModels;", in: project)
        let views = try group("Views", path: "path = Views;", in: project)
        for name in ["SnapshotExport.swift", "SnapshotExportFile.swift"] {
            XCTAssertTrue(build.contains(name), name)
            XCTAssertTrue(refs.contains(name), name)
            XCTAssertTrue(sources.contains(name), name)
            XCTAssertTrue(models.contains(name), name)
        }
        XCTAssertTrue(build.contains("MemoryDashboardVM+SnapshotExport.swift"))
        XCTAssertTrue(refs.contains("MemoryDashboardVM+SnapshotExport.swift"))
        XCTAssertTrue(sources.contains("MemoryDashboardVM+SnapshotExport.swift"))
        XCTAssertTrue(viewModels.contains("MemoryDashboardVM+SnapshotExport.swift"))
        XCTAssertTrue(build.contains("SnapshotExportPreview.swift"))
        XCTAssertTrue(refs.contains("SnapshotExportPreview.swift"))
        XCTAssertTrue(sources.contains("SnapshotExportPreview.swift"))
        XCTAssertTrue(views.contains("SnapshotExportPreview.swift"))
    }

    func testFreezeCopiesThePublishedFrameAndDoesNotSample() throws {
        let source = try WiringSourceText.text(for: "MemoryDashboardVM")
        XCTAssertEqual(occurrenceCount(of: "@Published", in: source), 18, "battery card adds energyBatteryCard; energy page adds energyWindowRates; hour ranking adds energyRankingSpan and energyHourRates; energy history adds energyMachineHistory; exited hour ranking adds exitedEnergyProcesses; thermal advice adds thermalAdvice; GPU page adds gpuPage; connection card adds hostConnection; Wi-Fi signal adds hostWiFi; public IP adds publicIPRequest; SSID permission adds ssidPermission; chip temperature adds chipTemperature")
        XCTAssertEqual(occurrenceCount(of: "didSet", in: source), 4)
        XCTAssertEqual(occurrenceCount(of: "@MainActor", in: source), 1)
        let body = try functionBody(named: "requestSaveCurrentSnapshot", in: source)
        for local in [
            "let snapshot = snapshot",
            "let rows = rows",
            "let systemCpuPercent = systemCpuPercent",
            "let busiestCorePercent = busiestCorePercent",
            "let hostNetworkRates = hostNetworkRates",
            "let hostDiskRates = hostDiskRates",
            "let samplingFailed = samplingFailed",
            "let processListFailed = processListFailed",
        ] {
            let localAt = try index(of: local, in: body)
            let freezeAt = try index(of: "SnapshotExport.freeze", in: body)
            XCTAssertLessThan(localAt, freezeAt, local)
        }
        XCTAssertTrue(body.contains("rows: rows"))
        XCTAssertTrue(body.contains("savedAt: savedAt"))
        XCTAssertFalse(body.contains("await"))
        XCTAssertFalse(body.contains("Date("))
        for forbidden in [
            "sample()",
            "HostMachineReader",
            "ProcessEnumerator",
            "WindowedAppLookup",
            "sortedRows",
            "visibleRows",
            "AppGroupProjection",
            "TopConsumer",
            "MenuBarPopoverSnapshot",
            "MemoryGrowthSignal",
            "thermalNotice",
            "machineFacts",
            "topMemorySeries",
        ] {
            XCTAssertFalse(body.contains(forbidden), forbidden)
        }
    }

    func testSaveButtonStaysOutsideTheFilterGroupAndTheMachinePageBranch() throws {
        let dashboard = try repoText("Pulse/Views/MemoryDashboardView.swift")
        XCTAssertTrue(dashboard.contains("保存当前快照"))
        let group = try braceBody(after: "ToolbarItemGroup(placement: .primaryAction)", in: dashboard)
        XCTAssertFalse(group.contains("保存当前快照"))
        let fullPageBranch = try braceBody(after: "if !vm.selectedPage.isFullPage", in: dashboard)
        XCTAssertFalse(fullPageBranch.contains("保存当前快照"))
        XCTAssertTrue(dashboard.contains("requestSaveCurrentSnapshot(savedAt:"))
        XCTAssertTrue(dashboard.contains("Date()"))
        let request = try functionBody(named: "requestSaveCurrentSnapshot", in: try WiringSourceText.text(for: "MemoryDashboardVM"))
        XCTAssertFalse(request.contains("Date()"))
    }

    func testPreviewAndFileShareTheDocumentAndDoNotQuitOrOpen() throws {
        let preview = try repoText("Pulse/Views/SnapshotExportPreview.swift")
        XCTAssertTrue(preview.contains("Text(document.previewText)"))
        XCTAssertTrue(preview.contains("document.suggestedFilename"))
        XCTAssertTrue(preview.contains("NSSavePanel"))
        XCTAssertTrue(preview.contains(".html"))
        XCTAssertTrue(preview.contains("隐藏进程名"))
        XCTAssertTrue(preview.contains("\"开\""))
        XCTAssertTrue(preview.contains("\"关\""))
        XCTAssertFalse(preview.contains("ByteFormat"))
        XCTAssertFalse(preview.contains("CPUPercentText"))
        XCTAssertFalse(preview.contains("NetworkRateText"))
        XCTAssertFalse(preview.contains("row.name"))
        XCTAssertFalse(preview.contains("quitSelected"))
        XCTAssertFalse(preview.contains("forceTerminate"))
        XCTAssertFalse(preview.contains("selectPidIfPresent"))
        XCTAssertFalse(preview.contains("NSWorkspace"))
        XCTAssertFalse(preview.contains("已保存"))
        XCTAssertFalse(preview.contains("sample()"))
        let panel = try functionBody(named: "presentSavePanel", in: preview)
        let beginAt = try index(of: "store.beginSavePanel()", in: panel)
        let panelAt = try index(of: "NSSavePanel()", in: panel)
        XCTAssertLessThan(beginAt, panelAt)
        let receiveAt = try index(of: "store.receiveSavePanel(attempt, confirmed: confirmed)", in: panel)
        let commitAt = try index(of: "SnapshotExportFile.commit(html: html, to: url)", in: panel)
        let successAt = try index(of: "store.finishSavePanel(attempt, succeeded: true)", in: panel)
        XCTAssertLessThan(receiveAt, commitAt)
        XCTAssertLessThan(commitAt, successAt)
        XCTAssertTrue(panel.contains("case .write(let html):"))
        XCTAssertTrue(panel.contains("store.finishSavePanel(attempt, succeeded: false)"))
        let ignored = try between("case .ignore, .cancelled:", "case .write(let html):", in: panel)
        XCTAssertFalse(ignored.contains("SnapshotExportFile.commit"))
        XCTAssertFalse(ignored.contains("finishSavePanel"))
        let callback = try between("panel.begin", "\n    }", in: panel)
        XCTAssertFalse(callback.contains("store.session?.document"))
        XCTAssertFalse(callback.contains("noteSnapshotExportWriteSucceeded"))
        XCTAssertFalse(callback.contains("noteSnapshotExportWriteFailed"))
        XCTAssertFalse(callback.contains("noteSnapshotExportCancelledPanel"))
        let model = try repoText("Pulse/Models/SnapshotExport.swift")
        XCTAssertEqual(occurrenceCount(of: "已保存", in: model), 1)
        let failed = try between("case .writeFailed:", "case .saved:", in: model)
        XCTAssertFalse(failed.contains("已保存"))
        let saved = try between("case .saved:", "\n    }", in: model)
        XCTAssertTrue(saved.contains("已保存"))
    }

    private func repoText(_ relative: String) throws -> String {
        try String(contentsOf: repoRoot().appendingPathComponent(relative), encoding: .utf8)
    }

    private func repoRoot() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private func functionBody(named name: String, in source: String) throws -> String {
        let patterns = ["func \(name)(", "func \(name)()", "private func \(name)(", "var \(name):"]
        for pattern in patterns {
            guard let range = source.range(of: pattern),
                  let brace = source[range.lowerBound...].firstIndex(of: "{")
            else { continue }
            return try balancedSlice(from: brace, in: source, label: name)
        }
        throw SourceSliceError.missing("declaration for \(name)")
    }

    private func braceBody(after needle: String, in source: String) throws -> String {
        guard let range = source.range(of: needle),
              let brace = source[range.upperBound...].firstIndex(of: "{")
        else {
            throw SourceSliceError.missing(needle)
        }
        return try balancedSlice(from: brace, in: source, label: needle)
    }

    private func between(_ start: String, _ end: String, in source: String) throws -> String {
        guard let from = source.range(of: start)?.upperBound,
              let to = source.range(of: end, range: from..<source.endIndex)?.lowerBound
        else {
            throw SourceSliceError.missing("\(start) .. \(end)")
        }
        return String(source[from..<to])
    }

    private func markedSection(_ name: String, in source: String) throws -> String {
        let begin = "/* Begin \(name) section */"
        let end = "/* End \(name) section */"
        guard let start = source.range(of: begin)?.upperBound,
              let stop = source.range(of: end)?.lowerBound,
              start < stop
        else {
            throw SourceSliceError.missing(name)
        }
        return String(source[start..<stop])
    }

    private func group(_ name: String, path: String, in source: String) throws -> String {
        guard let start = source.range(of: "/* \(name) */")?.lowerBound,
              let stop = source.range(of: path, range: start..<source.endIndex)?.upperBound
        else {
            throw SourceSliceError.missing(name)
        }
        return String(source[start..<stop])
    }

    private func index(of needle: String, in source: String) throws -> String.Index {
        guard let found = source.range(of: needle)?.lowerBound else {
            throw SourceSliceError.missing(needle)
        }
        return found
    }

    private func balancedSlice(from start: String.Index, in source: String, label: String) throws -> String {
        let opener = source[start]
        let closer: Character = opener == "(" ? ")" : "}"
        var depth = 0
        var cursor = start
        while cursor < source.endIndex {
            let character = source[cursor]
            if character == opener { depth += 1 }
            if character == closer {
                depth -= 1
                if depth == 0 {
                    return String(source[start...cursor])
                }
            }
            cursor = source.index(after: cursor)
        }
        throw SourceSliceError.missing("balanced \(opener) for \(label)")
    }

    private func occurrenceCount(of needle: String, in haystack: String) -> Int {
        haystack.components(separatedBy: needle).count - 1
    }
}

private enum SourceSliceError: Error, CustomStringConvertible {
    case missing(String)

    var description: String {
        switch self {
        case .missing(let detail):
            return "missing \(detail)"
        }
    }
}
