import XCTest

/// Source contract that the row background and ink share one highlight decision.
/// Linux reads text. A pass is not a painted row, not List retention, and not VoiceOver.
final class MemoryGroupRowHighlightWiringSourceTests: XCTestCase {
    func testBackgroundAndInkShareTheVisibleGroupDecision() throws {
        let pane = try repoText("Pulse/Views/ProcessTablePane.swift")
        let list = try functionBody(named: "processList", in: pane)
        XCTAssertEqual(occurrenceCount(of: "MemoryGroupRowHighlight.highlighted(", in: list), 1)
        XCTAssertTrue(list.contains("selected: groupHighlighted"))
        XCTAssertTrue(list.contains("rowBackground(groupHighlighted)"))
        XCTAssertTrue(list.contains("List(vm.sortedRows, selection: Binding(get: { vm.selectedPid }, set: { vm.select(pid: $0) }))"))
        XCTAssertFalse(list.contains("vm.selectedPid == row.pid"))
        XCTAssertFalse(list.contains("accessibilityAddTraits"))

        let label = try functionBody(named: "accessibilityLabel", in: pane)
        XCTAssertFalse(label.contains("selected"))
        XCTAssertFalse(pane.contains("accessibilityAddTraits"))

        let app = try repoText("Pulse/PulseApp.swift")
        let copy = try functionBody(named: "copySelectedProcessRow", in: app)
        XCTAssertFalse(copy.contains("selectedPid ="))
        XCTAssertTrue(copy.contains("MemoryGroupRowCopy.row("))
        XCTAssertTrue(pane.contains("ProcessRowCopy.line(page: vm.selectedPage, row: row)"))

        let scroll = try functionBody(named: "processListScrollTarget", in: try repoText("Pulse/Models/DashboardCore+Selection.swift"))
        XCTAssertTrue(scroll.contains("ProcessSelection.scrollTarget(selectedPid: selectedPid, rows: rows)"))
        let model = try repoText("Pulse/Models/MemoryGroupRowHighlight.swift")
        XCTAssertTrue(model.contains("MemoryMagnitudeVisibleGroup.row("))
        XCTAssertFalse(model.contains("setSelectedPid"))
        XCTAssertFalse(model.contains("applyGroupedByAppSelection"))
        XCTAssertFalse(model.contains("accessibilityAddTraits"))
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
        let patterns = ["func \(name)(", "private func \(name)(", "private var \(name):", "var \(name):"]
        for pattern in patterns {
            guard let range = source.range(of: pattern),
                  let brace = source[range.lowerBound...].firstIndex(of: "{")
            else { continue }
            return try balancedSlice(from: brace, in: source, label: name)
        }
        throw HighlightSourceError.missing(name)
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
        throw HighlightSourceError.missing("balanced brace for \(label)")
    }

    private func occurrenceCount(of needle: String, in haystack: String) -> Int {
        haystack.components(separatedBy: needle).count - 1
    }
}

private enum HighlightSourceError: Error, CustomStringConvertible {
    case missing(String)
    var description: String {
        switch self {
        case .missing(let detail): return "missing \(detail)"
        }
    }
}
