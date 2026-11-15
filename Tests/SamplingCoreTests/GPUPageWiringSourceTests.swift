import XCTest
@testable import SamplingCore

/// Source locks for the GPU page. They do not open IOKit or the Mac window.
final class GPUPageWiringSourceTests: XCTestCase {
    func testGPUPageIsAFullPageWithoutProcessChrome() throws {
        let dashboard = try repoText("Pulse/Views/MemoryDashboardView.swift")
        XCTAssertTrue(dashboard.contains("case .gpu:"))
        XCTAssertTrue(dashboard.contains("!vm.selectedPage.isFullPage"))
        let status = try repoText("Pulse/MenuBar/MenuBarStatus.swift")
        XCTAssertTrue(status.contains("var isFullPage: Bool { self == .machine || self == .gpu }"))
        XCTAssertTrue(dashboard.contains("reduceMotion ? nil : PulseMotion.page, value: fullPageIdentity"))
        XCTAssertTrue(dashboard.contains("case .energy:"))
        XCTAssertTrue(dashboard.contains("case .gpu:"))
        XCTAssertTrue(dashboard.contains("case .gpu, .machine:"))

        let gpu = dashboard.components(separatedBy: "private var gpuPage")
        XCTAssertEqual(gpu.count, 2)
        let gpuBody = gpu[1].components(separatedBy: "private var resourcePage")[0]
        XCTAssertTrue(gpuBody.contains("GPUOverviewSection()"))
        XCTAssertFalse(gpuBody.contains("ProcessTablePane"))
        XCTAssertFalse(gpuBody.contains("ProcessDetailSidebar"))
        XCTAssertFalse(gpuBody.replacingOccurrences(of: "GPUOverviewSection()", with: "").contains("OverviewSection()"))
        XCTAssertFalse(gpuBody.contains("AppFilterField"))

        let app = try repoText("Pulse/PulseApp.swift")
        XCTAssertFalse(app.contains("selectPage(.gpu)"))
        XCTAssertFalse(app.contains("\"GPU\""))
    }

    func testGPUOverviewUsesTheSharedThrottleCardAndOneUtilizationCurve() throws {
        let overview = try repoText("Pulse/Views/GPUOverviewSection.swift")
        XCTAssertTrue(overview.contains("ThermalAdviceCard()"))
        XCTAssertTrue(overview.contains("GPUPageCopy.utilization"))
        XCTAssertTrue(overview.contains("GPUPageCopy.memory"))
        XCTAssertTrue(overview.contains("vm.gpuPage.showsCurve"))
        XCTAssertTrue(overview.contains("vm.gpuPage.coreCountText"))
        XCTAssertEqual(occurrenceCount(of: "HistoryAnnotatedChart", in: overview), 1)
        XCTAssertFalse(overview.contains("ProcessTablePane"))
        XCTAssertFalse(overview.contains("ProcessDetailSidebar"))
        XCTAssertFalse(overview.contains("AppFilterField"))
        XCTAssertFalse(overview.replacingOccurrences(of: "GPUOverviewSection", with: "").contains("OverviewSection"))
        XCTAssertFalse(overview.contains("terminateThermalAdvice"))
        for forbidden in ["显存", "VRAM", "即将推出", "危险", "泄漏", "容量"] {
            XCTAssertFalse(overview.contains(forbidden), forbidden)
        }

        let copy = try repoText("Pulse/Models/ProcessRowCopy.swift")
        XCTAssertTrue(copy.contains("case .machine, .gpu:"))
        XCTAssertTrue(copy.contains("return \"\""))
    }

