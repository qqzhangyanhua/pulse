import XCTest
@testable import SamplingCore

/// Phase 20 source wiring. Linux SamplingCore does not compile ViewModels or Views.
/// These tests read source text. They do not instantiate `MemoryDashboardVM`, enter
/// its MainActor, click the card, build a SwiftUI List, or prove a scroll landed.
/// Two `scrollTo` schedules for different pids may both run; this file does not
/// claim they become one visual scroll, and it does not claim Mac onAppear or a
/// stale id after `main.async`.
final class TopAppLocationWiringSourceTests: XCTestCase {
    func testMemoryOverviewIsTheOnlyLocateEntry() throws {
        let overview = try repoText("Pulse/Views/OverviewSection.swift")
        XCTAssertEqual(occurrenceCount(of: "TopAppCard(", in: overview), 1)
        XCTAssertEqual(occurrenceCount(of: "TopConsumer.leading", in: overview), 1)
        XCTAssertEqual(occurrenceCount(of: "locateMemoryTopApp", in: overview), 1)
        XCTAssertFalse(overview.contains("selectedPid ="), "the card must not assign selectedPid")
        XCTAssertFalse(overview.contains("onTapGesture"), "nil card keeps the existing card gesture")

        let ready = try functionBody(named: "readyBody", in: overview)
        let readyCode = compact(ready)
        XCTAssertEqual(occurrenceCount(of: "TopConsumer.leading", in: ready), 1)
        XCTAssertTrue(readyCode.contains("letconsumer=TopConsumer.leading(in:vm.rows)"))
        XCTAssertTrue(readyCode.contains("TopAppCard(consumer:consumer)"))
        XCTAssertTrue(
            readyCode.contains("vm.locateMemoryTopApp(name:consumer.name,pid:pid)"),
            "closure must pass the same bound name and the card pid"
        )
        XCTAssertFalse(readyCode.contains("locateMemoryTopApp(name:TopConsumer"))
        XCTAssertEqual(occurrenceCount(of: "leading(in:", in: ready), 1)

        let sampling = try functionBody(named: "samplingBody", in: overview)
        let failure = try functionBody(named: "failureBody", in: overview)
        XCTAssertFalse(sampling.contains("TopAppCard"))
        XCTAssertFalse(failure.contains("TopAppCard"))
        XCTAssertFalse(sampling.contains("locateMemoryTopApp"))
        XCTAssertFalse(failure.contains("locateMemoryTopApp"))

        for name in [
            "CPUOverviewSection.swift",
            "NetworkOverviewSection.swift",
            "DiskOverviewSection.swift",
        ] {
            let text = try repoText("Pulse/Views/\(name)")
            XCTAssertFalse(text.contains("locateMemoryTopApp"), name)
            XCTAssertFalse(text.contains("TopAppLocation"), name)
            XCTAssertFalse(text.contains("topAppLocateReveal"), name)
            XCTAssertFalse(text.contains("TopAppCard"), name)
        }

        let card = try typeBody(named: "TopAppCard", keyword: "struct", in: try repoText("Pulse/Views/OverviewCards.swift"))
        XCTAssertTrue(card.contains("if let consumer"))
        XCTAssertTrue(card.contains("onSelect(consumer.pid)"))
        XCTAssertFalse(card.contains("locateMemoryTopApp"))

        let views = repoRoot().appendingPathComponent("Pulse/Views", isDirectory: true)
        let files = try FileManager.default.contentsOfDirectory(at: views, includingPropertiesForKeys: nil)
        for file in files where file.pathExtension == "swift" {
            let text = try String(contentsOf: file, encoding: .utf8)
            let count = occurrenceCount(of: "locateMemoryTopApp", in: text)
            if file.lastPathComponent == "OverviewSection.swift" {
                XCTAssertEqual(count, 1)
            } else {
                XCTAssertEqual(count, 0, file.lastPathComponent)
            }
        }
    }

