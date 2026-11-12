import XCTest
@testable import SamplingCore

/// Source locks for the production wiring. They do not open the Mac window.
final class EnergyPageWiringSourceTests: XCTestCase {
    func testSamplerConsumesTheEnumeratorReadingOnceAndSkipsTheListFailureBranch() throws {
        let enumerator = try repoText("Pulse/Sampling/ProcessEnumerator.swift")
        let sampler = try repoText("Pulse/Sampling/MemorySampler.swift")
        XCTAssertTrue(enumerator.contains("energyNanojoules: info.ri_energy_nj"))
        XCTAssertTrue(enumerator.contains("interruptWakeups: info.ri_interrupt_wkups"))
        XCTAssertEqual(occurrenceCount(of: "pulse_proc_pid_rusage(", in: enumerator), 2)
        XCTAssertFalse(enumerator.contains("info.ri_billed_energy"))
        XCTAssertFalse(sampler.contains("ri_energy_nj"))
        XCTAssertFalse(sampler.contains("ri_billed_energy"))
        XCTAssertFalse(sampler.contains("IOPSGetTimeRemainingEstimate"))
        XCTAssertEqual(occurrenceCount(of: "proc_pid_rusage", in: sampler), 0)
        XCTAssertTrue(sampler.contains("ProcessEnergyLoad.advance"))
        XCTAssertTrue(sampler.contains("energyWatts: energy.rates.watts"))
        XCTAssertTrue(sampler.contains("wakeupsPerSecond: energy.rates.wakeupsPerSecond"))
        XCTAssertTrue(sampler.contains("energyWindow.advance(listed:"))
        XCTAssertTrue(sampler.contains("listSucceeded: true"))
        XCTAssertFalse(sampler.contains("listSucceeded: false"))
        XCTAssertEqual(occurrenceCount(of: "energyWindow.advance(", in: sampler), 1)
        XCTAssertEqual(occurrenceCount(of: "energyMinuteLedger.advance(", in: sampler), 1)
        XCTAssertTrue(sampler.contains("names: listedNames"))
        XCTAssertTrue(sampler.contains("now: capturedAt"))
        XCTAssertTrue(sampler.contains("exitedEnergyProcesses: energyMinuteLedger.exitedProcesses"))
        XCTAssertTrue(sampler.contains("energyLiveGenerations: energyMinuteLedger.liveGenerations"))
        let failure = try braceBody(after: "ProcessEnumerator.list() else", in: sampler)
        XCTAssertFalse(failure.contains("energyWindow"))
        XCTAssertFalse(failure.contains("ProcessEnergyWindow"))
        XCTAssertFalse(failure.contains("energyMinute"))
        XCTAssertFalse(failure.contains("Ledger"))
        XCTAssertTrue(failure.contains("processListFailed: true"))
        let package = try repoText("Package.swift")
        XCTAssertTrue(package.contains("\"Sampling/ProcessEnergyWindow.swift\""))
        XCTAssertTrue(package.contains("\"Sampling/ProcessEnergyMinuteLedger.swift\""))
        XCTAssertTrue(package.contains("\"Models/EnergyPage.swift\""))
        let project = try repoText("Pulse.xcodeproj/project.pbxproj")
        XCTAssertTrue(project.contains("ProcessEnergyWindow.swift in Sources"))
        XCTAssertTrue(project.contains("ProcessEnergyMinuteLedger.swift in Sources"))
        XCTAssertTrue(project.contains("EnergyPage.swift in Sources"))
        XCTAssertTrue(project.contains("EnergyProcessTable.swift in Sources"))
        XCTAssertTrue(project.contains("MemoryDashboardVM+EnergyRanking.swift in Sources"))
        XCTAssertEqual(
            occurrenceCount(of: "isa = PBXBuildFile;", in: project),
            109,
            "minute ledger adds ProcessEnergyMinuteLedger.swift and hour ranking adds MemoryDashboardVM+EnergyRanking.swift; energy history adds EnergyMachineHistory.swift, EnergyHistoryChart.swift, and MemoryDashboardVM+EnergyHistory.swift; thermal advice adds ThermalAdvice.swift; thermal advice throttle adds ThermalAdviceThrottle.swift; thermal advice view model adds MemoryDashboardVM+ThermalAdvice.swift"
        )
        XCTAssertTrue(project.contains("ProcessDetailSidebar+Energy.swift in Sources"))
    }

