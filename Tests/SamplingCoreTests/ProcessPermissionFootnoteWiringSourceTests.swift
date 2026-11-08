import XCTest

/// Source read for the permission footnote. Not a GUI test and not a live process list.
final class ProcessPermissionFootnoteWiringSourceTests: XCTestCase {
    func testFootnoteStaysPortableAndIsABuildMember() throws {
        let footnote = try repoText("Pulse/Models/ProcessPermissionFootnote.swift")
        XCTAssertTrue(footnote.contains("import Foundation"))
        XCTAssertFalse(footnote.contains("import Darwin"))
        XCTAssertFalse(footnote.contains("import AppKit"))
        XCTAssertFalse(footnote.contains("import IOKit"))
        XCTAssertFalse(footnote.contains("import SwiftUI"))

        let package = try repoText("Package.swift")
        XCTAssertTrue(package.contains("\"Models/ProcessPermissionFootnote.swift\""))
        XCTAssertFalse(package.contains("ProcessPermissionFootnoteLabel.swift"))
        let project = try repoText("Pulse.xcodeproj/project.pbxproj")
        XCTAssertTrue(project.contains("ProcessPermissionFootnote.swift in Sources"))
        XCTAssertTrue(project.contains("path = ProcessPermissionFootnote.swift;"))
        XCTAssertTrue(project.contains("ProcessPermissionFootnoteLabel.swift in Sources"))
        XCTAssertTrue(project.contains("path = ProcessPermissionFootnoteLabel.swift;"))
    }

    func testWalkCountsOnlyEPERMAndDoesNotAddRows() throws {
        let reader = try repoText("Pulse/Sampling/ProcessEnumerator.swift")
        let raw = try structBody(named: "RawProcessSample", in: reader)
        XCTAssertFalse(raw.contains("permission"))
        XCTAssertFalse(raw.contains("errno"))

        let list = try functionBody(named: "list", in: reader)
        XCTAssertEqual(occurrenceCount(of: "readMachTimebase()", in: list), 1)
        XCTAssertTrue(list.contains("var permissionDeniedCount = 0"))
        XCTAssertFalse(list.contains("static var"))
        XCTAssertTrue(list.contains("guard pid > 0 else { continue }"))
        XCTAssertTrue(list.contains("if let sample = inspected.sample"))
        XCTAssertEqual(occurrenceCount(of: "samples.append(sample)", in: list), 1)
        XCTAssertTrue(list.contains("else if inspected.permissionDenied"))
        XCTAssertTrue(list.contains("permissionDeniedCount += 1"))
        XCTAssertTrue(list.contains("permissionDeniedCount: permissionDeniedCount"))

        let inspect = try functionBody(named: "inspect", in: reader)
        XCTAssertTrue(inspect.contains("errno = 0"))
        XCTAssertTrue(inspect.contains("if written != infoSize"))
        XCTAssertTrue(inspect.contains("taskInfoErrno = errno"))
        XCTAssertTrue(inspect.contains(
            "ProcessPermissionFootnote.countsTaskInfoFailure(errno: taskInfoErrno)"
        ))
        XCTAssertTrue(inspect.contains("sample: nil"))
        XCTAssertEqual(occurrenceCount(of: "RawProcessSample(", in: inspect), 1)
        XCTAssertFalse(inspect.contains("== EPERM"))
        XCTAssertFalse(inspect.contains("== ESRCH"))
        XCTAssertFalse(inspect.contains("mach_timebase_info("))
        XCTAssertFalse(inspect.contains("readMachTimebase("))
        XCTAssertTrue(inspect.contains("userTimeNs: cpu?.user"))
        XCTAssertTrue(inspect.contains("systemTimeNs: cpu?.system"))

        XCTAssertEqual(occurrenceCount(of: "pulse_proc_pid_rusage(", in: reader), 2)
        XCTAssertEqual(occurrenceCount(of: "MachTimebase.nanoseconds(", in: reader), 2)
        XCTAssertTrue(reader.contains("private static let rusageInfoV6: Int32 = 6"))
        XCTAssertFalse(reader.contains("rusageInfoV4"))
        XCTAssertTrue(reader.contains("ri_energy_nj"))
        XCTAssertTrue(reader.contains("ri_interrupt_wkups"))
        XCTAssertTrue(reader.contains("ri_phys_footprint"))
        XCTAssertTrue(reader.contains("ri_diskio_bytesread"))
        XCTAssertTrue(reader.contains("ri_diskio_byteswritten"))
    }

