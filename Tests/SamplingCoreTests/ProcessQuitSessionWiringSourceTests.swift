import XCTest
@testable import SamplingCore

/// Phase 16 knife 2 source contract.
///
/// Linux SamplingCore does not compile `ViewModels/`, `Views/`, `ProcessActions`,
/// or `MemorySampler`. These tests read source text. They do not instantiate
/// `MemoryDashboardVM`, do not enter its `@MainActor` isolation, do not run
/// SwiftUI, and do not call `NSRunningApplication`. A pass is not a sidebar
/// click, not a GUI test, and not a real quit.
final class ProcessQuitSessionWiringSourceTests: XCTestCase {
    func testSessionHelperStaysDarwinFreeAndHasNoIdentitySwitch() throws {
        let source = try repoText("Pulse/Models/ProcessQuitSession.swift")
        XCTAssertFalse(source.contains("import Darwin"))
        XCTAssertFalse(source.contains("import AppKit"))
        XCTAssertFalse(source.contains("import SwiftUI"))
        XCTAssertFalse(source.contains("ProcessActions"))
        XCTAssertFalse(source.contains("MemorySampler"))
        XCTAssertFalse(source.contains("MemoryDashboardVM"))
        XCTAssertFalse(source.contains("NSAlert"))
        XCTAssertFalse(source.contains("NSRunningApplication"))
        XCTAssertFalse(source.contains("startTime"))
        XCTAssertFalse(source.contains("identityEvidence:"))
        XCTAssertFalse(source.contains("identityEvidence ="))
        XCTAssertTrue(source.contains("enum ProcessQuitSession"))
        XCTAssertTrue(source.contains("store.applyPresenceFromRows"))
        let package = try repoText("Package.swift")
        XCTAssertTrue(package.contains("\"Models/ProcessQuitSession.swift\""))
        XCTAssertTrue(package.contains("\"Models/ProcessQuitOutcome.swift\""))
        XCTAssertTrue(package.contains("\"ViewModels\""))
        XCTAssertTrue(package.contains("\"Views\""))
        XCTAssertTrue(package.contains("\"Actions\""))
        XCTAssertTrue(package.contains("\"Sampling/MemorySampler.swift\""))
        XCTAssertFalse(package.contains("MemoryDashboardVM.swift"))
    }

    func testVMHoldsOneQuitStoreAndDerivesPhaseFromTheSidebar() throws {
        let source = try vmSource()
        XCTAssertEqual(occurrenceCount(of: "ProcessQuitOutcome()", in: source), 1)
        XCTAssertEqual(occurrenceCount(of: "var quitOutcome", in: source), 1)
        XCTAssertTrue(source.contains("@Published var quitOutcome = ProcessQuitOutcome()"))
        XCTAssertTrue(source.contains("@Published var sidebarSubjectPid: Int32?"))
        XCTAssertEqual(
            try lineContaining("var quitPhase", in: source),
            "    var quitPhase: QuitPhase { sidebar.quitPhase }"
        )
        XCTAssertEqual(
            try lineContaining("var quitMessage", in: source),
            "    var quitMessage: String? { sidebar.quitMessage }"
        )
        XCTAssertFalse(source.contains("quitPhase ="))
        XCTAssertFalse(source.contains("quitMessage ="))
        XCTAssertFalse(source.contains("func applyQuit"))
        XCTAssertFalse(source.contains("selectedPid = nil"))
        XCTAssertFalse(source.contains(".click("))
        XCTAssertFalse(source.contains("applyPresenceFromRows"))
        XCTAssertFalse(source.contains(".complete("))
        XCTAssertFalse(source.contains("identityEvidence"))
        XCTAssertFalse(source.contains("Timer"))
        XCTAssertFalse(source.contains("NSAlert"))
        XCTAssertEqual(occurrenceCount(of: "ProcessQuitSession.applySample", in: source), 1)
        XCTAssertEqual(occurrenceCount(of: "@Published", in: source), 27, "windowed app filter adds windowedOnlyFilter")
        XCTAssertEqual(occurrenceCount(of: "didSet", in: source), 3)
    }

