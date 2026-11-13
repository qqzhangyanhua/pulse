import XCTest
@testable import SamplingCore

/// Source locks for the chip-temperature card. They do not open IOKit or a Mac window.
final class ChipTemperatureWiringSourceTests: XCTestCase {
    func testProjectionStaysPortableAndTheReaderUsesDynamicLookup() throws {
        let projection = try repoText("Pulse/Models/ChipTemperature.swift")
        XCTAssertTrue(projection.contains("import Foundation"))
        XCTAssertFalse(projection.contains("import Darwin"))
        XCTAssertFalse(projection.contains("import AppKit"))
        XCTAssertFalse(projection.contains("import IOKit"))
        XCTAssertFalse(projection.contains("import SwiftUI"))
        XCTAssertFalse(projection.contains("IOServiceOpen"))
        XCTAssertFalse(projection.contains("AppleSMC"))

        let reader = try repoText("Pulse/Sampling/HostChipTemperatureReader.swift")
        XCTAssertTrue(reader.contains("dlopen"))
        XCTAssertTrue(reader.contains("dlsym"))
        XCTAssertTrue(reader.contains("/System/Library/Frameworks/IOKit.framework/IOKit"))
        XCTAssertFalse(reader.contains("dlopen(nil)"))
        for name in [
            "IOHIDEventSystemClientCreate",
            "IOHIDEventSystemClientSetMatching",
            "IOHIDEventSystemClientCopyServices",
            "IOHIDServiceClientCopyProperty",
            "IOHIDServiceClientCopyEvent",
            "IOHIDEventGetFloatValue",
            "\"Product\"",
            "\"PrimaryUsagePage\"",
            "\"PrimaryUsage\"",
        ] {
            XCTAssertTrue(reader.contains(name), name)
        }
        for forbidden in ["IOServiceOpen", "AppleSMC", "IOServiceMatching", "powermetrics", "import IOKit"] {
            XCTAssertFalse(reader.contains(forbidden), forbidden)
        }
    }

    func testSamplingHangsOffTheMainTickOnTheMachinePageOnly() throws {
        let sampler = try repoText("Pulse/Sampling/MemorySampler.swift")
        XCTAssertTrue(sampler.contains("readChipTemperature ? HostChipTemperatureReader.read() : nil"))
        XCTAssertFalse(sampler.contains("Timer"))
        XCTAssertEqual(occurrenceCount(of: "chipTemperatureSensors: chipTemperatureSensors", in: sampler), 2)

        let vm = try repoText("Pulse/ViewModels/MemoryDashboardVM.swift")
        XCTAssertTrue(vm.contains("sampler.sample(readGPU: selectedPage == .gpu, readChipTemperature: selectedPage == .machine)"))

        let extensionVM = try repoText("Pulse/ViewModels/MemoryDashboardVM+ChipTemperature.swift")
        XCTAssertFalse(extensionVM.contains("@Published"))
        XCTAssertFalse(extensionVM.contains("@MainActor"))
        XCTAssertFalse(extensionVM.contains("didSet"))
        XCTAssertFalse(extensionVM.contains("Task.sleep"))
        XCTAssertFalse(extensionVM.contains("Timer"))
    }

    func testTheCardDrawsTheCurveOnTheMachinePageAndIsAbsentElsewhere() throws {
        let overview = try repoText("Pulse/Views/MachineOverviewSection.swift")
        XCTAssertEqual(occurrenceCount(of: "chipTemperatureCard", in: overview), 1)
        let card = try repoText("Pulse/Views/MachineOverviewSection+ChipTemperature.swift")
        XCTAssertTrue(card.contains("ChipTemperatureCopy.title"))
        XCTAssertTrue(card.contains("vm.chipTemperature.text"))
        XCTAssertTrue(card.contains("vm.chipTemperature.showsCurve"))
        XCTAssertTrue(card.contains("HistoryAnnotatedChart"))
        XCTAssertTrue(card.contains("SparklineChart"))
        XCTAssertTrue(card.contains("ChartPlaceholder(text: ChipTemperatureCopy.chartCollecting)"))
        XCTAssertFalse(card.contains("GPUPageCopy"))
        XCTAssertTrue(card.contains("vm.chipTemperature.curveDomain"))
        XCTAssertTrue(card.contains("ChipTemperatureCopy.degrees"))
        XCTAssertTrue(card.contains("PulsePalette.accent"))
        XCTAssertFalse(card.contains("CPUPercentText"))
        XCTAssertFalse(card.contains("0...100"))
        XCTAssertFalse(card.contains("percentDomain"))
        for forbidden in ["过热", "危险", "CPU 温度", "GPU 温度", "核心温度", "SMC 温度"] {
            XCTAssertFalse(card.contains(forbidden), forbidden)
        }

        let entitlements = try repoText("Pulse/Pulse.entitlements")
        XCTAssertFalse(entitlements.contains("com.apple.security.device.hid"))
        XCTAssertFalse(entitlements.contains("iokit-user-client"))

        for relative in [
            "Pulse/Models/ThermalAdvice.swift",
            "Pulse/Models/ThermalAdviceThrottle.swift",
            "Pulse/Views/ThermalAdviceCard.swift",
            "Pulse/ViewModels/MemoryDashboardVM+ThermalAdvice.swift",
        ] {
            let text = try repoText(relative)
            for token in identifierNeedles {
                XCTAssertFalse(text.contains(token), "\(relative) \(token)")
            }
        }

        var files = [
            "Pulse/Models/SnapshotExport.swift",
            "Pulse/Models/SnapshotExportFile.swift",
            "Pulse/ViewModels/MemoryDashboardVM+SnapshotExport.swift",
            "Pulse/Views/SnapshotExportPreview.swift",
            "Pulse/Views/ProcessTablePane.swift",
            "Pulse/Views/GPUOverviewSection.swift",
            "Pulse/Models/GPUPage.swift",
            "Pulse/ViewModels/MemoryDashboardVM+GPU.swift",
        ]
        let menuBar = repoRoot().appendingPathComponent("Pulse/MenuBar", isDirectory: true)
        let entries = try FileManager.default.contentsOfDirectory(at: menuBar, includingPropertiesForKeys: nil)
        files += entries
            .filter { $0.pathExtension == "swift" }
            .map { "Pulse/MenuBar/\($0.lastPathComponent)" }
        for relative in files {
            let text = try repoText(relative)
            for token in identifierNeedles {
                XCTAssertFalse(text.contains(token), "\(relative) \(token)")
            }
        }
    }

    func testPackageKeepsTheReaderOutOfPortableSources() throws {
        let package = try repoText("Package.swift")
        let parts = package.components(separatedBy: "sources:")
        XCTAssertEqual(parts.count, 2)
        XCTAssertTrue(parts[0].contains("\"Sampling/HostChipTemperatureReader.swift\""))
        XCTAssertTrue(parts[1].contains("\"Models/ChipTemperature.swift\""))
        XCTAssertFalse(parts[1].contains("HostChipTemperatureReader.swift"))

        let project = try repoText("Pulse.xcodeproj/project.pbxproj")
        for name in [
            "ChipTemperature.swift in Sources",
            "HostChipTemperatureReader.swift in Sources",
            "MachineOverviewSection+ChipTemperature.swift in Sources",
            "MemoryDashboardVM+ChipTemperature.swift in Sources",
        ] {
            XCTAssertTrue(project.contains(name), name)
        }
    }

    private let identifierNeedles = [
        "ChipTemperature",
        "chipTemperature",
        "HostChipTemperatureReader",
        "芯片温度",
    ]

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
}