    func testFramePublishesTheSentenceAndLeavesProcessRowsAlone() throws {
        let models = try repoText("Pulse/Models/MemoryModels.swift")
        let row = try structBody(named: "ProcessRow", in: models)
        XCTAssertFalse(row.contains("permission"))
        XCTAssertFalse(row.contains("deniedCount"))
        XCTAssertTrue(models.contains("let permissionFootnote: String?"))

        let sampler = try repoText("Pulse/Sampling/MemorySampler.swift")
        XCTAssertEqual(occurrenceCount(of: "ProcessPermissionFootnote.published(", in: sampler), 2)
        XCTAssertTrue(sampler.contains("deniedCount: 0"))
        XCTAssertTrue(sampler.contains("processListFailed: true"))
        XCTAssertTrue(sampler.contains("deniedCount: listed.permissionDeniedCount"))
        XCTAssertTrue(sampler.contains("for raw in listed.samples"))
        XCTAssertFalse(sampler.contains("permissionDeniedCount +"))
        XCTAssertEqual(occurrenceCount(of: "rows.append(", in: sampler), 1)

        let vm = try repoText("Pulse/ViewModels/MemoryDashboardVM.swift")
        XCTAssertTrue(vm.contains("@Published private(set) var processPermissionFootnote: String?"))
        let apply = try functionBody(named: "applySample", in: vm)
        XCTAssertEqual(occurrenceCount(of: "processPermissionFootnote = frame.permissionFootnote", in: apply), 1)
        XCTAssertFalse(apply.contains("processPermissionFootnote = \"0\""))
        XCTAssertFalse(apply.contains("另有"))
    }

    func testTableDrawsTheSentenceUnderTheListAndKeepsMissingCells() throws {
        let pane = try repoText("Pulse/Views/ProcessTablePane.swift")
        let body = try slice(from: "var body: some View", until: "private var showsColumnHeader", in: pane)
        XCTAssertTrue(body.contains("tableBody"))
        XCTAssertTrue(body.contains("ProcessPermissionFootnoteLabel("))
        XCTAssertTrue(body.contains("sentence: vm.processPermissionFootnote"))
        XCTAssertTrue(body.contains("processListFailed: vm.processListFailed"))
        XCTAssertTrue(body.contains("showsProcessTable: showsReadyProcessList"))

        let list = try functionBody(named: "processList", in: pane)
        XCTAssertTrue(list.contains("List(vm.sortedRows"))
        XCTAssertFalse(list.contains("ProcessPermissionFootnote"))
        XCTAssertFalse(list.contains("另有"))
        XCTAssertTrue(pane.contains("ByteFormat.cpu(row.cpuPercent)"))
        XCTAssertTrue(pane.contains("ByteFormat.memory(row.memoryBytes)"))
        XCTAssertTrue(pane.contains("DiskRateText.string(row.diskReadBytesPerSecond)"))
        XCTAssertTrue(pane.contains("ProcessEnergyText.watts(row.energyWatts)"))

        let label = try repoText("Pulse/Views/ProcessPermissionFootnoteLabel.swift")
        XCTAssertTrue(label.contains("ProcessPermissionFootnote.visibleSentence("))
        XCTAssertTrue(label.contains("Text(text)"))
        XCTAssertFalse(label.contains("Text(\"0\")"))
        XCTAssertFalse(label.contains("另有 \\("))
        XCTAssertFalse(label.contains("import Darwin"))
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
        let patterns = ["func \(name)(", "private func \(name)(", "var \(name):", "private var \(name):"]
        for pattern in patterns {
            guard let range = source.range(of: pattern),
                  let brace = source[range.lowerBound...].firstIndex(of: "{")
            else { continue }
            return try balancedSlice(from: brace, in: source, label: name)
        }
        throw FootnoteWiringReadError.missing(name)
    }

    private func structBody(named name: String, in source: String) throws -> String {
        guard let range = source.range(of: "struct \(name)"),
              let brace = source[range.lowerBound...].firstIndex(of: "{")
        else {
            throw FootnoteWiringReadError.missing(name)
        }
        return try balancedSlice(from: brace, in: source, label: name)
    }

    private func slice(from start: String, until end: String, in source: String) throws -> String {
        guard let startRange = source.range(of: start),
              let endRange = source.range(of: end, range: startRange.upperBound..<source.endIndex)
        else {
            throw FootnoteWiringReadError.missing(start)
        }
        return String(source[startRange.lowerBound..<endRange.lowerBound])
    }

    private func balancedSlice(from start: String.Index, in source: String, label: String) throws -> String {
        var depth = 0
        var cursor = start
        while cursor < source.endIndex {
            let character = source[cursor]
            if character == "{" { depth += 1 }
            if character == "}" {
                depth -= 1
                if depth == 0 { return String(source[start...cursor]) }
            }
            cursor = source.index(after: cursor)
        }
        throw FootnoteWiringReadError.missing("balanced brace for \(label)")
    }

    private func occurrenceCount(of needle: String, in haystack: String) -> Int {
        haystack.components(separatedBy: needle).count - 1
    }
}

private enum FootnoteWiringReadError: Error, CustomStringConvertible {
    case missing(String)

    var description: String {
        switch self {
        case .missing(let detail): return "missing \(detail)"
        }
    }
}