    func testExitedSelectionHidesOnlyTheQuitButtons() throws {
        let energy = try repoText("Pulse/Views/ProcessDetailSidebar+Energy.swift")
        let controls = try functionBody(named: "quitControls", in: energy)
        XCTAssertFalse(controls.contains("if !vm.selectedEnergyExitedOnly"))
        XCTAssertTrue(
            controls.contains("ProcessDetailSidebarQuitControls(showsQuitButtons: !vm.selectedEnergyExitedOnly)")
        )
        let quit = try repoText("Pulse/Views/ProcessDetailSidebarQuitControls.swift")
        let buttons = try braceBody(after: "if showsQuitButtons", in: quit)
        XCTAssertTrue(buttons.contains("强制退出…"))
        XCTAssertTrue(buttons.contains("Label(\"退出\""))
        XCTAssertFalse(buttons.contains("正在退出…"))
        XCTAssertFalse(buttons.contains("quitMessage"))
        XCTAssertFalse(buttons.contains("releaseNote"))
        let body = try functionBody(named: "body", in: quit)
        XCTAssertTrue(body.contains("正在退出…"))
        XCTAssertTrue(body.contains("sidebar.quitMessage"))
        XCTAssertTrue(body.contains("sidebar.releaseNote"))
        let session = try repoText("Pulse/ViewModels/MemoryDashboardVM+QuitSession.swift")
        XCTAssertEqual(occurrenceCount(of: "guard !selectedEnergyExitedOnly else { return }", in: session), 2)
    }

