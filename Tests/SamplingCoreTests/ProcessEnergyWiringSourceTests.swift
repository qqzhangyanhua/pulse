import XCTest

/// Source read for the one rusage call and the CPU-page columns. Not a GUI test.
final class ProcessEnergyWiringSourceTests: XCTestCase {
    func testEnergyUsesTheExistingRusageCallAndSamplerTicks() throws {
        let reader = try repoText("Pulse/Sampling/ProcessEnumerator.swift")
        XCTAssertEqual(occurrenceCount(of: "pulse_proc_pid_rusage(", in: reader), 2)
        XCTAssertTrue(reader.contains("billedEnergyNanojoules: info.ri_billed_energy"))
        XCTAssertTrue(reader.contains("idleWakeups: info.ri_pkg_idle_wkups"))
        XCTAssertTrue(reader.contains("billedEnergyNanojoules: rusage?.billedEnergyNanojoules"))
        XCTAssertTrue(reader.contains("idleWakeups: rusage?.idleWakeups"))

        let sampler = try repoText("Pulse/Sampling/MemorySampler.swift")
        XCTAssertEqual(occurrenceCount(of: "proc_pid_rusage", in: sampler), 0)
        XCTAssertTrue(sampler.contains("energyTicks"))
        XCTAssertTrue(sampler.contains("ProcessEnergyLoad.advance"))
        XCTAssertTrue(sampler.contains("energyWatts: energy.rates.watts"))
        XCTAssertTrue(sampler.contains("idleWakeupsPerSecond: energy.rates.idleWakeupsPerSecond"))
        XCTAssertFalse(sampler.contains("energyReadingIsPartial: true"))

        let group = try repoText("Pulse/Models/AppGroupProjection.swift")
        XCTAssertTrue(group.contains("let energy = ProcessEnergyGroup.sum(members.map(\\.energyWatts))"))
        XCTAssertTrue(group.contains("let wakeups = ProcessEnergyGroup.sum(members.map(\\.idleWakeupsPerSecond))"))

        let package = try repoText("Package.swift")
        XCTAssertTrue(package.contains("\"Sampling/ProcessEnergy.swift\""))
        let project = try repoText("Pulse.xcodeproj/project.pbxproj")
        XCTAssertTrue(project.contains("ProcessEnergy.swift in Sources"))
        XCTAssertTrue(project.contains("path = ProcessEnergy.swift;"))
    }

    func testCPUTableAndSidebarShowWattsAndWakeups() throws {
        let pane = try WiringSourceText.text(for: "ProcessTablePane")
        XCTAssertTrue(pane.contains("sortHeader(ProcessColumnTitle.energy, column: .energy, trailing: true)"))
        XCTAssertTrue(pane.contains("sortHeader(ProcessColumnTitle.idleWakeups, column: .idleWakeups, trailing: true)"))
        XCTAssertTrue(pane.contains("vm.selectedPage == .cpu"))
        XCTAssertTrue(pane.contains("ProcessEnergyText.watts(row.energyWatts)"))
        XCTAssertTrue(pane.contains("ProcessEnergyText.wakeups(row.idleWakeupsPerSecond)"))
        XCTAssertFalse(pane.contains("部分读数"))
        XCTAssertFalse(pane.contains("部分按驻留内存"))

        let sidebar = try WiringSourceText.text(for: "ProcessDetailSidebar")
        let cpu = try functionBody(named: "cpuResourceDetail", in: sidebar)
        XCTAssertTrue(cpu.contains("ProcessEnergyText.impactTitle"))
        XCTAssertTrue(cpu.contains("ProcessEnergyText.idleWakeTitle"))
        XCTAssertTrue(cpu.contains("ProcessEnergyText.watts(cpu.energyWatts)"))
        XCTAssertTrue(cpu.contains("ProcessEnergyText.wakeups(cpu.idleWakeupsPerSecond)"))
        XCTAssertTrue(cpu.contains("ProcessEnergyText.caption(isPartial: cpu.energyReadingIsPartial)"))
        XCTAssertTrue(cpu.contains("ProcessEnergyText.caption(isPartial: cpu.idleWakeupReadingIsPartial)"))

        let projection = try functionBody(named: "displayedProjection", in: sidebar)
        XCTAssertTrue(projection.contains("displayedMemoryRow(detail.row)"))
        XCTAssertTrue(projection.contains("memorySeries: detail.memorySeries"))
        XCTAssertTrue(projection.contains("cpuSeries: detail.cpuSeries"))
        let groupedRow = try functionBody(named: "displayedMemoryRow", in: sidebar)
        XCTAssertTrue(groupedRow.contains("AppGroupChrome.applies(on: vm.selectedPage)"))
        XCTAssertTrue(groupedRow.contains("vm.sortedRows.first { $0.pid == row.pid }"))
        let chart = try functionBody(named: "memoryChart", in: sidebar)
        XCTAssertTrue(chart.contains("samples: detail.memorySeries"))
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
        throw WiringReadError.missing(name)
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
        throw WiringReadError.missing("balanced brace for \(label)")
    }

    private func occurrenceCount(of needle: String, in haystack: String) -> Int {
        haystack.components(separatedBy: needle).count - 1
    }
}

private enum WiringReadError: Error, CustomStringConvertible {
    case missing(String)
    var description: String {
        switch self {
        case .missing(let detail): return "missing \(detail)"
        }
    }
}
