import XCTest
@testable import SamplingCore

/// Phase 15 step 2: static wiring contract for memory-page filter clears.
///
/// Linux SamplingCore does not compile `ViewModels/` or `Views/`. These tests
/// read source text only. They do not instantiate `MemoryDashboardVM`, do not
/// enter its `@MainActor` isolation, do not click a button, and do not run
/// SwiftUI, Xcode, or Sampler. A pass is not a same-turn GUI or selection test.
final class MemoryPageFilterClearWiringSourceTests: XCTestCase {
    func testClearMemoryPageFiltersIsTheOnlyMainActorMethodThatWritesBothFields() throws {
        let source = try vmSource()
        XCTAssertEqual(
            occurrenceCount(of: "@MainActor", in: source),
            1,
            "existing class isolation only; source contract, not a VM run"
        )
        XCTAssertTrue(source.contains("@MainActor\nfinal class MemoryDashboardVM: ObservableObject"))

        let classBody = try typeBody(named: "MemoryDashboardVM", keyword: "class", in: source)
        XCTAssertEqual(
            occurrenceCount(of: "func clearMemoryPageFilters(", in: classBody),
            1,
            "one clear method on the existing MainActor type"
        )
        XCTAssertFalse(classBody.contains("private func clearMemoryPageFilters"))
        XCTAssertFalse(classBody.contains("static func clearMemoryPageFilters"))
        XCTAssertEqual(occurrenceCount(of: "func clearMemoryPageFilters(", in: source), 1)

        let declaration = try lineContaining("func clearMemoryPageFilters(", in: source)
        XCTAssertEqual(declaration, "    func clearMemoryPageFilters() {")
        XCTAssertFalse(declaration.contains("async"), "the clear is synchronous source, not a sampled turn")
        XCTAssertFalse(declaration.contains("@MainActor"), "no second isolation annotation")

        let body = try functionBody(named: "clearMemoryPageFilters", in: source)
        XCTAssertEqual(
            statements(in: body),
            ["filter = \"\"", "risingOnlyFilter = false"],
            "direct writes of the two existing fields, even when already default; not a VM instance"
        )
    }

    func testClearMemoryPageFiltersOmitsSampleRetrySortSelectionAndStateWrites() throws {
        let source = try vmSource()
        let body = try functionBody(named: "clearMemoryPageFilters", in: source)
        let forbidden = [
            "sample()",
            "retrySampling()",
            "setTableSort",
            "setMemoryPageSort",
            "applyRisingOnlySelection",
            "onChange",
            "didSet",
            "rows",
            "navigation",
            "tableSort",
            "publication",
            "loadState",
            "topMemorySeries",
            "selectedPid",
            "@Published",
            "Task",
            "await",
            "filterPhase",
            "MemoryTablePhase",
        ]
        for token in forbidden {
            XCTAssertFalse(body.contains(token), "clear method must not contain \(token); source contract")
        }

        let filterLine = try lineContaining("var filter", in: source)
        XCTAssertEqual(filterLine, "    @Published var filter = \"\"")
        XCTAssertFalse(filterLine.contains("didSet"), "do not add didSet on filter")
        XCTAssertEqual(occurrenceCount(of: "didSet", in: source), 2, "no new didSet")
        XCTAssertFalse(source.contains("onChange"), "VM gains no onChange")
        XCTAssertEqual(
            occurrenceCount(of: "@Published", in: source),
            23,
            "topAppLocateReveal is the only added published property"
        )
        XCTAssertEqual(
            try lineContaining("var topAppLocateReveal", in: source).trimmingCharacters(in: .whitespaces),
            "@Published var topAppLocateReveal: TopAppLocation.Reveal?"
        )
        XCTAssertFalse(try lineContaining("var topAppLocateReveal", in: source).contains("didSet"))

        let risingObserver = try braceBody(after: "@Published var risingOnlyFilter", in: source)
        XCTAssertTrue(risingObserver.contains("didSet"))
        XCTAssertTrue(risingObserver.contains("guard oldValue != risingOnlyFilter else { return }"))
        XCTAssertTrue(
            risingObserver.contains("applyRisingOnlySelection()"),
            "existing OFF selectedPid path stays on risingOnlyFilter.didSet"
        )
        XCTAssertFalse(risingObserver.contains("filter ="))

        let selection = try functionBody(named: "applyRisingOnlySelection", in: source)
        XCTAssertTrue(selection.contains("MemoryGrowthRisingFilter.selectedPid"))
        XCTAssertEqual(occurrenceCount(of: "applyRisingOnlySelection()", in: body), 0)
    }

