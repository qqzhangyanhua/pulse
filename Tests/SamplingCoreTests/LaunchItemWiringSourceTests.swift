import XCTest
@testable import SamplingCore

/// Source locks for the machine-page 启动项 list. They do not read the Mac directories.
final class LaunchItemWiringSourceTests: XCTestCase {
    func testPlistModelStaysPortableAndAwayFromPulseLoginItem() throws {
        let model = try repoText("Pulse/Models/LaunchItem.swift")
        XCTAssertTrue(model.contains("static let title = \"启动项\""))
        XCTAssertFalse(model.contains("import ServiceManagement"))
        XCTAssertFalse(model.contains("import Darwin"))
        XCTAssertFalse(model.contains("import SwiftUI"))
        XCTAssertFalse(model.contains("sfltool"))
        XCTAssertFalse(model.contains("LoginItem"))
        XCTAssertFalse(model.contains("SMAppService"))

        let package = try repoText("Package.swift")
        let excluded = package.components(separatedBy: "exclude:")[1].components(separatedBy: "sources:")[0]
        let sources = package.components(separatedBy: "sources:")[1]
        XCTAssertTrue(sources.contains("\"Models/LaunchItem.swift\""))
        XCTAssertTrue(sources.contains("\"Models/DashboardCore+LaunchItems.swift\""))
        XCTAssertTrue(excluded.contains("\"Sampling/LaunchItemReader.swift\""))
        XCTAssertFalse(sources.contains("LaunchItemReader.swift"))
        XCTAssertFalse(excluded.contains("LaunchItem.swift"))
    }

    func testReaderUsesOnlyTheThreeDirectoriesAndLegacyPlistStatus() throws {
        let reader = try repoText("Pulse/Sampling/LaunchItemReader.swift")
        XCTAssertTrue(reader.contains("\"Library/LaunchAgents\""))
        XCTAssertTrue(reader.contains("\"/Library/LaunchAgents\""))
        XCTAssertTrue(reader.contains("\"/Library/LaunchDaemons\""))
        XCTAssertEqual(occurrenceCount(of: "LaunchDaemons", in: reader), 1)
        XCTAssertTrue(reader.contains("statusForLegacyPlist(at:"))
        XCTAssertTrue(reader.contains("contentsOfDirectory"))
        XCTAssertTrue(reader.contains("SecStaticCodeCreateWithPath"))
        XCTAssertFalse(reader.contains("sfltool"))
        XCTAssertFalse(reader.contains("enumerator"))
        XCTAssertFalse(reader.contains("LoginItem"))
        XCTAssertFalse(reader.contains("SMAppService.mainApp"))

        let sampler = try repoText("Pulse/Sampling/MemorySampler.swift")
        XCTAssertFalse(sampler.contains("LaunchItem"))
        XCTAssertFalse(sampler.contains("sfltool"))
    }

    func testMachinePageSectionShowsSourceSignatureAndOpensLoginItemsSettings() throws {
        let section = try repoText("Pulse/Views/MachineOverviewSection+LaunchItems.swift")
        XCTAssertTrue(section.contains("LaunchItemCopy.title"))
        XCTAssertTrue(section.contains("Text(\"来源\")"))
        XCTAssertTrue(section.contains("Text(\"签名\")"))
        XCTAssertTrue(section.contains("Text(\"启用\")"))
        XCTAssertTrue(section.contains("row.source"))
        XCTAssertTrue(section.contains("row.signature"))
        XCTAssertTrue(section.contains("row.enabled"))
        XCTAssertTrue(section.contains("SMAppService.openSystemSettingsLoginItems()"))
        XCTAssertTrue(section.contains("LaunchItemCopy.openSettings"))
        XCTAssertFalse(section.contains("sfltool"))
        XCTAssertFalse(section.contains("LoginItemProjection"))
        XCTAssertFalse(section.contains("SMAppService.mainApp"))
        XCTAssertFalse(section.contains("SMLoginItemSetEnabled"))
        XCTAssertFalse(section.contains("HistoryAnnotatedChart"))

        let overview = try repoText("Pulse/Views/MachineOverviewSection.swift")
        XCTAssertTrue(overview.contains("launchItemsSection"))

        let project = try repoText("Pulse.xcodeproj/project.pbxproj")
        for name in [
            "LaunchItem.swift",
            "DashboardCore+LaunchItems.swift",
            "LaunchItemReader.swift",
            "MachineOverviewSection+LaunchItems.swift",
            "MemoryDashboardVM+LaunchItems.swift",
        ] {
            XCTAssertTrue(project.contains("\(name) in Sources"), name)
        }
    }

