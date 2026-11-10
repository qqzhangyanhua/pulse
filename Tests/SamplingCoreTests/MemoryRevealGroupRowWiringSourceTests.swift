import XCTest

/// Source order for the ordinary reveal. Linux reads text.
/// A pass is not a Mac scroll, not List retention, and not VoiceOver.
final class MemoryRevealGroupRowWiringSourceTests: XCTestCase {
    func testRevealCapturesTheGroupIdBeforeTheExistingAsyncScroll() throws {
        let pane = try repoText("Pulse/Views/ProcessTablePane.swift")
        let list = try functionBody(named: "processList", in: pane)
        XCTAssertEqual(occurrenceCount(of: "revealProcessListTarget(proxy)", in: list), 2)
        XCTAssertTrue(list.contains(".onAppear { revealProcessListTarget(proxy) }"))
        XCTAssertTrue(list.contains(".onChange(of: vm.processListScrollTarget)"))
        XCTAssertTrue(list.contains("revealTopApp(request: request, proxy: proxy)"))

        let reveal = try functionBody(named: "revealProcessListTarget", in: pane)
        let gate = try index(of: "guard let target = vm.processListScrollTarget else { return }", in: reveal)
        let mapped = try index(of: "MemoryRevealGroupRow.target(", in: reveal)
        let async = try index(of: "DispatchQueue.main.async", in: reveal)
        let scroll = try index(of: "proxy.scrollTo(revealed, anchor: .center)", in: reveal)
        XCTAssertLessThan(gate, mapped)
        XCTAssertLessThan(mapped, async)
        XCTAssertLessThan(async, scroll)
        XCTAssertTrue(reveal.contains("if self.reduceMotion"))
        XCTAssertTrue(reveal.contains("withAnimation(.easeInOut(duration: 0.28), move)"))
        XCTAssertFalse(reveal.contains("selectedPid ="))

        let top = try functionBody(named: "revealTopApp", in: pane)
        XCTAssertTrue(top.contains("TopCardRevealTarget.scrollID("))
        XCTAssertTrue(top.contains("sortedRows: vm.sortedRows"))
        XCTAssertTrue(top.contains("proxy.scrollTo(scrollID, anchor: .center)"))
        XCTAssertFalse(top.contains("MemoryRevealGroupRow"))
        XCTAssertFalse(top.contains("revealProcessListTarget"))

        let background = try functionBody(named: "rowBackground", in: pane)
        XCTAssertTrue(background.contains("duration: 0.16"))

        let vm = try repoText("Pulse/ViewModels/MemoryDashboardVM.swift")
        let scrollTarget = try functionBody(named: "processListScrollTarget", in: vm)
        XCTAssertTrue(scrollTarget.contains("ProcessSelection.scrollTarget(selectedPid: selectedPid, rows: rows)"))
        XCTAssertFalse(scrollTarget.contains("MemoryRevealGroupRow"))
        let apply = try functionBody(named: "applySample", in: vm)
        XCTAssertFalse(apply.contains("setSelectedPid"))

        let model = try repoText("Pulse/Models/MemoryRevealGroupRow.swift")
        XCTAssertTrue(model.contains("MemoryMagnitudeVisibleGroup.row("))
        XCTAssertFalse(model.contains("setSelectedPid"))
        XCTAssertFalse(model.contains("DispatchQueue"))
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
        let patterns = ["func \(name)(", "private func \(name)(", "var \(name):"]
        for pattern in patterns {
            guard let range = source.range(of: pattern),
                  let brace = source[range.lowerBound...].firstIndex(of: "{")
            else { continue }
            return try balancedSlice(from: brace, in: source, label: name)
        }
        throw RevealSourceError.missing(name)
    }

    private func index(of needle: String, in source: String) throws -> String.Index {
        guard let found = source.range(of: needle)?.lowerBound else {
            throw RevealSourceError.missing(needle)
        }
        return found
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
        throw RevealSourceError.missing("balanced brace for \(label)")
    }

    private func occurrenceCount(of needle: String, in haystack: String) -> Int {
        haystack.components(separatedBy: needle).count - 1
    }
}

private enum RevealSourceError: Error, CustomStringConvertible {
    case missing(String)
    var description: String {
        switch self {
        case .missing(let detail): return "missing \(detail)"
        }
    }
}
