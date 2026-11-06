import XCTest

/// Phase 26 source constraints. Linux reads text; it does not post thermal
/// notifications or draw the four overviews.
final class ThermalNoticeWiringSourceTests: XCTestCase {
    func testProjectionStaysFreeOfPlatformImports() throws {
        let source = try repoText("Pulse/Models/ThermalNotice.swift")
        XCTAssertTrue(source.contains("static func message(for condition: ThermalCondition) -> String?"))
        for token in ["import Darwin", "import AppKit", "import SwiftUI", "ProcessInfo", "Timer"] {
            XCTAssertFalse(source.contains(token), token)
        }
    }

    func testPackageAndProjectListTheProjection() throws {
        let package = try repoText("Package.swift")
        XCTAssertTrue(package.contains("\"Models/ThermalNotice.swift\""))
        XCTAssertTrue(package.contains("\"Views\""))
        XCTAssertTrue(package.contains("\"ViewModels\""))

        let project = try repoText("Pulse.xcodeproj/project.pbxproj")
        XCTAssertTrue(project.contains("ThermalNotice.swift in Sources"))
        XCTAssertTrue(project.contains("path = ThermalNotice.swift;"))
    }

    func testThermalWatchStaysOutOfTheSamplerAndUsesNoTimer() throws {
        let sampler = try repoText("Pulse/Sampling/MemorySampler.swift")
        let vm = try WiringSourceText.text(for: "MemoryDashboardVM")
        for token in ["thermalState", "ThermalNotice", "thermalNotice", "Timer", "ProcessInfo"] {
            XCTAssertFalse(sampler.contains(token), token)
        }
        XCTAssertTrue(vm.contains("ProcessInfo.thermalStateDidChangeNotification"))
        XCTAssertTrue(vm.contains("ThermalNotice.message(for:"))
        XCTAssertFalse(vm.contains("Timer"))
        XCTAssertEqual(occurrenceCount(of: "addObserver", in: vm), 1)
    }

    func testMenuBarDoesNotReadThermalState() throws {
        let directory = repoRoot().appendingPathComponent("Pulse/MenuBar", isDirectory: true)
        let files = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
        let sources = files.filter { $0.pathExtension == "swift" }
        XCTAssertFalse(sources.isEmpty)
        for file in sources {
            let text = try String(contentsOf: file, encoding: .utf8)
            for token in ["thermalNotice", "ThermalNotice", "ThermalCondition", "thermalState"] {
                XCTAssertFalse(text.contains(token), "\(file.lastPathComponent) \(token)")
            }
        }
    }

    func testFourOverviewsShareTheThermalNoticeProperty() throws {
        let files = [
            "Pulse/Views/OverviewSection.swift",
            "Pulse/Views/CPUOverviewSection.swift",
            "Pulse/Views/NetworkOverviewSection.swift",
            "Pulse/Views/DiskOverviewSection.swift",
        ]
        for file in files {
            let source = try repoText(file)
            XCTAssertTrue(source.contains("vm.thermalNotice"), file)
            XCTAssertFalse(source.contains("Timer"), file)
            XCTAssertFalse(source.contains("ProcessInfo"), file)
        }
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

    private func occurrenceCount(of needle: String, in source: String) -> Int {
        source.components(separatedBy: needle).count - 1
    }
}
