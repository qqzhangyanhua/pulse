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

    func testThermalAdviceStaysFreeOfPlatformImports() throws {
        let source = try repoText("Pulse/Models/ThermalAdvice.swift")
        XCTAssertTrue(source.contains("static func project(_ processes: [ThermalAdviceCandidate], excludingPid pulsePid: Int32) -> ThermalAdvice"))
        for token in ["import Darwin", "import AppKit", "import SwiftUI", "import Foundation"] {
            XCTAssertFalse(source.contains(token), token)
        }
    }

    func testPackageAndProjectListThermalAdvice() throws {
        let package = try repoText("Package.swift")
        XCTAssertTrue(package.contains("\"Models/ThermalAdvice.swift\""))

        let project = try repoText("Pulse.xcodeproj/project.pbxproj")
        XCTAssertTrue(project.contains("ThermalAdvice.swift in Sources"))
        XCTAssertTrue(project.contains("path = ThermalAdvice.swift;"))
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

    func testThermalAdvicePublishesFromSamplesAndClearsWhenTheNoticeEnds() throws {
        let sampler = try repoText("Pulse/Sampling/MemorySampler.swift")
        XCTAssertFalse(sampler.contains("ThermalAdvice"))

        let menuBar = repoRoot().appendingPathComponent("Pulse/MenuBar", isDirectory: true)
        let menuSources = try FileManager.default.contentsOfDirectory(at: menuBar, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "swift" }
        XCTAssertFalse(menuSources.isEmpty)
        for file in menuSources {
            let text = try String(contentsOf: file, encoding: .utf8)
            XCTAssertFalse(text.contains("ThermalAdvice"), file.lastPathComponent)
        }

        let package = try repoText("Package.swift")
        XCTAssertTrue(package.contains("\"ViewModels\",\n                \"ViewModels/MemoryDashboardVM+ThermalAdvice.swift\","))
        let sourcesList = package.components(separatedBy: "sources:")
        XCTAssertEqual(sourcesList.count, 2)
        XCTAssertFalse(sourcesList[1].contains("MemoryDashboardVM+ThermalAdvice.swift"))

        let project = try repoText("Pulse.xcodeproj/project.pbxproj")
        XCTAssertTrue(project.contains("MemoryDashboardVM+ThermalAdvice.swift in Sources"))
        XCTAssertTrue(project.contains("path = \"MemoryDashboardVM+ThermalAdvice.swift\";"))

        let dashboard = try repoText("Pulse/ViewModels/MemoryDashboardVM.swift")
        XCTAssertTrue(dashboard.contains("@Published var thermalAdvice: ThermalAdvice?"))
        XCTAssertTrue(dashboard.contains("var thermalAdviceLastUpdate: Double?"))
        XCTAssertFalse(dashboard.contains("private var thermalAdviceLastUpdate"))
        XCTAssertFalse(dashboard.contains("@Published var thermalAdviceLastUpdate"))
        XCTAssertTrue(
            dashboard.contains(
                "rows = frame.rows\n                    refreshThermalAdvice(now: frame.snapshot.capturedAt.timeIntervalSince1970)"
            )
        )

        let watch = try repoText("Pulse/ViewModels/MemoryDashboardVM+HostWatch.swift")
        XCTAssertTrue(
            watch.contains(
                "thermalNotice = ThermalNotice.message(for: ThermalCondition(state))\n"
                    + "        if thermalNotice == nil {\n"
                    + "            thermalAdvice = nil\n"
                    + "            thermalAdviceLastUpdate = nil\n"
                    + "        }"
            )
        )

        let advice = try repoText("Pulse/ViewModels/MemoryDashboardVM+ThermalAdvice.swift")
        XCTAssertFalse(advice.contains("Timer"))
        XCTAssertFalse(advice.contains("addObserver"))
        XCTAssertFalse(advice.contains("ProcessEnumerator"))
        let cleared = try range(of: "thermalAdvice = nil", in: advice)
        let throttle = try range(of: "ThermalAdviceThrottle.shouldUpdate(", in: advice)
        let projectCall = try range(of: "ThermalAdviceProjection.project(", in: advice)
        let stored = try range(of: "thermalAdviceLastUpdate = now", in: advice)
        XCTAssertLessThan(cleared.lowerBound, throttle.lowerBound)
        XCTAssertLessThan(throttle.lowerBound, projectCall.lowerBound)
        XCTAssertLessThan(projectCall.lowerBound, stored.lowerBound)
        XCTAssertTrue(advice.contains("excludingPid: ProcessInfo.processInfo.processIdentifier"))
        XCTAssertEqual(occurrenceCount(of: "addObserver", in: try WiringSourceText.text(for: "MemoryDashboardVM")), 1)
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

    private func range(of needle: String, in source: String) throws -> Range<String.Index> {
        guard let found = source.range(of: needle) else {
            XCTFail("missing \(needle)")
            throw ThermalNoticeSourceError.missing(needle)
        }
        return found
    }
}

private enum ThermalNoticeSourceError: Error {
    case missing(String)
}