    func testMemoryFilterEmptiesShareFilterEmptyLinesAndTheSameClearAction() throws {
        let nameLines = MemoryTableEmptyCopy.filterEmptyLines(for: .nameFilterEmpty)
        let risingLines = MemoryTableEmptyCopy.filterEmptyLines(for: .risingOnlyEmpty)
        XCTAssertEqual(nameLines?.title, "没有匹配的 App")
        XCTAssertEqual(nameLines?.message, "清空名称和仅上涨过滤。")
        XCTAssertEqual(nameLines?.buttonTitle, "清空过滤")
        XCTAssertEqual(risingLines?.title, "Top5 暂无上涨")
        XCTAssertEqual(risingLines?.message, "其他进程未做趋势判断")
        XCTAssertEqual(risingLines?.buttonTitle, "清空过滤")
        XCTAssertNotEqual(risingLines?.message, nameLines?.message)

        let pane = try paneSource()
        let memory = try functionBody(named: "memoryTableBody", in: pane)
        let nameArm = try switchArm(".nameFilterEmpty", in: memory)
        let risingArm = try switchArm(".risingOnlyEmpty", in: memory)
        let nameCall = callText(in: nameArm)
        let risingCall = callText(in: risingArm)
        let nameCallee = try calleeName(in: nameCall)
        let risingCallee = try calleeName(in: risingCall)
        XCTAssertEqual(
            nameCallee,
            risingCallee,
            "both memory filter empties share one view function; source wiring, not a click"
        )
        XCTAssertTrue(nameCall.contains(".nameFilterEmpty"))
        XCTAssertTrue(risingCall.contains(".risingOnlyEmpty"))

        let shared = try functionBody(named: nameCallee, in: pane)
        XCTAssertEqual(occurrenceCount(of: "MemoryTableEmptyCopy.filterEmptyLines(for:", in: pane), 1)
        XCTAssertTrue(shared.contains("MemoryTableEmptyCopy.filterEmptyLines(for:"))
        XCTAssertFalse(shared.contains("filterEmptyLines(for: .nameFilterEmpty)"))
        XCTAssertFalse(shared.contains("filterEmptyLines(for: .risingOnlyEmpty)"))
        XCTAssertTrue(shared.contains(".title"))
        XCTAssertTrue(shared.contains(".message"))
        XCTAssertTrue(shared.contains(".buttonTitle"))
        XCTAssertEqual(occurrenceCount(of: "vm.clearMemoryPageFilters()", in: shared), 1)
        XCTAssertEqual(occurrenceCount(of: "vm.clearMemoryPageFilters()", in: pane), 1)
        XCTAssertFalse(shared.contains("vm.filter"))
        XCTAssertFalse(shared.contains("risingOnlyFilter"))
        XCTAssertFalse(pane.contains("MemoryGrowthRisingFilterCopy"))

        let duplicated = [
            "没有匹配的 App",
            "清空名称和仅上涨过滤。",
            "Top5 暂无上涨",
            "其他进程未做趋势判断",
            "清空过滤",
            "换个名称试试，或清空过滤。",
        ]
        for literal in duplicated {
            XCTAssertFalse(shared.contains(literal), "view must not hand-write \(literal)")
        }
    }

