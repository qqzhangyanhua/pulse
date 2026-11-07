import XCTest

/// Reader, sampler, and sidebar stay on the agreed seams.
/// Linux reads source text. A pass is not a Mac sample and not a sidebar click.
final class ProcessMemoryChoiceWiringSourceTests: XCTestCase {
    func testChoiceStaysDarwinFreeAndIsABuildMember() throws {
        let choice = try repoText("Pulse/Models/ProcessMemoryChoice.swift")
        XCTAssertTrue(choice.contains("import Foundation"))
        XCTAssertFalse(choice.contains("import Darwin"))
        XCTAssertFalse(choice.contains("import AppKit"))
        XCTAssertFalse(choice.contains("import SwiftUI"))

        let package = try repoText("Package.swift")
        XCTAssertTrue(package.contains("\"Models/ProcessMemoryChoice.swift\""))
        let project = try repoText("Pulse.xcodeproj/project.pbxproj")
        XCTAssertTrue(project.contains("ProcessMemoryChoice.swift in Sources"))
        XCTAssertTrue(project.contains("path = ProcessMemoryChoice.swift;"))
    }

    func testReaderPassesBothReadingsAndSamplerChoosesTheRow() throws {
        let reader = try repoText("Pulse/Sampling/ProcessEnumerator.swift")
        XCTAssertFalse(reader.contains("ProcessMemoryChoice"))
        XCTAssertFalse(reader.contains("memoryBytes: info.pti_resident_size"))
        XCTAssertTrue(reader.contains("residentBytes: info.pti_resident_size"))
        XCTAssertTrue(reader.contains("ri_phys_footprint"))
        XCTAssertEqual(occurrenceCount(of: "pulse_proc_pid_rusage(", in: reader), 2)

        let sampler = try repoText("Pulse/Sampling/MemorySampler.swift")
        XCTAssertTrue(sampler.contains("ProcessMemoryChoice.project("))
        XCTAssertTrue(sampler.contains("footprint: raw.footprintBytes"))
        XCTAssertTrue(sampler.contains("resident: raw.residentBytes"))
        XCTAssertTrue(sampler.contains("memoryBytes: memory.bytes"))
        XCTAssertTrue(sampler.contains("memorySource: memory.source"))
        XCTAssertFalse(sampler.contains("memoryBytes: raw."))
        XCTAssertEqual(occurrenceCount(of: "proc_pid_rusage", in: sampler), 0)
        XCTAssertFalse(sampler.contains("Timer("))
        XCTAssertTrue(sampler.contains("append(Double(row.memoryBytes)"))

        let sidebar = try WiringSourceText.text(for: "ProcessDetailSidebar")
        let memoryField = try functionBody(named: "memoryField", in: sidebar)
        XCTAssertTrue(memoryField.contains("part: row.memoryBytes"))
        XCTAssertTrue(memoryField.contains("source: row.memorySource"))
        let metrics = try functionBody(named: "metrics", in: sidebar)
        XCTAssertTrue(metrics.contains("ByteFormat.memory(detail.row.memoryBytes)"))
        let chart = try functionBody(named: "memoryChart", in: sidebar)
        XCTAssertTrue(chart.contains("detail.memorySeries"))
        XCTAssertTrue(chart.contains("memoryField(detail.row).title"))
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
        let patterns = ["func \(name)(", "private func \(name)("]
        for pattern in patterns {
            guard let range = source.range(of: pattern),
                  let brace = source[range.lowerBound...].firstIndex(of: "{")
            else { continue }
            return try balancedSlice(from: brace, in: source, label: name)
        }
        throw SourceReadError.missing(name)
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
        throw SourceReadError.missing("balanced brace for \(label)")
    }

    private func occurrenceCount(of needle: String, in haystack: String) -> Int {
        haystack.components(separatedBy: needle).count - 1
    }
}

private enum SourceReadError: Error, CustomStringConvertible {
    case missing(String)
    var description: String {
        switch self {
        case .missing(let detail): return "missing \(detail)"
        }
    }
}