    func testProjectionStaysPortableAndTheReaderStaysOnRegistryProperties() throws {
        let projection = try repoText("Pulse/Models/GPUPage.swift")
        XCTAssertTrue(projection.contains("import Foundation"))
        XCTAssertFalse(projection.contains("import Darwin"))
        XCTAssertFalse(projection.contains("import AppKit"))
        XCTAssertFalse(projection.contains("import IOKit"))
        XCTAssertFalse(projection.contains("import SwiftUI"))
        XCTAssertFalse(projection.contains("Date("))

        let reader = try repoText("Pulse/Sampling/HostGPUReader.swift")
        XCTAssertTrue(reader.contains("IOServiceMatching"))
        XCTAssertTrue(reader.contains("IORegistryEntryCreateCFProperties"))
        XCTAssertTrue(reader.contains("\"IOAccelerator\""))
        XCTAssertTrue(reader.contains("\"PerformanceStatistics\""))
        XCTAssertTrue(reader.contains("GPUCoreCount.registryKey"))
        XCTAssertTrue(reader.contains("GPUCoreCount.parse"))
        XCTAssertFalse(reader.contains("IOServiceOpen"))
        XCTAssertFalse(reader.contains("powermetrics"))
        XCTAssertTrue(reader.contains("/usr/lib/libIOReport.dylib"))
        XCTAssertTrue(reader.contains("/System/Library/PrivateFrameworks/IOReport.framework/IOReport"))
        XCTAssertTrue(reader.contains("\"GPU Stats\""))
        XCTAssertTrue(reader.contains("\"GPU Performance States\""))
        XCTAssertTrue(reader.contains("\"OFF\""))
        XCTAssertTrue(reader.contains("IOReportCreateSamples"))
        XCTAssertTrue(reader.contains("IOReportCreateSamplesDelta"))
        XCTAssertFalse(reader.contains("Energy Model"))
        XCTAssertFalse(reader.contains("Renderer Utilization"))
        XCTAssertFalse(reader.contains("Tiler Utilization"))
        XCTAssertFalse(reader.contains("missing.count == 1"))
        XCTAssertFalse(reader.contains("copy[missing[0]]"))
        XCTAssertTrue(reader.contains("for index in missing"))
        XCTAssertTrue(reader.contains("nodes.isEmpty, sawAccelerator"))
        XCTAssertTrue(reader.contains("GPUAcceleratorNode()"))
        guard let skipChannel = reader.range(of: "guard !missing.isEmpty else { return nodes }")?.lowerBound,
              let readChannel = reader.range(of: "IOReportDeviceChannel.percent()")?.lowerBound
        else {
            return XCTFail("device channel must be skipped when no node is missing the key")
        }
        XCTAssertLessThan(skipChannel, readChannel)
    }

    func testGPUReadSwitchIsNotTheSelectedGPUPage() throws {
        let sampler = try repoText("Pulse/Sampling/MemorySampler.swift")
        XCTAssertTrue(sampler.contains("let gpuNodes = HostGPUReader.read()"))
        XCTAssertFalse(sampler.contains("readGPU ?"))
        XCTAssertFalse(sampler.contains("readGPU:"))
        XCTAssertFalse(sampler.contains("selectedPage == .gpu"))
        XCTAssertFalse(sampler.contains("Timer"))

        let vm = try repoText("Pulse/ViewModels/MemoryDashboardVM.swift")
        XCTAssertEqual(occurrenceCount(of: "selectedPage == .gpu", in: vm), 1)
        XCTAssertTrue(vm.contains("sampler.sample(readChipTemperature: selectedPage == .machine, readEnergyModel: selectedPage == .cpu, readGPUEnergy: selectedPage == .gpu, readMachineRails: selectedPage == .energy)"))
        XCTAssertTrue(vm.contains("func selectPage("))
        XCTAssertTrue(vm.contains("func focusMemoryPage("))

        let selection = try repoText("Pulse/Models/DashboardCore+Selection.swift")
        XCTAssertFalse(selection.contains("selectedPage == .gpu"))
        XCTAssertTrue(selection.contains(".setGPUSampling(on: true)"))

        let gpuVM = try repoText("Pulse/ViewModels/MemoryDashboardVM+GPU.swift")
        XCTAssertFalse(gpuVM.contains("Task.sleep"))
        XCTAssertFalse(gpuVM.contains("@MainActor"))
        XCTAssertFalse(gpuVM.contains("@Published"))

        for relative in [
            "Pulse/MenuBar/MenuBarStatus.swift",
            "Pulse/MenuBar/MenuBarPopoverView.swift",
            "Pulse/Models/MenuBarReading.swift",
            "Pulse/Views/MachineOverviewSection.swift",
            "Pulse/Views/MachineOverviewSection+ChipTemperature.swift",
            "Pulse/Views/MachineOverviewSection+Throughput.swift",
            "Pulse/Views/OverviewSection.swift",
            "Pulse/Views/ProcessTablePane.swift",
        ] {
            let text = try repoText(relative)
            XCTAssertFalse(text.contains("GPU 使用率"), relative)
            XCTAssertFalse(text.contains("gpuPage"), relative)
            XCTAssertFalse(text.contains("Device Utilization"), relative)
            XCTAssertFalse(text.contains("coreCountText"), relative)
            XCTAssertFalse(text.contains("核 GPU"), relative)
            XCTAssertFalse(text.contains("gpu-core-count"), relative)
        }
    }

