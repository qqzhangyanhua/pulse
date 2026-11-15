import XCTest

/// Source locks for the GPU display card. They do not open CoreGraphics.
final class GPUDisplayWiringSourceTests: XCTestCase {
    func testProjectionStaysPortableAndTheReaderOnlyCopiesNumbers() throws {
        let projection = try repoText("Pulse/Models/GPUDisplays.swift")
        XCTAssertTrue(projection.contains("import Foundation"))
        for forbidden in ["import AppKit", "import CoreGraphics", "import SwiftUI", "import Darwin", "import IOKit"] {
            XCTAssertFalse(projection.contains(forbidden), forbidden)
        }

        let reader = try repoText("Pulse/Sampling/HostGPUDisplayReader.swift")
        for required in [
            "CGGetActiveDisplayList",
            "CGDisplayCopyDisplayMode",
            ".refreshRate",
            ".pixelWidth",
            ".pixelHeight",
            "CGDisplayIsBuiltin",
            "maximumFramesPerSecond",
            "NSScreenNumber",
        ] {
            XCTAssertTrue(reader.contains(required), required)
        }
        for forbidden in [
            "IOServiceOpen",
            "IOReport",
            "GPUDisplayProjection",
            "\" Hz\"",
            "内建",
            "CGDisplayModeGetRefreshRate",
            "CGDisplayModeGetPixelWidth",
            "CGDisplayModeGetPixelHeight",
            "takeUnretainedValue",
            "CGDisplayModeRelease",
            "?? 0",
        ] {
            XCTAssertFalse(reader.contains(forbidden), forbidden)
        }
    }

    func testPackageExcludesTheDarwinReaderAndTheProjectCompilesIt() throws {
        let package = try repoText("Package.swift")
        let parts = package.components(separatedBy: "sources:")
        XCTAssertEqual(parts.count, 2)
        XCTAssertTrue(parts[0].contains("\"Sampling/HostGPUDisplayReader.swift\""))
        XCTAssertTrue(parts[1].contains("\"Models/GPUDisplays.swift\""))
        XCTAssertFalse(parts[1].contains("HostGPUDisplayReader.swift"))
        XCTAssertFalse(parts[1].contains("GPUOverviewSection+Displays.swift"))

        let project = try repoText("Pulse.xcodeproj/project.pbxproj")
        for name in [
            "GPUDisplays.swift in Sources",
            "HostGPUDisplayReader.swift in Sources",
            "GPUOverviewSection+Displays.swift in Sources",
        ] {
            XCTAssertEqual(occurrenceCount(of: name, in: project), 2, name)
        }
    }

    func testReadHappensOnGPUPageEntryAndScreenParameterChangesNotOnTheSample() throws {
        let sampler = try repoText("Pulse/Sampling/MemorySampler.swift")
        for forbidden in ["HostGPUDisplayReader", "CGDisplay", "didChangeScreenParameters"] {
            XCTAssertFalse(sampler.contains(forbidden), forbidden)
        }

        let vm = try repoText("Pulse/ViewModels/MemoryDashboardVM.swift")
        let tick = try functionBody(named: "tick", in: vm)
        XCTAssertFalse(tick.contains("HostGPUDisplayReader"))
        XCTAssertFalse(tick.contains("refreshGPUDisplays"))
        let perform = try functionBody(named: "perform", in: vm)
        XCTAssertTrue(perform.contains("syncGPUDisplayWatch()"))

        let selection = try repoText("Pulse/Models/DashboardCore+Selection.swift")
        XCTAssertFalse(selection.contains("selectedPage == .gpu"))
        let finish = try functionBody(named: "finishPageChange", in: selection)
        XCTAssertEqual(occurrenceCount(of: "gpuDisplayWatchEffect(on: selectedPage)", in: finish), 1)

        let gate = try functionBody(
            named: "gpuDisplayWatchEffect",
            in: try repoText("Pulse/Models/DashboardCore+GPU.swift")
        )
        XCTAssertTrue(gate.contains("page == .gpu"))
        XCTAssertTrue(gate.contains(".startGPUDisplayWatch"))
        XCTAssertTrue(gate.contains(".stopGPUDisplayWatch"))

        let watch = try repoText("Pulse/ViewModels/MemoryDashboardVM+GPU.swift")
        XCTAssertFalse(watch.contains("Timer"))
        let sync = try functionBody(named: "syncGPUDisplayWatch", in: watch)
        XCTAssertTrue(sync.contains("selectedPage == .gpu"))
        XCTAssertTrue(sync.contains("NSApplication.didChangeScreenParametersNotification"))
        XCTAssertTrue(sync.contains("refreshGPUDisplays()"))
        let refresh = try functionBody(named: "refreshGPUDisplays", in: watch)
        XCTAssertTrue(refresh.contains("HostGPUDisplayReader.read()"))
        XCTAssertTrue(refresh.contains("apply(gpuDisplays:"))
    }