    func testLocateMethodSnapshotsThenWritesOnlyAfterThePlanGuard() throws {
        let source = try vmSource()
        XCTAssertEqual(occurrenceCount(of: "@MainActor", in: source), 1)
        XCTAssertEqual(occurrenceCount(of: "didSet", in: source), 2)
        XCTAssertEqual(occurrenceCount(of: "@Published", in: source), 26)
        XCTAssertEqual(occurrenceCount(of: "func locateMemoryTopApp(", in: source), 1)
        XCTAssertEqual(occurrenceCount(of: "topAppLocateReveal =", in: source), 1)

        let declaration = try lineContaining("func locateMemoryTopApp(", in: source)
        XCTAssertFalse(declaration.contains("@MainActor"))
        XCTAssertFalse(declaration.contains("async"))
        XCTAssertTrue(compact(declaration).contains("funclocateMemoryTopApp(name:String,pid:Int32)"))

        let revealLine = try lineContaining("var topAppLocateReveal", in: source)
        XCTAssertEqual(
            revealLine.trimmingCharacters(in: .whitespaces),
            "@Published var topAppLocateReveal: TopAppLocation.Reveal?"
        )
        XCTAssertFalse(revealLine.contains("didSet"))

        let sortedLine = try lineContaining("var sortedRows", in: source)
        XCTAssertFalse(sortedLine.contains("@Published"))
        let sortedBody = try functionBody(named: "sortedRows", in: source)
        XCTAssertTrue(compact(sortedBody).contains("tableSort.ordered(visibleRows)"))
        XCTAssertFalse(compact(sortedBody).contains("ordered(rows)"))

        let body = try functionBody(named: "locateMemoryTopApp", in: source)
        let code = compact(body)
        XCTAssertEqual(occurrenceCount(of: "guard let plan", in: body), 1)
        XCTAssertEqual(occurrenceCount(of: "risingOnlyFilter = false", in: body), 1)
        XCTAssertEqual(occurrenceCount(of: "selectPidIfPresent(", in: body), 1)
        XCTAssertEqual(occurrenceCount(of: "topAppLocateReveal =", in: body), 1)
        XCTAssertEqual(occurrenceCount(of: "filter =", in: body), 1)

        let guardAt = try index(of: "guard let plan", in: body)
        let planAt = try index(of: "TopAppLocation.plan(", in: body)
        let replaceAt = try index(of: ".replace", in: body)
        let filterAt = try index(of: "filter =", in: body)
        let risingAt = try index(of: "risingOnlyFilter = false", in: body)
        let selectAt = try index(of: "selectPidIfPresent(", in: body)
        let revealAt = try index(of: "topAppLocateReveal =", in: body)
        XCTAssertLessThan(guardAt, planAt)
        XCTAssertLessThan(planAt, replaceAt)
        XCTAssertLessThan(replaceAt, filterAt)
        XCTAssertLessThan(filterAt, risingAt)
        XCTAssertLessThan(risingAt, selectAt)
        XCTAssertLessThan(selectAt, revealAt)

        XCTAssertTrue(
            code.contains(
                "TopAppLocation.plan(name:name,pid:pid,rows:rows,page:selectedPage,currentFilter:filter,currentRisingOnly:risingOnlyFilter,previousReveal:topAppLocateReveal)"
            )
        )
        XCTAssertTrue(code.contains("case.replace(letnextName)"))
        XCTAssertTrue(code.contains("filter=nextName"))
        XCTAssertTrue(code.contains("selectPidIfPresent(plan.acceptedPid)"))
        XCTAssertTrue(code.contains("topAppLocateReveal=plan.reveal"))
        XCTAssertFalse(body.contains("selectedPid ="))
        XCTAssertFalse(body.contains("await"))
        XCTAssertFalse(body.contains("sample()"))
        for token in [
            "clearMemoryPageFilters",
            "retrySampling",
            "setSelectedPid",
            "setTableSort",
            "setMemoryPageSort",
            "publishMemoryPageSort",
            "selectPage",
            "focusMemoryPage",
            "applyRisingOnlySelection",
            "quitOutcome",
            "sidebarSubjectPid",
            "navigation",
            "publication",
            "topMemorySeries",
            "Task",
            "onChange",
            "processListScrollTarget",
        ] {
            XCTAssertFalse(body.contains(token), token)
        }
    }