    func testMachineGPUCardOpensTheGPUPageAndTheMenuBarStaysClear() throws {
        let overview = try repoText("Pulse/Views/MachineOverviewSection.swift")
        XCTAssertEqual(occurrenceCount(of: "gpuCard", in: overview), 1)
        XCTAssertFalse(overview.contains("selectPage(.gpu)"))
        XCTAssertFalse(overview.contains("GPU 使用率"))
        XCTAssertFalse(overview.contains("gpuPage"))

        let card = try repoText("Pulse/Views/MachineOverviewSection+GPU.swift")
        XCTAssertTrue(card.contains("GPUPageCopy.utilization"))
        XCTAssertTrue(card.contains("GPUPageCopy.memory"))
        XCTAssertTrue(card.contains("vm.gpuPage.utilizationText"))
        XCTAssertTrue(card.contains("vm.gpuPage.memoryText"))
        XCTAssertEqual(occurrenceCount(of: "vm.selectPage(.gpu)", in: card), 1)
        XCTAssertTrue(card.contains("Button"))
        for forbidden in ["GPU 功耗", "GPU 频率", "coreCountText", "核 GPU", "渲染器", "分块器", "显存", "容量", "HistoryAnnotatedChart"] {
            XCTAssertFalse(card.contains(forbidden), forbidden)
        }

        let project = try repoText("Pulse.xcodeproj/project.pbxproj")
        XCTAssertEqual(occurrenceCount(of: "MachineOverviewSection+GPU.swift in Sources", in: project), 2)

        let readings = [
            "GPU 使用率",
            "GPU 占用内存",
            "gpuPage",
            "Device Utilization",
            "In use system memory",
            "GPU 功耗",
            "GPU 频率",
        ]
        let menuBar = repoRoot().appendingPathComponent("Pulse/MenuBar", isDirectory: true)
        let entries = try FileManager.default.contentsOfDirectory(at: menuBar, includingPropertiesForKeys: nil)
        let sources = entries.filter { $0.pathExtension == "swift" }
        XCTAssertFalse(sources.isEmpty)
        for entry in sources {
            let text = try String(contentsOf: entry, encoding: .utf8)
            for reading in readings {
                XCTAssertFalse(text.contains(reading), "\(entry.lastPathComponent) \(reading)")
            }
        }
    }

    func testPackageKeepsTheReaderOutOfPortableSources() throws {
        let package = try repoText("Package.swift")
        let parts = package.components(separatedBy: "sources:")
        XCTAssertEqual(parts.count, 2)
        XCTAssertTrue(parts[0].contains("\"Sampling/HostGPUReader.swift\""))
        XCTAssertTrue(parts[1].contains("\"Models/GPUPage.swift\""))
        XCTAssertFalse(parts[1].contains("HostGPUReader.swift"))

        let project = try repoText("Pulse.xcodeproj/project.pbxproj")
        XCTAssertFalse(project.contains("IOReport.framework"))
        for name in [
            "GPUPage.swift in Sources",
            "HostGPUReader.swift in Sources",
            "GPUOverviewSection.swift in Sources",
            "MemoryDashboardVM+GPU.swift in Sources",
        ] {
            XCTAssertTrue(project.contains(name), name)
        }
    }

    func testIOReportReadersTryTheSystemDylibBeforeTheFramework() throws {
        let dylib = "\"/usr/lib/libIOReport.dylib\""
        let framework = "\"/System/Library/PrivateFrameworks/IOReport.framework/IOReport\""
        for relative in ["Pulse/Sampling/HostGPUReader.swift", "Pulse/Sampling/HostEnergyModelReader.swift"] {
            let reader = try repoText(relative)
            guard let dylibAt = reader.range(of: dylib)?.lowerBound,
                  let frameworkAt = reader.range(of: framework)?.lowerBound
            else {
                XCTFail("\(relative) must name both IOReport paths")
                continue
            }
            XCTAssertLessThan(dylibAt, frameworkAt, relative)
            XCTAssertTrue(reader.contains("dlopen("), relative)
            XCTAssertTrue(reader.contains("RTLD_LAZY | RTLD_LOCAL"), relative)
            XCTAssertFalse(reader.contains("IOServiceOpen"), relative)
        }

        let project = try repoText("Pulse.xcodeproj/project.pbxproj")
        XCTAssertFalse(project.contains("libIOReport"))
        XCTAssertFalse(project.contains("IOReport.framework"))
        let package = try repoText("Package.swift")
        XCTAssertFalse(package.contains("IOReport"))
        XCTAssertFalse(package.contains("linkerSettings"))
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
}