    func testCardIsOnTheGPUPageAndStaysOutOfHistoryMenuBarSnapshotAndMachineCard() throws {
        let page = try repoText("Pulse/Views/GPUOverviewSection.swift")
        guard let chart = page.range(of: "chartAndShare")?.upperBound,
              let time = page.range(of: "gpuTimeCard")?.upperBound,
              let card = page.range(of: "displaysCard")?.lowerBound
        else {
            return XCTFail("displays card follows the gpu time card")
        }
        XCTAssertLessThan(chart, time)
        XCTAssertLessThan(time, card)

        let view = try repoText("Pulse/Views/GPUOverviewSection+Displays.swift")
        XCTAssertTrue(view.contains("GPUDisplayCopy.title"))

        for relative in [
            "Pulse/Sampling/HistoryStore.swift",
            "Pulse/Models/SnapshotExport.swift",
            "Pulse/Models/SnapshotExport+Redaction.swift",
            "Pulse/Models/SnapshotExportFile.swift",
            "Pulse/Models/DashboardCore+Snapshot.swift",
            "Pulse/Views/MachineOverviewSection+GPU.swift",
        ] {
            let text = try repoText(relative)
            for forbidden in ["HostGPUDisplayReader", "GPUDisplays", "GPUDisplayCopy", "displaysCard"] {
                XCTAssertFalse(text.contains(forbidden), "\(relative) \(forbidden)")
            }
        }

        let menuBar = repoRoot().appendingPathComponent("Pulse/MenuBar", isDirectory: true)
        let entries = try FileManager.default.contentsOfDirectory(at: menuBar, includingPropertiesForKeys: nil)
        let sources = entries.filter { $0.pathExtension == "swift" }
        XCTAssertFalse(sources.isEmpty)
        for entry in sources {
            let text = try String(contentsOf: entry, encoding: .utf8)
            for forbidden in ["HostGPUDisplayReader", "GPUDisplays", "GPUDisplayCopy", "displaysCard"] {
                XCTAssertFalse(text.contains(forbidden), "\(entry.lastPathComponent) \(forbidden)")
            }
        }
    }

    private func repoRoot() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private func repoText(_ relative: String) throws -> String {
        try String(contentsOf: repoRoot().appendingPathComponent(relative), encoding: .utf8)
    }

    private func occurrenceCount(of needle: String, in source: String) -> Int {
        source.components(separatedBy: needle).count - 1
    }

    private func functionBody(named name: String, in source: String) throws -> String {
        let patterns = ["func \(name)(", "private func \(name)("]
        for pattern in patterns {
            guard let range = source.range(of: pattern),
                  let brace = source[range.lowerBound...].firstIndex(of: "{")
            else { continue }
            return try balancedSlice(from: brace, in: source, label: name)
        }
        throw GPUDisplaySourceError.missing(name)
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
        throw GPUDisplaySourceError.missing("balanced brace for \(label)")
    }
}

private enum GPUDisplaySourceError: Error {
    case missing(String)
}
