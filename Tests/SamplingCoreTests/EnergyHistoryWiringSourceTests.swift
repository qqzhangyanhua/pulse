import XCTest
@testable import SamplingCore

/// Source locks for the energy-page history curve. They do not open the Mac window.
final class EnergyHistoryWiringSourceTests: XCTestCase {
    func testAcceptedSuccessRecordsProcessWattsAndFailureDoesNot() throws {
        let vm = try repoText("Pulse/ViewModels/MemoryDashboardVM.swift")
        XCTAssertEqual(
            occurrenceCount(
                of: "energyMachineHistory = recordedEnergyHistory(rows: frame.rows, at: frame.snapshot.capturedAt)",
                in: vm
            ),
            1
        )
        let failure = try braceBody(after: "case .failure:", in: vm)
        XCTAssertFalse(failure.contains("recordedEnergyHistory"))
        XCTAssertFalse(failure.contains("EnergyMachineHistory"))
        let rejected = try braceBody(after: "if !accepted", in: vm)
        XCTAssertFalse(rejected.contains("recordedEnergyHistory"))

        let history = try repoText("Pulse/ViewModels/MemoryDashboardVM+EnergyHistory.swift")
        XCTAssertTrue(history.contains("let known = rows.compactMap(\\.energyWatts)"))
        XCTAssertTrue(history.contains("known.isEmpty ? nil : known.reduce(0, +)"))
        XCTAssertTrue(history.contains("reading.hasInternalBattery"))
        XCTAssertTrue(history.contains("Double(percent)"))
        XCTAssertFalse(history.contains("energyWindowRates"))
        XCTAssertFalse(history.contains("@Published"))
        XCTAssertFalse(history.contains("@MainActor"))
        XCTAssertFalse(history.contains("didSet"))

        let sampler = try repoText("Pulse/Sampling/MemorySampler.swift")
        XCTAssertFalse(sampler.contains("EnergyMachineHistory"))
        let battery = try repoText("Pulse/ViewModels/MemoryDashboardVM+EnergyBattery.swift")
        XCTAssertTrue(battery.contains("energyBatteryReading = reading"))
        XCTAssertTrue(battery.contains(".seconds(30)"))
        XCTAssertFalse(battery.contains("HostMachineReader"))
    }

    func testChartBreaksNilMinutesAndSitsBetweenTheCardAndTheTable() throws {
        let chart = try repoText("Pulse/Views/EnergyHistoryChart.swift")
        XCTAssertTrue(chart.contains("LineMark("))
        XCTAssertTrue(chart.contains("interpolationMethod(.linear)"))
        XCTAssertFalse(chart.contains("catmullRom"))
        XCTAssertFalse(chart.contains("SparklineChart"))
        XCTAssertFalse(chart.contains("?? 0"))
        XCTAssertFalse(chart.contains("整机功耗"))
        XCTAssertTrue(chart.contains("进程能耗合计"))
        XCTAssertTrue(chart.contains("电量"))
        XCTAssertTrue(chart.contains("HistoryCurvePresentation.unavailable"))
        XCTAssertTrue(chart.contains("energyBatteryReading?.hasInternalBattery"))
        XCTAssertTrue(chart.contains("series: .value(\"段\", segment.id)"))

        let dashboard = try repoText("Pulse/Views/MemoryDashboardView.swift")
        let column = try braceBody(after: "var energyResourceColumn", in: dashboard)
        let card = try index(of: "EnergyBatteryCardView()", in: column)
        let curve = try index(of: "EnergyHistoryChart()", in: column)
        let table = try index(of: "ProcessTablePane()", in: column)
        XCTAssertLessThan(card, curve)
        XCTAssertLessThan(curve, table)
        XCTAssertTrue(column.contains(".frame(height: 150)"))
        XCTAssertFalse(column.contains("OverviewSection"))
        let overview = try braceBody(after: "var resourceOverview", in: dashboard)
        XCTAssertFalse(overview.contains("EnergyHistoryChart"))
        XCTAssertTrue(overview.contains("case .energy:"))
        let height = try functionBody(named: "overviewHeight", in: dashboard)
        XCTAssertTrue(height.contains("case .energy:"))
        XCTAssertTrue(height.contains("0"))

        let package = try repoText("Package.swift")
        XCTAssertTrue(package.contains("\"Models/EnergyMachineHistory.swift\""))
        let sources = package.components(separatedBy: "sources:")[1]
        XCTAssertFalse(sources.contains("EnergyHistoryChart.swift"))
        XCTAssertFalse(sources.contains("MemoryDashboardVM+EnergyHistory.swift"))

        let project = try repoText("Pulse.xcodeproj/project.pbxproj")
        for name in [
            "EnergyMachineHistory.swift",
            "EnergyHistoryChart.swift",
            "MemoryDashboardVM+EnergyHistory.swift",
        ] {
            XCTAssertTrue(project.contains("\(name) in Sources"), name)
        }
        XCTAssertTrue(project.contains("path = \"MemoryDashboardVM+EnergyHistory.swift\";"))
        XCTAssertTrue(project.contains("A00000000000000000000070"))
        XCTAssertTrue(project.contains("A00000000000000000000072"))
        XCTAssertTrue(project.contains("A00000000000000000000074"))
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
            throw EnergyHistorySourceError.missing(needle)
        }
        return found
    }

    private func functionBody(named name: String, in source: String) throws -> String {
        let patterns = ["func \(name)(", "private func \(name)("]
        for pattern in patterns {
            guard let range = source.range(of: pattern),
                  let brace = source[range.lowerBound...].firstIndex(of: "{")
            else { continue }
            return try balancedSlice(from: brace, in: source, label: name)
        }
        throw EnergyHistorySourceError.missing(name)
    }

    private func braceBody(after needle: String, in source: String) throws -> String {
        guard let start = source.range(of: needle)?.upperBound,
              let brace = source[start...].firstIndex(of: "{")
        else { throw EnergyHistorySourceError.missing(needle) }
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
        throw EnergyHistorySourceError.missing("balanced brace for \(label)")
    }

    private func occurrenceCount(of needle: String, in haystack: String) -> Int {
        haystack.components(separatedBy: needle).count - 1
    }
}

private enum EnergyHistorySourceError: Error, CustomStringConvertible {
    case missing(String)
    var description: String {
        switch self {
        case .missing(let detail):
            return "missing \(detail)"
        }
    }
}