    func testSelectedPidDidSetDoesNotTouchTheQuitStore() throws {
        let source = try vmSource()
        let body = try braceBody(after: "var selectedPid", in: source)
        XCTAssertTrue(body.contains("didSet"))
        XCTAssertTrue(body.contains("ProcessQuitSession.followListSelection"))
        XCTAssertTrue(body.contains("sampler.setSelectedPid(pid)"))
        XCTAssertFalse(body.contains("quitOutcome"))
        XCTAssertFalse(body.contains("quitPhase"))
        XCTAssertFalse(body.contains("quitMessage"))
        XCTAssertFalse(body.contains("setSelectedPid(sidebarSubjectPid)"))
        XCTAssertFalse(body.contains(".idle"))
        let samplerLine = try lineContaining("sampler.setSelectedPid", in: body)
        XCTAssertEqual(samplerLine.trimmingCharacters(in: .whitespaces), "Task { await sampler.setSelectedPid(pid) }")
        XCTAssertTrue(body.contains("let pid = selectedPid"))
        XCTAssertFalse(samplerLine.contains("sidebarSubjectPid"))
    }

    func testTickRoutesEverySampleOutcomeThroughOneApply() throws {
        let source = try vmSource()
        let tick = try functionBody(named: "tick", in: source)
        XCTAssertTrue(tick.contains("applySample(result, accepted: accepted)"))
        XCTAssertFalse(tick.contains("selectedPid"))
        XCTAssertFalse(tick.contains("quit"))
        XCTAssertEqual(occurrenceCount(of: "func applySample(", in: source), 1)
        let apply = try functionBody(named: "applySample", in: source)
        XCTAssertEqual(occurrenceCount(of: "ProcessQuitSession.applySample", in: apply), 1)
        XCTAssertTrue(apply.contains("freshnessInsufficient: true"))
        XCTAssertTrue(apply.contains("samplingFailed: true"))
        XCTAssertTrue(apply.contains("processListFailed: frame.processListFailed"))
        XCTAssertTrue(apply.contains("detailToFreeze: detail"))
        XCTAssertTrue(apply.contains("usageHistory"))
        XCTAssertTrue(apply.contains("rows = frame.rows"))
        XCTAssertTrue(apply.contains("SamplingRetryApply.apply"))
        XCTAssertTrue(apply.contains("applyRisingOnlySelection()"))
        XCTAssertFalse(apply.contains("identityEvidence"))
        XCTAssertFalse(apply.contains("quitPhase"))
        XCTAssertFalse(apply.contains("quitMessage"))
    }

    func testQuitMethodsUseTheSessionTokenAndTheExistingActions() throws {
        let source = try vmSource()
        let ordinary = try functionBody(named: "quitSelected", in: source)
        XCTAssertTrue(ordinary.contains("ProcessQuitSession.ordinaryTerminate"))
        XCTAssertTrue(ordinary.contains("ProcessActions.terminate(pid: issued.pid)"))
        XCTAssertTrue(ordinary.contains("taskCancelled: Task.isCancelled"))
        XCTAssertTrue(ordinary.contains("ProcessQuitSession.finish"))
        XCTAssertTrue(ordinary.contains("pid: issued.pid"))
        XCTAssertTrue(ordinary.contains("token: issued.token"))
        XCTAssertFalse(ordinary.contains("pid: selectedPid"))
        XCTAssertFalse(ordinary.contains("pid: sidebarSubjectPid"))
        XCTAssertFalse(ordinary.contains("quitPhase"))

        let force = try functionBody(named: "forceQuitSelected", in: source)
        XCTAssertLessThan(
            try index(of: "ProcessQuitSession.requestForce", in: force),
            try index(of: "ProcessActions.confirmForceQuit(displayName: request.displayName)", in: force)
        )
        XCTAssertLessThan(
            try index(of: "ProcessActions.confirmForceQuit(displayName: request.displayName)", in: force),
            try index(of: "ProcessQuitSession.cancelForce", in: force)
        )
        XCTAssertLessThan(
            try index(of: "ProcessQuitSession.cancelForce", in: force),
            try index(of: "ProcessQuitSession.confirmForce", in: force)
        )
        XCTAssertLessThan(
            try index(of: "ProcessQuitSession.confirmForce", in: force),
            try index(of: "ProcessActions.forceTerminate(pid: issued.pid)", in: force)
        )
        XCTAssertTrue(force.contains("ProcessQuitSession.finish"))
        XCTAssertTrue(force.contains("taskCancelled: Task.isCancelled"))
        XCTAssertFalse(force.contains("NSAlert"))
        XCTAssertFalse(force.contains(".sheet"))
        XCTAssertFalse(force.contains("quitPhase ="))
        let dismiss = try functionBody(named: "dismissSidebar", in: source)
        XCTAssertTrue(dismiss.contains("ProcessQuitSession.dismissSidebar()"))
        XCTAssertFalse(dismiss.contains("quitOutcome"))
        XCTAssertFalse(dismiss.contains("complete"))
        let rising = try functionBody(named: "applyRisingOnlySelection", in: source)
        XCTAssertTrue(rising.contains("ProcessQuitSession.risingOnlySelection"))
        XCTAssertTrue(rising.contains("MemoryGrowthRisingFilter.selectedPid"))
        XCTAssertFalse(rising.contains("quitOutcome ="))
    }