    func testRevealTopAppGatesOnSortedRowsThenScrollsRequestPid() throws {
        let pane = try paneSource()
        XCTAssertEqual(occurrenceCount(of: "func revealTopApp(", in: pane), 1)
        XCTAssertEqual(occurrenceCount(of: "revealTopApp(", in: pane), 2)
        XCTAssertEqual(occurrenceCount(of: "onChange(of: vm.topAppLocateReveal)", in: pane), 1)
        XCTAssertEqual(occurrenceCount(of: "onChange(of: vm.processListScrollTarget)", in: pane), 1)
        XCTAssertFalse(pane.contains("private var sortedRows"))
        XCTAssertFalse(pane.contains("tableSort.ordered"))

        let paneCode = compact(pane)
        XCTAssertTrue(paneCode.contains("List(vm.sortedRows,selection:$vm.selectedPid)"))
        XCTAssertTrue(paneCode.contains("visibleCount:vm.sortedRows.count"))

        let topChange = try trailingClosure(after: ".onChange(of: vm.topAppLocateReveal)", in: pane)
        let topCode = compact(topChange)
        XCTAssertTrue(topCode.contains("guardletrequestelse{return}"))
        XCTAssertTrue(topCode.contains("revealTopApp(request:request,proxy:proxy)"))
        XCTAssertFalse(topChange.contains("revealProcessListTarget"))
        XCTAssertFalse(topChange.contains("processListScrollTarget"))
        XCTAssertFalse(topChange.contains("selectedPid"))

        let body = try functionBody(named: "revealTopApp", in: pane)
        let code = compact(body)
        let gate = "vm.sortedRows.contains(where:{$0.pid==request.pid})"
        let scroll = "scrollTo(request.pid,anchor:.center)"
        XCTAssertTrue(code.contains(gate), "request-pid sortedRows gate missing")
        XCTAssertTrue(code.contains(scroll), "request.pid scroll identity missing")
        let gateAt = try index(of: gate, in: code)
        let scrollAt = try index(of: scroll, in: code)
        XCTAssertLessThan(gateAt, scrollAt, "missing pid returns before scrollTo")
        XCTAssertTrue(
            code.contains("DispatchQueue.main.async{proxy.scrollTo(request.pid,anchor:.center)}"),
            "scrollTo(request.pid) must sit in the main.async closure"
        )
        XCTAssertFalse(body.contains("processListScrollTarget"))
        XCTAssertFalse(body.contains("selectedPid"))
        XCTAssertFalse(body.contains("revealProcessListTarget"))
        XCTAssertEqual(occurrenceCount(of: "scrollTo(", in: body), 1)

        let oldChange = try trailingClosure(after: ".onChange(of: vm.processListScrollTarget)", in: pane)
        XCTAssertTrue(compact(oldChange).contains("revealProcessListTarget(proxy)"))
        XCTAssertFalse(oldChange.contains("revealTopApp"))

        let appear = try trailingClosure(after: ".onAppear", in: pane)
        XCTAssertTrue(compact(appear).contains("revealProcessListTarget(proxy)"))
        XCTAssertFalse(appear.contains("revealTopApp"))

        let old = try functionBody(named: "revealProcessListTarget", in: pane)
        let oldCode = compact(old)
        XCTAssertTrue(oldCode.contains("guardlettarget=vm.processListScrollTargetelse{return}"))
        XCTAssertTrue(oldCode.contains("DispatchQueue.main.async{proxy.scrollTo(target,anchor:.center)}"))
        XCTAssertFalse(old.contains("request.pid"))
        XCTAssertFalse(old.contains("sortedRows"))
        XCTAssertFalse(old.contains("revealTopApp"))
    }