    func testWatchStartsOnlyOnTheMachinePage() throws {
        let tail = try functionBody(
            named: "finishPageChange",
            in: try repoText("Pulse/Models/DashboardCore+Selection.swift")
        )
        XCTAssertTrue(tail.contains("startLaunchItemWatch"))
        XCTAssertTrue(tail.contains("stopLaunchItemWatch"))
        let machine = try slice(from: "if selectedPage == .machine", until: "} else {", in: tail)
        XCTAssertTrue(machine.contains("startLaunchItemWatch"))
        XCTAssertFalse(machine.contains("stopLaunchItemWatch"))

        let vm = try repoText("Pulse/ViewModels/MemoryDashboardVM.swift")
        let perform = try functionBody(named: "perform", in: vm)
        XCTAssertTrue(perform.contains("syncLaunchItemWatch()"))
        XCTAssertFalse(vm.contains("SMAppService"))
        XCTAssertFalse(vm.contains("LoginItem"))

        let watch = try repoText("Pulse/ViewModels/MemoryDashboardVM+LaunchItems.swift")
        let sync = try functionBody(named: "syncLaunchItemWatch", in: watch)
        XCTAssertTrue(sync.contains("selectedPage == .machine"))
        XCTAssertTrue(sync.contains("launchItemRefreshTask?.cancel()"))
        XCTAssertTrue(sync.contains(".seconds(30)"))
        XCTAssertFalse(watch.contains("Timer"))
        let refresh = try functionBody(named: "refreshLaunchItems", in: watch)
        XCTAssertTrue(refresh.contains("LaunchItemReader.read()"))
        XCTAssertTrue(refresh.contains("apply(launchItems: next)"))
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

    private func occurrenceCount(of needle: String, in haystack: String) -> Int {
        haystack.components(separatedBy: needle).count - 1
    }

    private func functionBody(named name: String, in source: String) throws -> String {
        let patterns = ["func \(name)(", "private func \(name)("]
        for pattern in patterns {
            guard let range = source.range(of: pattern),
                  let brace = source[range.lowerBound...].firstIndex(of: "{")
            else { continue }
            return try balancedSlice(from: brace, in: source)
        }
        throw LaunchItemSourceError.missing(name)
    }

    private func slice(from start: String, until end: String, in source: String) throws -> String {
        guard let lower = source.range(of: start)?.lowerBound,
              let upper = source.range(of: end, range: lower..<source.endIndex)?.lowerBound
        else { throw LaunchItemSourceError.missing("\(start) … \(end)") }
        return String(source[lower..<upper])
    }

    private func balancedSlice(from brace: String.Index, in source: String) throws -> String {
        var depth = 0
        var cursor = brace
        while cursor < source.endIndex {
            let character = source[cursor]
            if character == "{" { depth += 1 }
            if character == "}" {
                depth -= 1
                if depth == 0 {
                    return String(source[brace...cursor])
                }
            }
            cursor = source.index(after: cursor)
        }
        throw LaunchItemSourceError.missing("balanced")
    }
}

private enum LaunchItemSourceError: Error, CustomStringConvertible {
    case missing(String)

    var description: String {
        "missing \(self)"
    }
}
