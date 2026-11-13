import XCTest
@testable import SamplingCore

/// ⌘C and the row context menu call `ProcessRowCopy`. No selection does not touch the pasteboard.
final class ProcessRowCopyWiringSourceTests: XCTestCase {
    func testCommandCopiesTheSelectedRowAndSkipsAnEmptySelection() throws {
        let app = try repoText("Pulse/PulseApp.swift")
        XCTAssertTrue(app.contains("CommandGroup(replacing: .pasteboard)"))

        let command = try functionBody(named: "copyProcessRowCommand", in: app)
        let focused = try braceBody(after: "if nameFilterFocused == true", in: command)
        XCTAssertFalse(focused.contains("keyboardShortcut"))
        XCTAssertFalse(focused.contains("NSPasteboard"))
        let idle = try braceBody(after: "} else", in: command)
        XCTAssertTrue(idle.contains(".keyboardShortcut(\"c\", modifiers: .command)"))
        XCTAssertTrue(app.contains(".disabled(copyProcessRowDisabled)"))
        let disabled = try functionBody(named: "copyProcessRowDisabled", in: app)
        XCTAssertTrue(disabled.contains("nameFilterFocused != true && dashboard.selectedRow == nil"))

        let copy = try functionBody(named: "copySelectedProcessRow", in: app)
        XCTAssertEqual(occurrenceCount(of: "MemoryGroupRowCopy.row(", in: copy), 1)
        let guardAt = try index(of: "else { return }", in: copy)
        let boardAt = try index(of: "NSPasteboard", in: copy)
        XCTAssertLessThan(guardAt, boardAt)
        XCTAssertTrue(copy.contains("EnergyPage.display("))
        XCTAssertTrue(copy.contains("windowRates: dashboard.activeEnergyRates"))
        XCTAssertTrue(copy.contains("dashboard.groupedByApp && AppGroupChrome.applies(on: dashboard.selectedPage)"))
        XCTAssertTrue(copy.contains("energyWindow: reading?.rates"))
        XCTAssertFalse(copy.contains("energyWindowRates[row.pid]"))
        let skippedPage = try index(of: "case .machine, .gpu:", in: copy)
        XCTAssertLessThan(skippedPage, boardAt)
        let between = String(copy[skippedPage..<boardAt])
        XCTAssertTrue(between.contains("return"))
        XCTAssertFalse(between.contains("NSPasteboard"))
        XCTAssertFalse(between.contains("ProcessRowCopy"))

        let focusedCopy = try braceBody(after: "if nameFilterFocused == true", in: copy)
        XCTAssertFalse(focusedCopy.contains("NSPasteboard"))
        XCTAssertFalse(focusedCopy.contains("ProcessRowCopy"))

        let pane = try repoText("Pulse/Views/ProcessTablePane.swift")
        XCTAssertEqual(occurrenceCount(of: "Button(\"复制\")", in: pane), 1)
        let menu = try braceBody(after: ".contextMenu", in: pane)
        XCTAssertTrue(menu.contains("Button(\"复制\")"))
        XCTAssertTrue(menu.contains("ProcessRowCopy.line(page: vm.selectedPage, row: row)"))
        XCTAssertTrue(menu.contains("NSPasteboard"))

        let vm = try repoText("Pulse/ViewModels/MemoryDashboardVM.swift")
        let selected = try functionBody(named: "selectedRow", in: vm)
        let shown = try index(of: "sortedRows.first", in: selected)
        let raw = try index(of: "rows.first", in: selected)
        XCTAssertLessThan(shown, raw)
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
        throw SourceSliceError.missing(name)
    }

    private func braceBody(after needle: String, in source: String) throws -> String {
        guard let start = source.range(of: needle)?.upperBound,
              let brace = source[start...].firstIndex(of: "{")
        else { throw SourceSliceError.missing(needle) }
        return try balancedSlice(from: brace, in: source, label: needle)
    }

    private func index(of needle: String, in source: String) throws -> String.Index {
        guard let found = source.range(of: needle)?.lowerBound else {
            throw SourceSliceError.missing(needle)
        }
        return found
    }

    private func balancedSlice(from start: String.Index, in source: String, label: String) throws -> String {
        var depth = 0
        var index = start
        while index < source.endIndex {
            let character = source[index]
            if character == "{" { depth += 1 }
            if character == "}" {
                depth -= 1
                if depth == 0 { return String(source[start...index]) }
            }
            index = source.index(after: index)
        }
        throw SourceSliceError.missing("balanced brace for \(label)")
    }

    private func occurrenceCount(of needle: String, in haystack: String) -> Int {
        haystack.components(separatedBy: needle).count - 1
    }
}

private enum SourceSliceError: Error, CustomStringConvertible {
    case missing(String)
    var description: String {
        switch self {
        case .missing(let detail): return "missing \(detail)"
        }
    }
}