    func testOrdinaryPathsDoNotPublishTheTopReveal() throws {
        let source = try vmSource()
        let clear = try functionBody(named: "clearMemoryPageFilters", in: source)
        XCTAssertEqual(statements(in: clear), ["filter = \"\"", "risingOnlyFilter = false"])
        XCTAssertFalse(clear.contains("topAppLocateReveal"))

        let filterLine = try lineContaining("var filter", in: source)
        XCTAssertEqual(filterLine, "    @Published var filter = \"\"")
        XCTAssertFalse(filterLine.contains("didSet"))

        for name in ["selectPage", "focusMemoryPage", "setTableSort", "retrySampling"] {
            let body = try functionBody(named: name, in: source)
            XCTAssertFalse(body.contains("topAppLocateReveal"), name)
            XCTAssertFalse(body.contains("locateMemoryTopApp"), name)
        }

        let pane = try paneSource()
        XCTAssertFalse(pane.contains("onChange(of: vm.filter)"))
        XCTAssertFalse(pane.contains("onChange(of: vm.risingOnlyFilter)"))
        XCTAssertEqual(occurrenceCount(of: "vm.clearMemoryPageFilters()", in: pane), 1)
        let list = try functionBody(named: "processList", in: pane)
        XCTAssertTrue(list.contains("selection: $vm.selectedPid"))
        XCTAssertFalse(list.contains("locateMemoryTopApp"))
        XCTAssertFalse(compact(list).contains("topAppLocateReveal="))

        let dashboard = try repoText("Pulse/Views/MemoryDashboardView.swift")
        XCTAssertTrue(dashboard.contains("AppFilterField(text: $vm.filter)"))
        XCTAssertTrue(dashboard.contains("isOn: $vm.risingOnlyFilter"))
        XCTAssertFalse(dashboard.contains("topAppLocateReveal"))
        XCTAssertFalse(dashboard.contains("locateMemoryTopApp"))
        XCTAssertFalse(dashboard.contains("onChange(of: vm.filter)"))
        XCTAssertFalse(dashboard.contains("onChange(of: vm.risingOnlyFilter)"))
    }

    func testPackageAndProjectRegisterThePureModel() throws {
        let package = try repoText("Package.swift")
        XCTAssertTrue(package.contains("\"Models/TopAppLocation.swift\""))
        XCTAssertTrue(package.contains("\"ViewModels\""))
        XCTAssertTrue(package.contains("\"Views\""))
        XCTAssertFalse(package.contains("MemoryDashboardVM.swift"))
        XCTAssertFalse(package.contains("ProcessTablePane.swift"))

        let project = try repoText("Pulse.xcodeproj/project.pbxproj")
        XCTAssertTrue(project.contains("TopAppLocation.swift in Sources"))
        XCTAssertTrue(project.contains("path = TopAppLocation.swift;"))
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

    private func trailingClosure(after needle: String, in source: String) throws -> String {
        guard let start = source.range(of: needle)?.upperBound else {
            throw SourceSliceError.missing(needle)
        }
        guard let brace = source[start...].firstIndex(of: "{") else {
            throw SourceSliceError.missing("closure after \(needle)")
        }
        return try balancedSlice(from: brace, in: source, label: needle)
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

    private func compact(_ source: String) -> String {
        let withoutLineComments = source.components(separatedBy: .newlines).map { line -> String in
            guard let marker = line.range(of: "//") else { return line }
            return String(line[..<marker.lowerBound])
        }.joined(separator: "\n")
        return withoutLineComments.filter { !$0.isWhitespace }
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