    func testSidebarReadsTheProjectionAndKeepsTheExistingControls() throws {
        let sidebar = try WiringSourceText.text(for: "ProcessDetailSidebar")
        XCTAssertTrue(sidebar.contains("vm.sidebar"))
        XCTAssertTrue(sidebar.contains("sidebar.detail"))
        XCTAssertTrue(sidebar.contains("sidebar.absentLabel"))
        XCTAssertTrue(sidebar.contains("sidebar.quitMessage"))
        XCTAssertTrue(sidebar.contains("sidebar.showsQuittingSpinner"))
        XCTAssertTrue(sidebar.contains("!sidebar.buttonsEnabled"))
        XCTAssertTrue(sidebar.contains("vm.dismissSidebar()"))
        XCTAssertTrue(sidebar.contains("Text(\"正在退出…\")"))
        XCTAssertTrue(sidebar.contains("Text(\"强制退出…\")"))
        XCTAssertTrue(sidebar.contains("Label(\"退出\""))
        XCTAssertTrue(sidebar.contains("memoryChart(detail)"))
        XCTAssertTrue(sidebar.contains("cpuChart(detail)"))
        XCTAssertTrue(sidebar.contains("vm.memoryGrowthSlot"))
        // Phase 18: normal live is sidebar.detail.pid == vm.detail.pid.
        // The card is still sidebar.detail. The one vm.detail read is that pid gate,
        // so a row-only placeholder is not treated as live. It is not a second detail source.
        XCTAssertEqual(occurrenceCount(of: "vm.detail", in: sidebar), 1)
        XCTAssertTrue(sidebar.contains("liveDetailPid: vm.detail?.row.pid"))
        XCTAssertFalse(sidebar.contains("detailBody(vm.detail"))
        XCTAssertFalse(sidebar.contains("vm.detail.memory"))
        XCTAssertFalse(sidebar.contains("vm.detail.cpu"))
        XCTAssertFalse(sidebar.contains("selectedFallback"))
        XCTAssertFalse(sidebar.contains("vm.quitPhase"))
        XCTAssertFalse(sidebar.contains("vm.quitMessage"))
        XCTAssertFalse(sidebar.contains("重试退出"))
        XCTAssertFalse(sidebar.contains("重试强制退出"))
        XCTAssertFalse(sidebar.contains("上次退出未成功"))
        XCTAssertFalse(sidebar.contains("已成功"))
        XCTAssertFalse(sidebar.contains("Timer"))
        XCTAssertEqual(occurrenceCount(of: "vm.dismissSidebar()", in: sidebar), 1)
        let vm = try vmSource()
        let slot = try functionBody(named: "memoryGrowthSlot", in: vm)
        XCTAssertTrue(slot.contains("sidebar.showsLiveTrend"))
        XCTAssertTrue(slot.contains("MemoryGrowthSidebar.slot"))
    }

    func testXcodeListsTheQuitModelOnceAndSamplerStaysUntouched() throws {
        let project = try repoText("Pulse.xcodeproj/project.pbxproj")
        XCTAssertEqual(occurrenceCount(of: "ProcessQuitOutcome.swift", in: project), 6)
        XCTAssertEqual(occurrenceCount(of: "ProcessQuitSession.swift", in: project), 6)
        XCTAssertTrue(project.contains("ProcessQuitOutcome.swift in Sources"))
        XCTAssertTrue(project.contains("ProcessQuitSession.swift in Sources"))
        let actions = try repoText("Pulse/Actions/ProcessActions.swift")
        XCTAssertTrue(actions.contains("alert.messageText = \"立即退出“\\(displayName)”？\""))
        XCTAssertTrue(actions.contains("应用没有响应正常退出。系统将立即结束该进程。"))
        XCTAssertTrue(actions.contains("alert.addButton(withTitle: \"立即退出\")"))
        XCTAssertTrue(actions.contains("alert.addButton(withTitle: \"取消\")"))
        XCTAssertTrue(actions.contains("static func confirmForceQuit(displayName: String) -> Bool"))
        let sampler = try repoText("Pulse/Sampling/MemorySampler.swift")
        XCTAssertTrue(sampler.contains("selectedMemorySeries.removeAll(keepingCapacity: true)"))
        XCTAssertTrue(sampler.contains("selectedCPUSeries.removeAll(keepingCapacity: true)"))
        XCTAssertFalse(sampler.contains("ProcessQuit"))
        XCTAssertFalse(sampler.contains("Timer"))
        let menu = try repoText("Pulse/MenuBar/MenuBarStatus.swift")
        XCTAssertFalse(menu.contains("quitSelected"))
        XCTAssertFalse(menu.contains("forceTerminate"))
    }

