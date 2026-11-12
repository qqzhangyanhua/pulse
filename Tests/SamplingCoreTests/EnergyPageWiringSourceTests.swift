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
        let failure = try braceBody(after: "ProcessEnumerator.list() else", in: sampler)
        XCTAssertFalse(failure.contains("energyWindow"))
        XCTAssertFalse(failure.contains("ProcessEnergyWindow"))
        XCTAssertTrue(failure.contains("processListFailed: true"))
        let package = try repoText("Package.swift")
        XCTAssertTrue(package.contains("\"Sampling/ProcessEnergyWindow.swift\""))
        XCTAssertTrue(package.contains("\"Models/EnergyPage.swift\""))
        let project = try repoText("Pulse.xcodeproj/project.pbxproj")
        XCTAssertTrue(project.contains("ProcessEnergyWindow.swift in Sources"))
        XCTAssertTrue(project.contains("EnergyPage.swift in Sources"))
        XCTAssertTrue(project.contains("EnergyProcessTable.swift in Sources"))
        XCTAssertEqual(
            occurrenceCount(of: "isa = PBXBuildFile;", in: project),
            100,
            "energy sidebar adds ProcessDetailSidebar+Energy.swift"
        )
        XCTAssertTrue(project.contains("ProcessDetailSidebar+Energy.swift in Sources"))
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
        XCTAssertTrue(table.contains("energyWindowRates"))
        XCTAssertTrue(table.contains("ProcessEnergyText.watts"))
        XCTAssertTrue(table.contains("ProcessEnergyText.wakeups"))
        XCTAssertTrue(table.contains("EnergyPageCopy.headline"))
        XCTAssertTrue(table.contains("EnergyPageCopy.explanation"))
        XCTAssertTrue(table.contains("EnergyPageCopy.emptyTitle"))
        XCTAssertTrue(table.contains("EnergyPageCopy.filteredEmptyTitle"))
        XCTAssertTrue(table.contains("EnergyPage.display("))
        XCTAssertFalse(table.contains("1 小时"))
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
        XCTAssertTrue(app.contains("energyWindowRates"))
        let status = try repoText("Pulse/MenuBar/MenuBarStatus.swift")
        XCTAssertTrue(status.contains("self != .machine"))
        XCTAssertFalse(status.contains("self != .energy"))
        let popover = try repoText("Pulse/MenuBar/MenuBarPopoverView.swift")
        XCTAssertFalse(popover.contains("能耗"))
        XCTAssertFalse(popover.contains("energyWindow"))
        let vm = try repoText("Pulse/ViewModels/MemoryDashboardVM.swift")
        let sorted = try functionBody(named: "sortedRows", in: vm)
        XCTAssertTrue(sorted.contains("EnergyPage.sorted"))
        XCTAssertTrue(sorted.contains("energyWindowRates"))
        XCTAssertFalse(sorted.contains("?? -1"))
        XCTAssertFalse(sorted.contains("energyWatts"))
        let failure = try braceBody(after: "case .failure:", in: vm)
        XCTAssertFalse(failure.contains("energyWindowRates"))
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
