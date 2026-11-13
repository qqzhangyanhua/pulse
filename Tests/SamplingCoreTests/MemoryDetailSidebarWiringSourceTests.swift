import XCTest
@testable import SamplingCore

/// Phase 17 sidebar source contract.
///
/// Linux SamplingCore does not compile `Views/` or `ViewModels/`. These tests
/// read source text. They do not instantiate `MemoryDashboardVM`, do not enter
/// SwiftUI, and do not render `DisclosureGroup`. A pass is not a sidebar click,
/// not a snapshot, and not a Mac acceptance.
final class MemoryDetailSidebarWiringSourceTests: XCTestCase {
    func testPresentationModelStaysDarwinFreeAndIsABuildMember() throws {
        let source = try repoText("Pulse/Models/MemoryDetailPresentation.swift")
        XCTAssertFalse(source.contains("import SwiftUI"))
        XCTAssertFalse(source.contains("import Darwin"))
        XCTAssertFalse(source.contains("import AppKit"))
        XCTAssertFalse(source.contains("wholePercent"))
        XCTAssertTrue(source.contains("struct MemoryDetailFieldCopy"))
        XCTAssertTrue(source.contains("enum MemoryDetailPresentation"))
        XCTAssertTrue(source.contains("enum MemoryDetailSamplingWindow"))
        let package = try repoText("Package.swift")
        XCTAssertTrue(package.contains("\"Models/MemoryDetailPresentation.swift\""))
        XCTAssertTrue(package.contains("\"Views\""))
        XCTAssertTrue(package.contains("\"ViewModels\""))
        let project = try repoText("Pulse.xcodeproj/project.pbxproj")
        XCTAssertTrue(project.contains("MemoryDetailPresentation.swift in Sources"))
        XCTAssertTrue(project.contains("path = MemoryDetailPresentation.swift;"))
    }

    func testSidebarUsesPageGatedTitlesAndOneCollapsedDisclosure() throws {
        let sidebar = try WiringSourceText.text(for: "ProcessDetailSidebar")
        XCTAssertEqual(occurrenceCount(of: "DisclosureGroup(", in: sidebar), 1)
        XCTAssertEqual(occurrenceCount(of: "@State private var samplingWindowExpanded = false", in: sidebar), 1)
        XCTAssertFalse(sidebar.contains("@Published"))
        XCTAssertFalse(sidebar.contains("UserDefaults"))
        XCTAssertFalse(sidebar.contains("Timer"))
        XCTAssertFalse(sidebar.contains("evaluate("))
        XCTAssertFalse(sidebar.contains("evaluate(frozen"))
        XCTAssertFalse(sidebar.contains("frozenDetail"))
        XCTAssertFalse(sidebar.contains("quitOutcome"))

        let detail = try functionBody(named: "detailBody", in: sidebar)
        let slotIndex = try index(of: "vm.memoryGrowthSlot", in: detail)
        let gate = "vm.sidebar.showsLiveTrend && vm.selectedPage == .memory"
        let gateIndex = try index(of: gate, in: detail)
        let disclosureIndex = try index(of: "samplingWindowDisclosure", in: detail)
        let chartIndex = try index(of: "memoryChart(detail)", in: detail)
        XCTAssertLessThan(slotIndex, gateIndex)
        XCTAssertLessThan(gateIndex, disclosureIndex)
        XCTAssertLessThan(disclosureIndex, chartIndex)
        XCTAssertEqual(occurrenceCount(of: "samplingWindowDisclosure", in: detail), 1)

        let disclosure = try functionBody(named: "samplingWindowDisclosure", in: sidebar)
        XCTAssertTrue(disclosure.contains("DisclosureGroup(isExpanded: $samplingWindowExpanded)"))
        XCTAssertTrue(disclosure.contains("MemoryDetailSamplingWindow.summary"))
        XCTAssertTrue(disclosure.contains("MemoryDetailSamplingWindow.body"))
        XCTAssertFalse(disclosure.contains("evaluate"))

        let metrics = try functionBody(named: "metrics", in: sidebar)
        XCTAssertTrue(metrics.contains("displayedMemoryRow(detail.row)"))
        XCTAssertTrue(metrics.contains("memoryField(row)"))
        XCTAssertTrue(metrics.contains("title: memory.title"))
        XCTAssertTrue(metrics.contains("caption: memory.caption"))
        XCTAssertTrue(metrics.contains("help: memory.help"))
        XCTAssertTrue(metrics.contains("title: \"CPU\""))
        XCTAssertFalse(metrics.contains("memoryGrowthSlot"))
        XCTAssertFalse(metrics.contains("title: \"内存\""))

        let chart = try functionBody(named: "memoryChart", in: sidebar)
        XCTAssertTrue(chart.contains("vm.selectedPage == .memory"))
        XCTAssertTrue(chart.contains("curveRow: detail.row"))
        XCTAssertTrue(chart.contains("memoryField(displayedMemoryRow(detail.row))"))
        XCTAssertTrue(chart.contains("memoryField("))
        XCTAssertFalse(chart.contains("memoryField(detail.row)"))
        XCTAssertFalse(chart.contains("title: \"内存\""))
        XCTAssertFalse(chart.contains("memoryGrowthSlot"))
        XCTAssertTrue(chart.contains("正在采集内存曲线"))

        let trend = try functionBody(named: "memoryTrend", in: sidebar)
        XCTAssertTrue(trend.contains("slot.title"))
        XCTAssertTrue(trend.contains("slot.caption"))
        XCTAssertTrue(trend.contains("slot.basis"))

        let metric = try repoText("Pulse/Views/SharedUI.swift")
        XCTAssertTrue(metric.contains("struct SidebarMetric"))
        XCTAssertTrue(metric.contains("var help: String? = nil"))
        XCTAssertTrue(metric.contains(".help(help)"))
        XCTAssertTrue(sidebar.contains("samples.count < 2"))
    }