    func testApplySamplePassesFrameUsedBytesAndSamplerStaysFreeOfQuitWords() throws {
        let source = try vmSource()
        let apply = try functionBody(named: "applySample", in: source)
        XCTAssertEqual(occurrenceCount(of: "usedBytes: frame.snapshot.usedBytes", in: apply), 1)
        XCTAssertEqual(occurrenceCount(of: "@Published", in: source), 27)
        XCTAssertTrue(source.contains("guard snapshot != nil, samplingFailed == false else { return nil }"))
        XCTAssertTrue(source.contains("return snapshot?.usedBytes"))
        let ordinary = try functionBody(named: "quitSelected", in: source)
        XCTAssertTrue(ordinary.contains("usedBytes: quitReleaseBaseline"))
        let force = try functionBody(named: "forceQuitSelected", in: source)
        XCTAssertLessThan(
            try index(of: "ProcessQuitSession.requestForce", in: force),
            try index(of: "usedBytes: quitReleaseBaseline", in: force)
        )
        XCTAssertLessThan(
            try index(of: "ProcessQuitSession.confirmForce", in: force),
            try index(of: "usedBytes: quitReleaseBaseline", in: force)
        )
        XCTAssertEqual(occurrenceCount(of: "usedBytes: quitReleaseBaseline", in: force), 1)
        let sampler = try repoText("Pulse/Sampling/MemorySampler.swift")
        XCTAssertFalse(sampler.contains("ProcessQuit"))
        XCTAssertFalse(sampler.contains("releaseNote"))
        XCTAssertFalse(sampler.contains("已用内存"))
        let menu = try repoText("Pulse/MenuBar/MenuBarStatus.swift")
        XCTAssertFalse(menu.contains("releaseNote"))
        XCTAssertFalse(menu.contains("quitSelected"))
        let sidebar = try WiringSourceText.text(for: "ProcessDetailSidebar")
        XCTAssertEqual(occurrenceCount(of: "sidebar.releaseNote", in: sidebar), 1)
    }

    /// Source shape only. Not a VM instance, not NSAlert, not MainActor, not a real quit.
    func testClosedConfirmHelperIsGenerationScopedAndWrittenBack() throws {
        let session = try repoText("Pulse/Models/ProcessQuitSession.swift")
        let helper = try functionBody(named: "releaseClosedForceConfirmation", in: session)
        XCTAssertTrue(helper.contains("cancelForce"))
        XCTAssertTrue(helper.contains("generation"))
        XCTAssertFalse(helper.contains("NSAlert"))
        XCTAssertFalse(helper.contains("ProcessActions"))
        XCTAssertFalse(helper.contains("targetPid ="))
        XCTAssertFalse(session.contains("import AppKit"))
        let outcome = try repoText("Pulse/Models/ProcessQuitOutcome.swift")
        XCTAssertTrue(outcome.contains("if isAbsent(pending.targetPid)"))
        XCTAssertTrue(outcome.contains("pendingForceConfirmation = nil"))
        let force = try functionBody(named: "forceQuitSelected", in: try vmSource())
        XCTAssertLessThan(
            try index(of: "ProcessQuitSession.confirmForce", in: force),
            try index(of: "ProcessQuitSession.releaseClosedForceConfirmation", in: force)
        )
        XCTAssertLessThan(
            try index(of: "ProcessQuitSession.releaseClosedForceConfirmation", in: force),
            try index(of: "quitOutcome = confirming", in: force)
        )
        XCTAssertLessThan(
            try index(of: "ProcessQuitSession.cancelForce", in: force),
            try index(of: "ProcessQuitSession.confirmForce", in: force)
        )
        XCTAssertTrue(force.contains("if !confirmed"))
        XCTAssertTrue(force.contains("ProcessActions.forceTerminate(pid: issued.pid)"))
        XCTAssertFalse(force.contains("NSAlert"))
        let entitlements = try repoText("Pulse/Pulse.entitlements")
        XCTAssertFalse(entitlements.contains("ProcessQuit"))
    }

    private func vmSource() throws -> String {
        try WiringSourceText.text(for: "MemoryDashboardVM")
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