    func testResourceNameEmptyUsesCPUPageCopyAndClearsFilterOnly() throws {
        XCTAssertEqual(CPUPageCopy.filteredEmptyTitle, "没有匹配的 App")
        XCTAssertEqual(CPUPageCopy.filteredEmptyMessage, "换个名称试试，或清空过滤。")
        XCTAssertEqual(CPUPageCopy.filteredEmptyButton, "清空过滤")
        XCTAssertNotEqual(CPUPageCopy.filteredEmptyMessage, "清空名称和仅上涨过滤。")

        let pane = try paneSource()
        let table = try functionBody(named: "tableBody", in: pane)
        XCTAssertTrue(table.contains("case .cpu:"))
        XCTAssertTrue(table.contains("case .network:"))
        XCTAssertTrue(table.contains("case .disk:"))
        XCTAssertTrue(table.contains("resourceTableBody("))
        XCTAssertTrue(table.contains("memoryTableBody"))

        let resource = try functionBody(named: "resourceTableBody", in: pane)
        let filtered = try switchArm(".filteredEmpty", in: resource)
        XCTAssertEqual(try calleeName(in: callText(in: filtered)), "filterEmpty")
        let empty = try functionBody(named: "filterEmpty", in: pane)
        XCTAssertTrue(empty.contains("CPUPageCopy.filteredEmptyTitle"))
        XCTAssertTrue(empty.contains("CPUPageCopy.filteredEmptyMessage"))
        XCTAssertTrue(empty.contains("CPUPageCopy.filteredEmptyButton"))
        XCTAssertTrue(empty.contains("vm.filter = \"\""))
        XCTAssertFalse(empty.contains("risingOnly"), "resource clear must not write risingOnlyFilter")
        XCTAssertFalse(empty.contains("clearMemoryPageFilters"))
        XCTAssertFalse(empty.contains("MemoryTableEmptyCopy"))
        XCTAssertFalse(empty.contains("filterEmptyLines"))
        XCTAssertFalse(empty.contains("换个名称试试，或清空过滤。"))
        XCTAssertFalse(empty.contains("清空名称和仅上涨过滤。"))

        let memory = try functionBody(named: "memoryTableBody", in: pane)
        XCTAssertFalse(memory.contains("\n                filterEmpty\n"))
        XCTAssertFalse(memory.contains("CPUPageCopy.filteredEmpty"))
    }

    func testPhasesOutsideFilterEmptiesDoNotWireTheClearButton() throws {
        let pane = try paneSource()
        let memory = try functionBody(named: "memoryTableBody", in: pane)
        let memoryArms: [(String, Bool)] = [
            (".sampling", false),
            (".processListFailed", true),
            (".failed", true),
            (".empty", false),
            (".ready", false),
        ]
        for (label, expectsRetry) in memoryArms {
            try assertNoClearButton(label, in: memory, pane: pane, expectsRetry: expectsRetry)
        }
        let listFailure = try switchArm(".processListFailed", in: memory)
        XCTAssertTrue(listFailure.contains("SamplingRetryChrome.processListFailedMessage"))
        let failed = try switchArm(".failed", in: memory)
        XCTAssertTrue(failed.contains("进程列表还没有数据"))

        let resource = try functionBody(named: "resourceTableBody", in: pane)
        let resourceArms: [(String, Bool)] = [
            (".sampling", false),
            (".failed", true),
            (".empty", false),
            (".ready", false),
        ]
        for (label, expectsRetry) in resourceArms {
            try assertNoClearButton(label, in: resource, pane: pane, expectsRetry: expectsRetry)
        }

        let sampling = try functionBody(named: "samplingPlaceholder", in: pane)
        XCTAssertFalse(sampling.contains("clearMemoryPageFilters"))
        XCTAssertFalse(sampling.contains("vm.filter = \"\""))
        let list = try functionBody(named: "processList", in: pane)
        XCTAssertFalse(list.contains("clearMemoryPageFilters"))
        XCTAssertFalse(list.contains("清空过滤"))

        let views = repoRoot().appendingPathComponent("Pulse/Views", isDirectory: true)
        let files = try FileManager.default.contentsOfDirectory(at: views, includingPropertiesForKeys: nil)
        for file in files where file.pathExtension == "swift" {
            let text = try String(contentsOf: file, encoding: .utf8)
            if file.lastPathComponent == "ProcessTablePane.swift" {
                XCTAssertEqual(occurrenceCount(of: "vm.clearMemoryPageFilters()", in: text), 1)
            } else {
                XCTAssertFalse(
                    text.contains("clearMemoryPageFilters"),
                    "\(file.lastPathComponent) must not gain the memory clear; source contract"
                )
            }
        }
    }

