import XCTest

/// Source contract for the memory-page magnitude lookup.
/// Linux reads text. A pass is not a Mac click and not VoiceOver.
final class MemoryMagnitudeVisibleGroupWiringSourceTests: XCTestCase {
    func testModelIsPortableAndDoesNotWriteSelection() throws {
        let source = try repoText("Pulse/Models/MemoryMagnitudeVisibleGroup.swift")
        XCTAssertTrue(source.contains("enum MemoryMagnitudeVisibleGroup"))
        XCTAssertTrue(source.contains("AppGroupProjection.combine"))
        XCTAssertFalse(source.contains("setSelectedPid"))
        XCTAssertFalse(source.contains("MemorySampler"))
        XCTAssertFalse(source.contains("import SwiftUI"))
        XCTAssertFalse(source.contains("import Darwin"))
        XCTAssertFalse(source.contains("import AppKit"))
        let package = try repoText("Package.swift")
        XCTAssertTrue(package.contains("\"Models/MemoryMagnitudeVisibleGroup.swift\""))
        let project = try repoText("Pulse.xcodeproj/project.pbxproj")
        XCTAssertTrue(project.contains("MemoryMagnitudeVisibleGroup.swift in Sources"))
        XCTAssertTrue(project.contains("path = MemoryMagnitudeVisibleGroup.swift;"))
    }

    func testMemoryMagnitudeUsesTheVisibleGroupAndOtherPagesDoNot() throws {
        let sidebar = try WiringSourceText.text(for: "ProcessDetailSidebar")
        let metrics = try functionBody(named: "metrics", in: sidebar)
        XCTAssertTrue(metrics.contains("memoryMagnitudeRow(fallback: displayedMemoryRow(detail.row))"))
        XCTAssertTrue(metrics.contains("ByteFormat.memory(row.memoryBytes)"))
        XCTAssertTrue(metrics.contains("memoryMagnitudeAttribution("))
        XCTAssertTrue(metrics.contains("curve: detail.row"))
        XCTAssertFalse(metrics.contains("ByteFormat.cpu(row.cpuPercent)"))

        let lookup = try functionBody(named: "memoryMagnitudeRow", in: sidebar)
        XCTAssertTrue(lookup.contains("MemoryMagnitudeVisibleGroup.row("))
        XCTAssertTrue(lookup.contains("page: vm.selectedPage"))
        XCTAssertTrue(lookup.contains("grouping: vm.groupedByApp && AppGroupChrome.applies(on: vm.selectedPage)"))
        XCTAssertTrue(lookup.contains("selectedPid: vm.selectedPid"))
        XCTAssertTrue(lookup.contains("visibleUngrouped: vm.visibleRows"))
        XCTAssertTrue(lookup.contains("return fallback"))

        let displayed = try functionBody(named: "displayedMemoryRow", in: sidebar)
        XCTAssertTrue(displayed.contains("vm.sortedRows.first { $0.pid == row.pid }"))
        XCTAssertFalse(displayed.contains("MemoryMagnitudeVisibleGroup"))

        let chart = try functionBody(named: "memoryChart", in: sidebar)
        XCTAssertTrue(chart.contains("curveRow: detail.row"))
        XCTAssertTrue(chart.contains("curvePid: detail.row.pid"))
        XCTAssertTrue(chart.contains("samples: detail.memorySeries"))
        XCTAssertFalse(chart.contains("MemoryMagnitudeVisibleGroup"))

        let cpu = try functionBody(named: "cpuResourceDetail", in: sidebar)
        XCTAssertFalse(cpu.contains("MemoryMagnitudeVisibleGroup"))
        XCTAssertFalse(cpu.contains("memoryMagnitudeRow"))

        let projection = try functionBody(named: "displayedProjection", in: sidebar)
        XCTAssertTrue(projection.contains("displayedMemoryRow(detail.row)"))
        XCTAssertFalse(projection.contains("MemoryMagnitudeVisibleGroup"))

        let quit = try repoText("Pulse/Models/ProcessQuitSession.swift")
        let force = try functionBody(named: "requestForce", in: quit)
        XCTAssertTrue(force.contains("rows.first(where: { $0.pid == pid })?.name"))

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
        throw VisibleGroupSourceError.missing(name)
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
        throw VisibleGroupSourceError.missing("balanced brace for \(label)")
    }
}

private enum VisibleGroupSourceError: Error, CustomStringConvertible {
    case missing(String)
    var description: String {
        switch self {
        case .missing(let detail): return "missing \(detail)"
        }
    }
}