    /// Already-held call paths. Not the resident-copy red.
    /// Source text only: not a VM instance, not SwiftUI, not a real pid switch.
    func testFrozenGuardPidSwitchAndChartPlaceholderStayUntouched() throws {
        let vm = try WiringSourceText.text(for: "MemoryDashboardVM")
        let slot = try functionBody(named: "memoryGrowthSlot", in: vm)
        XCTAssertTrue(slot.contains("guard sidebar.showsLiveTrend else { return nil }"))
        XCTAssertLessThan(
            try index(of: "sidebar.showsLiveTrend", in: slot),
            try index(of: "MemoryGrowthSidebar.slot", in: slot)
        )
        XCTAssertFalse(slot.contains("evaluate"))
        XCTAssertFalse(slot.contains("frozenDetail"))
        XCTAssertFalse(vm.contains("DisclosureGroup"))
        XCTAssertFalse(vm.contains("samplingWindowExpanded"))
        XCTAssertFalse(vm.contains("MemoryDetailSamplingWindow"))
        XCTAssertFalse(vm.contains("MemoryDetailPresentation"))
        XCTAssertEqual(occurrenceCount(of: "@Published", in: vm), 42, "battery card adds energyBatteryCard; energy page adds energyWindowRates; hour ranking adds energyRankingSpan and energyHourRates; app grouping adds groupedByApp; permission footnote adds processPermissionFootnote; energy history adds energyMachineHistory; exited hour ranking adds exitedEnergyProcesses; thermal advice adds thermalAdvice; GPU page adds gpuPage; connection card adds hostConnection; Wi-Fi signal adds hostWiFi; public IP adds publicIPRequest; SSID permission adds ssidPermission; chip temperature adds chipTemperature")

        let didSet = try braceBody(after: "var selectedPid", in: vm)
        XCTAssertTrue(didSet.contains("detail = nil"))
        XCTAssertTrue(didSet.contains("let pid = selectedPid"))
        XCTAssertEqual(
            try lineContaining("sampler.setSelectedPid", in: didSet).trimmingCharacters(in: .whitespaces),
            "Task { await sampler.setSelectedPid(pid) }"
        )
        XCTAssertFalse(didSet.contains("samplingWindow"))
        XCTAssertFalse(didSet.contains("MemoryDetail"))

        let selectPage = try functionBody(named: "selectPage", in: vm)
        XCTAssertFalse(selectPage.contains("setSelectedPid"))
        XCTAssertFalse(selectPage.contains("selectedMemorySeries"))

        let apply = try functionBody(named: "applySample", in: vm)
        XCTAssertFalse(apply.contains("MemoryDetailPresentation"))
        XCTAssertFalse(apply.contains("DisclosureGroup"))
        XCTAssertTrue(apply.contains("rows = frame.rows"))

        let sampler = try repoText("Pulse/Sampling/MemorySampler.swift")
        let setter = try functionBody(named: "setSelectedPid", in: sampler)
        XCTAssertTrue(setter.contains("guard selectedPid != pid else { return }"))
        XCTAssertTrue(setter.contains("selectedMemorySeries.removeAll(keepingCapacity: true)"))
        XCTAssertTrue(setter.contains("selectedCPUSeries.removeAll(keepingCapacity: true)"))
        XCTAssertFalse(setter.contains("topMemoryStore"))
        XCTAssertFalse(setter.contains("adopt"))
        XCTAssertTrue(sampler.contains("topMemoryStore.adopt(pid: selectedPid, series: selectedMemorySeries)"))
        XCTAssertTrue(sampler.contains("selectedMemorySeries = shared"))

        let signal = try repoText("Pulse/Models/MemoryGrowthSignal.swift")
        let evaluate = try functionBody(named: "evaluate", in: signal)
        XCTAssertTrue(evaluate.contains("guard samples.count >= minSamples else"))
        XCTAssertTrue(evaluate.contains("guard netIncrease > deltaThreshold else"))
        XCTAssertTrue(evaluate.contains("samples[index].value > samples[index - 1].value"))
        XCTAssertTrue(evaluate.contains("positiveSteps * riseFloorDenominator >= stepCount * riseFloorNumerator"))
        XCTAssertFalse(evaluate.contains("basis"))

        let list = try functionBody(named: "badge", in: signal)
        XCTAssertFalse(list.contains("memoryGrowthSlot"))
        XCTAssertTrue(list.contains("seriesByPid[rowPid]"))

        let sidebar = try WiringSourceText.text(for: "ProcessDetailSidebar")
        let absent = try functionBody(named: "absentRecordBody", in: sidebar)
        XCTAssertFalse(absent.contains("DisclosureGroup"))
        XCTAssertFalse(absent.contains("samplingWindow"))
        let empty = try functionBody(named: "emptyBody", in: sidebar)
        XCTAssertFalse(empty.contains("DisclosureGroup"))
        XCTAssertFalse(empty.contains("samplingWindow"))
        let cpu = try functionBody(named: "cpuChart", in: sidebar)
        XCTAssertTrue(cpu.contains("title: \"CPU\""))
        XCTAssertTrue(sidebar.contains("samples.count < 2"))
        XCTAssertTrue(sidebar.contains("正在采集内存曲线"))
        XCTAssertFalse(sidebar.contains("NSAlert"))
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
        throw SourceContractError.missing(name)
    }

    private func braceBody(after needle: String, in source: String) throws -> String {
        guard let start = source.range(of: needle)?.upperBound,
              let brace = source[start...].firstIndex(of: "{")
        else { throw SourceContractError.missing(needle) }
        return try balancedSlice(from: brace, in: source, label: needle)
    }

    private func lineContaining(_ needle: String, in source: String) throws -> String {
        guard let line = source.components(separatedBy: .newlines).first(where: { $0.contains(needle) }) else {
            throw SourceContractError.missing(needle)
        }
        return line
    }

    private func index(of needle: String, in source: String) throws -> String.Index {
        guard let found = source.range(of: needle)?.lowerBound else {
            throw SourceContractError.missing(needle)
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
        throw SourceContractError.missing("balanced brace for \(label)")
    }

    private func occurrenceCount(of needle: String, in haystack: String) -> Int {
        haystack.components(separatedBy: needle).count - 1
    }
}

private enum SourceContractError: Error, CustomStringConvertible {
    case missing(String)
    var description: String {
        switch self {
        case .missing(let detail): return "missing \(detail)"
        }
    }
}