    func testToolbarAndAppFilterFieldStayNameOnlyClear() throws {
        let dashboard = try repoText("Pulse/Views/MemoryDashboardView.swift")
        let toggle = try range(of: "Toggle(MemoryRisingOnlyChrome.toggleTitle, isOn: $vm.risingOnlyFilter)", in: dashboard)
        let field = try range(of: "AppFilterField(text: $vm.filter)", in: dashboard)
        XCTAssertLessThan(
            toggle.lowerBound,
            field.lowerBound,
            "toggle stays before the name field; source order, not a layout run"
        )
        XCTAssertTrue(dashboard.contains("MemoryRisingOnlyChrome.showsToggle(page: vm.selectedPage)"))
        XCTAssertFalse(dashboard.contains("clearMemoryPageFilters"))
        XCTAssertFalse(dashboard.contains("vm.filter = \"\""))
        XCTAssertFalse(dashboard.contains("risingOnlyFilter = false"))

        let shared = try repoText("Pulse/Views/SharedUI.swift")
        let filterField = try typeBody(named: "AppFilterField", keyword: "struct", in: shared)
        XCTAssertTrue(filterField.contains("text = \"\""))
        XCTAssertTrue(filterField.contains(".accessibilityLabel(\"清空过滤\")"))
        XCTAssertFalse(filterField.contains("clearMemoryPageFilters"))
        XCTAssertFalse(filterField.contains("risingOnly"))
        XCTAssertFalse(filterField.contains("vm.filter"))
        XCTAssertEqual(occurrenceCount(of: "text = \"\"", in: filterField), 1)

        let package = try repoText("Package.swift")
        XCTAssertTrue(package.contains("\"Views\""))
        XCTAssertTrue(package.contains("\"ViewModels\""))
        XCTAssertFalse(package.contains("MemoryDashboardVM.swift"))
        XCTAssertFalse(package.contains("ProcessTablePane.swift"))
    }

    private func assertNoClearButton(
        _ label: String,
        in body: String,
        pane: String,
        expectsRetry: Bool
    ) throws {
        let arm = try switchArm(label, in: body)
        XCTAssertFalse(arm.contains("clearMemoryPageFilters"), label)
        XCTAssertFalse(arm.contains("filterEmptyLines"), label)
        XCTAssertFalse(arm.contains("filteredEmptyButton"), label)
        XCTAssertFalse(arm.contains("vm.filter = \"\""), label)
        XCTAssertFalse(arm.contains("memoryFilterEmpty"), label)
        if expectsRetry {
            XCTAssertTrue(arm.contains("vm.retrySampling"), label)
        } else {
            XCTAssertFalse(arm.contains("vm.retrySampling"), label)
        }
        if let callee = try? calleeName(in: callText(in: arm)),
           let local = functionBodyIfPresent(named: callee, in: pane) {
            XCTAssertFalse(local.contains("clearMemoryPageFilters"), "\(label) \(callee)")
            XCTAssertFalse(local.contains("MemoryTableEmptyCopy"), "\(label) \(callee)")
            XCTAssertFalse(local.contains("CPUPageCopy.filteredEmptyButton"), "\(label) \(callee)")
            XCTAssertFalse(local.contains("vm.filter = \"\""), "\(label) \(callee)")
        }
    }

    private func vmSource() throws -> String {
        try WiringSourceText.text(for: "MemoryDashboardVM")
    }