    func testEnergyTableReadsWindowRatesAndTheCPUTableKeepsTwoFrameWatts() throws {
        let tableURL = repoRoot().appendingPathComponent("Pulse/Views/EnergyProcessTable.swift")
        XCTAssertTrue(FileManager.default.fileExists(atPath: tableURL.path))
        guard FileManager.default.fileExists(atPath: tableURL.path) else { return }
        let table = try String(contentsOf: tableURL, encoding: .utf8)
        XCTAssertFalse(table.contains("?? -1"))
        XCTAssertFalse(table.contains("energyWatts ??"))
        XCTAssertFalse(table.contains("row.energyWatts"))
        XCTAssertFalse(table.contains("row.wakeupsPerSecond"))
        XCTAssertTrue(table.contains("activeEnergyRates"))
        XCTAssertFalse(table.contains("energyWindowRates"))
        XCTAssertTrue(table.contains("Text(\"1 分钟\")"))
        XCTAssertTrue(table.contains("Text(\"1 小时\")"))
        XCTAssertTrue(table.contains(".pickerStyle(.segmented)"))
        XCTAssertTrue(table.contains("ProcessEnergyText.watts"))
        XCTAssertTrue(table.contains("ProcessEnergyText.wakeups"))
        XCTAssertTrue(table.contains("EnergyPageCopy.headline"))
        XCTAssertTrue(table.contains("EnergyPageCopy.explanation"))
        XCTAssertTrue(table.contains("EnergyPageCopy.emptyTitle"))
        XCTAssertTrue(table.contains("EnergyPageCopy.filteredEmptyTitle"))
        XCTAssertTrue(table.contains("EnergyPage.ranked("))
        XCTAssertTrue(table.contains("EnergyPage.exitedStatus"))
        XCTAssertTrue(table.contains("entry.isQuitTarget"))
        XCTAssertFalse(table.contains("EnergyPage.display("))
        XCTAssertFalse(table.contains("selection: $vm.selectedPid"))
        XCTAssertFalse(table.contains("ProcessDetailSidebar"))
        XCTAssertFalse(table.contains("IOPSGetTimeRemainingEstimate"))

        let pane = try repoText("Pulse/Views/ProcessTablePane.swift")
        XCTAssertTrue(pane.contains("vm.selectedPage == .cpu"))
        XCTAssertTrue(pane.contains("ProcessEnergyText.watts(row.energyWatts)"))
        XCTAssertTrue(pane.contains("EnergyProcessTable()"))
        XCTAssertEqual(occurrenceCount(of: "Button(\"复制\")", in: pane), 1)

        let dashboard = try repoText("Pulse/Views/MemoryDashboardView.swift")
        let energyColumn = try braceBody(after: "var energyResourceColumn", in: dashboard)
        XCTAssertTrue(energyColumn.contains("ProcessTablePane()"))
        XCTAssertTrue(energyColumn.contains("ProcessDetailSidebar()"))
        XCTAssertTrue(energyColumn.contains("HSplitView"))
        XCTAssertFalse(energyColumn.contains("OverviewSection"))
        XCTAssertFalse(energyColumn.contains("IOPSGetTimeRemainingEstimate"))
        XCTAssertTrue(dashboard.contains("AppGroupChrome.showsToggle(page: vm.selectedPage)"))
        XCTAssertTrue(dashboard.contains("ProcessDetailSidebar()"))

        let shared = try repoText("Pulse/Views/SharedUI.swift")
        let cpu = try index(of: "case cpu", in: shared)
        let energy = try index(of: "case energy = \"能耗\"", in: shared)
        let disk = try index(of: "case disk", in: shared)
        XCTAssertLessThan(cpu, energy)
        XCTAssertLessThan(energy, disk)
        XCTAssertTrue(shared.contains("case .energy: return \"bolt\""))
        XCTAssertFalse(shared.contains("keyboardShortcut"))

        let app = try repoText("Pulse/PulseApp.swift")
        XCTAssertFalse(app.contains("selectPage(.energy)"))
        XCTAssertFalse(app.contains("Button(\"能耗\")"))
        XCTAssertTrue(app.contains("case .memory, .cpu, .disk, .network, .energy:"))
        XCTAssertTrue(app.contains("activeEnergyRates"))
        XCTAssertFalse(app.contains("energyWindowRates"))
        let status = try repoText("Pulse/MenuBar/MenuBarStatus.swift")
        XCTAssertTrue(status.contains("self != .machine"))
        XCTAssertFalse(status.contains("self != .energy"))
        let popover = try repoText("Pulse/MenuBar/MenuBarPopoverView.swift")
        XCTAssertFalse(popover.contains("能耗"))
        XCTAssertFalse(popover.contains("energyWindow"))
        let vm = try repoText("Pulse/ViewModels/MemoryDashboardVM.swift")
        let sorted = try functionBody(named: "sortedRows", in: vm)
        XCTAssertTrue(sorted.contains("EnergyPage.sorted"))
        XCTAssertTrue(sorted.contains("activeEnergyRates"))
        XCTAssertFalse(sorted.contains("energyWindowRates"))
        XCTAssertFalse(sorted.contains("?? -1"))
        XCTAssertFalse(sorted.contains("energyWatts"))
        let failure = try braceBody(after: "case .failure:", in: vm)
        XCTAssertFalse(failure.contains("energyWindowRates"))
        XCTAssertFalse(failure.contains("energyHourRates"))
        XCTAssertFalse(failure.contains("exitedEnergyProcesses"))
        let apply = try functionBody(named: "applySample", in: vm)
        XCTAssertTrue(apply.contains("energyLiveGenerations = frame.energyLiveGenerations"))
        XCTAssertTrue(apply.contains("reconcileEnergySelectionGeneration()"))
        XCTAssertEqual(occurrenceCount(of: "didSet", in: vm), 4)
        XCTAssertFalse(vm.contains("@Published private var selectedEnergyGeneration"))
        XCTAssertTrue(vm.contains("private var selectedEnergyGeneration: Int?"))
        XCTAssertFalse(vm.contains("selectedPid = nil"))
        let ranking = try repoText("Pulse/ViewModels/MemoryDashboardVM+EnergyRanking.swift")
        XCTAssertTrue(ranking.contains("case .oneHour:"))
        XCTAssertTrue(ranking.contains("return energyHourRates"))
        XCTAssertTrue(ranking.contains("return energyWindowRates"))
        XCTAssertFalse(ranking.contains("@Published"))
        XCTAssertFalse(ranking.contains("@MainActor"))
        XCTAssertFalse(ranking.contains("didSet"))
        XCTAssertTrue(vm.contains("@Published var energyRankingSpan = EnergyRankingSpan.oneMinute"))
        XCTAssertTrue(vm.contains("@Published private(set) var energyHourRates: [Int32: ProcessEnergyRates] = [:]"))
        XCTAssertTrue(vm.contains("@Published private(set) var exitedEnergyProcesses: [ExitedEnergyProcess] = []"))
        let snapshot = try repoText("Pulse/Models/SnapshotExport.swift")
        XCTAssertFalse(snapshot.contains("energyWindow"))
        XCTAssertFalse(snapshot.contains("ri_energy_nj"))
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

    private func index(of needle: String, in source: String) throws -> String.Index {
        guard let found = source.range(of: needle)?.lowerBound else {
            throw EnergySourceError.missing(needle)
        }
        return found
    }

    private func functionBody(named name: String, in source: String) throws -> String {
        let patterns = ["func \(name)(", "private func \(name)(", "var \(name):"]
        for pattern in patterns {
            guard let range = source.range(of: pattern),
                  let brace = source[range.lowerBound...].firstIndex(of: "{")
            else { continue }
            return try balancedSlice(from: brace, in: source, label: name)
        }
        throw EnergySourceError.missing(name)
    }

    private func braceBody(after needle: String, in source: String) throws -> String {
        guard let start = source.range(of: needle)?.upperBound,
              let brace = source[start...].firstIndex(of: "{")
        else { throw EnergySourceError.missing(needle) }
        return try balancedSlice(from: brace, in: source, label: needle)
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
        throw EnergySourceError.missing("balanced brace for \(label)")
    }

    private func occurrenceCount(of needle: String, in haystack: String) -> Int {
        haystack.components(separatedBy: needle).count - 1
    }
}

private enum EnergySourceError: Error, CustomStringConvertible {
    case missing(String)
    var description: String {
        switch self {
        case .missing(let detail):
            return "missing \(detail)"
        }
    }
}
