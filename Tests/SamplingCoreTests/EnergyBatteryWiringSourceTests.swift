import XCTest
@testable import SamplingCore

/// Source locks for the energy-page battery card. They do not open the Mac window.
final class EnergyBatteryWiringSourceTests: XCTestCase {
    func testMappingStaysPortableAndTheReaderStaysDarwinOnly() throws {
        let model = try repoText("Pulse/Models/EnergyBattery.swift")
        XCTAssertFalse(model.contains("import IOKit"))
        XCTAssertFalse(model.contains("import Darwin"))
        XCTAssertFalse(model.contains("ProcessInfo"))

        let package = try repoText("Package.swift")
        XCTAssertTrue(package.contains("\"Models/EnergyBattery.swift\""))
        XCTAssertTrue(package.contains("\"Sampling/EnergyBatteryReader.swift\""))
        let excluded = package.components(separatedBy: "exclude:")[1].components(separatedBy: "sources:")[0]
        XCTAssertTrue(excluded.contains("EnergyBatteryReader.swift"))
        XCTAssertFalse(excluded.contains("EnergyBattery.swift"))
        let sources = package.components(separatedBy: "sources:")[1]
        XCTAssertFalse(sources.contains("EnergyBatteryReader.swift"))

        let reader = try repoText("Pulse/Sampling/EnergyBatteryReader.swift")
        XCTAssertTrue(reader.contains("kIOPSInternalBatteryType"))
        XCTAssertTrue(reader.contains("IOPSGetTimeRemainingEstimate()"))
        XCTAssertTrue(reader.contains("kIOPSTimeToFullChargeKey"))
        XCTAssertTrue(reader.contains("kIOPSIsChargingKey"))
        XCTAssertFalse(reader.contains("kIOPSUPSType"))
        XCTAssertFalse(reader.contains("kIOPSTimeToEmptyKey"))
        XCTAssertFalse(reader.contains("AppleSmartBattery"))
        XCTAssertFalse(reader.contains("energyWatts"))

        let sampler = try repoText("Pulse/Sampling/MemorySampler.swift")
        XCTAssertFalse(sampler.contains("IOPSGetTimeRemainingEstimate"))
        XCTAssertFalse(sampler.contains("EnergyBatteryReader"))
        let host = try repoText("Pulse/Sampling/HostMachineReader.swift")
        XCTAssertFalse(host.contains("IOPSGetTimeRemainingEstimate"))
        XCTAssertFalse(host.contains("kIOPSTimeToFullChargeKey"))
    }

    func testEnergyPageReadsOnEntryAndStopsWhenLeaving() throws {
        let vm = try repoText("Pulse/ViewModels/MemoryDashboardVM.swift")
        let focus = try functionBody(named: "focusMemoryPage", in: vm)
        let select = try functionBody(named: "selectPage", in: vm)
        XCTAssertTrue(focus.contains("syncEnergyBatteryWatch()"))
        XCTAssertTrue(select.contains("syncEnergyBatteryWatch()"))
        XCTAssertTrue(vm.contains("energyBatteryRefreshTask?.cancel()"))
        XCTAssertTrue(vm.contains("@Published var energyBatteryCard: EnergyBatteryCard?"))

        let watch = try repoText("Pulse/ViewModels/MemoryDashboardVM+EnergyBattery.swift")
        let sync = try functionBody(named: "syncEnergyBatteryWatch", in: watch)
        XCTAssertTrue(sync.contains("selectedPage == .energy"))
        XCTAssertTrue(sync.contains("energyBatteryRefreshTask?.cancel()"))
        XCTAssertTrue(sync.contains(".seconds(30)"))
        XCTAssertFalse(sync.contains("Timer"))
        let refresh = try functionBody(named: "refreshEnergyBattery", in: watch)
        XCTAssertTrue(refresh.contains("EnergyBatteryReader.read()"))
        XCTAssertTrue(refresh.contains("EnergyBattery.card("))
        XCTAssertFalse(watch.contains("IOPSGetTimeRemainingEstimate"))
        XCTAssertFalse(watch.contains("HostMachineReader"))
    }

    func testCardSitsAboveTheEnergyTableAndNowhereElse() throws {
        let dashboard = try repoText("Pulse/Views/MemoryDashboardView.swift")
        let column = try braceBody(after: "var energyResourceColumn", in: dashboard)
        let card = try index(of: "EnergyBatteryCardView()", in: column)
        let table = try index(of: "ProcessTablePane()", in: column)
        XCTAssertLessThan(card, table)
        XCTAssertTrue(column.contains("vm.energyBatteryCard != nil"))
        XCTAssertFalse(column.contains("ProcessDetailSidebar"))
        XCTAssertFalse(column.contains("OverviewSection"))

        let tableSource = try repoText("Pulse/Views/EnergyProcessTable.swift")
        XCTAssertFalse(tableSource.contains("EnergyBattery"))
        XCTAssertFalse(tableSource.contains("IOPSGetTimeRemainingEstimate"))

        let cardView = try repoText("Pulse/Views/EnergyBatteryCardView.swift")
        XCTAssertTrue(cardView.contains("card.percent"))
        XCTAssertTrue(cardView.contains("card.power"))
        XCTAssertTrue(cardView.contains("card.lowPowerMode"))
        XCTAssertTrue(cardView.contains("card.time"))
        XCTAssertFalse(cardView.contains("ProcessDetailSidebar"))

        let project = try repoText("Pulse.xcodeproj/project.pbxproj")
        for name in [
            "EnergyBattery.swift",
            "EnergyBatteryReader.swift",
            "EnergyBatteryCardView.swift",
            "MemoryDashboardVM+EnergyBattery.swift",
        ] {
            XCTAssertTrue(project.contains("\(name) in Sources"), name)
        }
        XCTAssertTrue(project.contains("path = \"MemoryDashboardVM+EnergyBattery.swift\";"))
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
            throw EnergyBatterySourceError.missing(needle)
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
        throw EnergyBatterySourceError.missing(name)
    }

    private func braceBody(after needle: String, in source: String) throws -> String {
        guard let start = source.range(of: needle)?.upperBound,
              let brace = source[start...].firstIndex(of: "{")
        else { throw EnergyBatterySourceError.missing(needle) }
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
        throw EnergyBatterySourceError.missing("balanced brace for \(label)")
    }
}

private enum EnergyBatterySourceError: Error, CustomStringConvertible {
    case missing(String)
    var description: String {
        switch self {
        case .missing(let detail):
            return "missing \(detail)"
        }
    }
}