    private func paneSource() throws -> String {
        try repoText("Pulse/Views/ProcessTablePane.swift")
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
        guard let body = functionBodyIfPresent(named: name, in: source) else {
            throw SourceSliceError.missing("declaration for \(name)")
        }
        return body
    }

    private func functionBodyIfPresent(named name: String, in source: String) -> String? {
        let patterns = [
            "var \(name):",
            "func \(name)(",
            "func \(name)()",
            "private func \(name)(",
            "private func \(name)()",
        ]
        for pattern in patterns {
            guard let range = source.range(of: pattern),
                  let brace = source[range.lowerBound...].firstIndex(of: "{")
            else { continue }
            return try? balancedSlice(from: brace, in: source, label: name)
        }
        return nil
    }

    private func typeBody(named name: String, keyword: String, in source: String) throws -> String {
        guard let start = source.range(of: "\(keyword) \(name)")?.lowerBound else {
            throw SourceSliceError.missing("\(keyword) \(name)")
        }
        guard let brace = source[start...].firstIndex(of: "{") else {
            throw SourceSliceError.missing("body for \(name)")
        }
        return try balancedSlice(from: brace, in: source, label: name)
    }

    private func braceBody(after needle: String, in source: String) throws -> String {
        guard let start = source.range(of: needle)?.upperBound else {
            throw SourceSliceError.missing(needle)
        }
        guard let brace = source[start...].firstIndex(of: "{") else {
            throw SourceSliceError.missing("brace after \(needle)")
        }
        return try balancedSlice(from: brace, in: source, label: needle)
    }

    private func switchArm(_ label: String, in source: String) throws -> String {
        let needle = "case \(label):"
        guard let range = source.range(of: needle) else {
            throw SourceSliceError.missing(needle)
        }
        var index = range.upperBound
        while index < source.endIndex {
            guard let newline = source[index...].firstIndex(of: "\n") else { break }
            let lineStart = source.index(after: newline)
            if lineStart >= source.endIndex { break }
            let lineEnd = source[lineStart...].firstIndex(of: "\n") ?? source.endIndex
            let trimmed = source[lineStart..<lineEnd].drop(while: { $0 == " " || $0 == "\t" })
            if trimmed.hasPrefix("case ") || trimmed.hasPrefix("default:") || trimmed == "}" {
                return String(source[range.lowerBound..<newline])
            }
            index = lineStart
        }
        throw SourceSliceError.missing("end of \(needle)")
    }

    private func callText(in arm: String) -> String {
        arm.components(separatedBy: .newlines)
            .dropFirst()
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && !$0.hasPrefix("//") }
            .joined(separator: "\n")
    }

    private func calleeName(in call: String) throws -> String {
        let token = call.prefix { $0.isLetter || $0 == "_" }
        guard !token.isEmpty else {
            throw SourceSliceError.missing("callee in \(call)")
        }
        return String(token)
    }

    private func statements(in body: String) -> [String] {
        body.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { line in
                !line.isEmpty && line != "{" && line != "}" && !line.hasPrefix("//")
            }
    }

    private func lineContaining(_ needle: String, in source: String) throws -> String {
        guard let line = source.components(separatedBy: .newlines).first(where: { $0.contains(needle) }) else {
            throw SourceSliceError.missing(needle)
        }
        return line
    }

    private func range(of needle: String, in source: String) throws -> Range<String.Index> {
        guard let found = source.range(of: needle) else {
            throw SourceSliceError.missing(needle)
        }
        return found
    }

    private func balancedSlice(from start: String.Index, in source: String, label: String) throws -> String {
        let opener = source[start]
        let closer: Character = opener == "(" ? ")" : "}"
        var depth = 0
        var index = start
        while index < source.endIndex {
            let character = source[index]
            if character == opener { depth += 1 }
            if character == closer {
                depth -= 1
                if depth == 0 {
                    return String(source[start...index])
                }
            }
            index = source.index(after: index)
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
