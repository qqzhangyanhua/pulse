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
        XCTAssertFalse(reader.contains("IOServiceOpen"))
        XCTAssertFalse(reader.contains("powermetrics"))
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

    /// Enter applies this beat immediately. A failed main sample with no visit
    /// success is the sampling-failure empty state, not a pending skeleton.
    /// Leave still does not publish this beat's numbers.
    func testJustEnteredFailedMainSamplePublishesTheFailureFrame() throws {
        let gpuVM = try repoText("Pulse/ViewModels/MemoryDashboardVM+GPU.swift")
        let parts = gpuVM.components(separatedBy: "func publishGPUTransition")
        XCTAssertEqual(parts.count, 2)
        let transition = parts[1].components(separatedBy: "func recordGPUSample")[0]
        XCTAssertTrue(transition.contains("transition == .justEntered && samplingFailed ? .failed : .pending"))
        XCTAssertTrue(transition.contains(".justLeft"))
        XCTAssertFalse(transition.contains("nodes:"))
        XCTAssertEqual(occurrenceCount(of: "GPUPageProjection.apply", in: transition), 1)
    }

    func testSamplingHangsOffTheMainTickAndStaysOffOtherSurfaces() throws {
        let sampler = try repoText("Pulse/Sampling/MemorySampler.swift")
        XCTAssertTrue(sampler.contains("readGPU ? HostGPUReader.read() : nil"))
        XCTAssertFalse(sampler.contains("Timer"))

        let vm = try repoText("Pulse/ViewModels/MemoryDashboardVM.swift")
        XCTAssertTrue(vm.contains("sample(readGPU: selectedPage == .gpu"))
        XCTAssertEqual(
            occurrenceCount(of: "publishGPUTransition(from: previous, to: selectedPage)", in: vm),
            2
        )
        XCTAssertTrue(vm.contains("func selectPage("))
        XCTAssertTrue(vm.contains("func focusMemoryPage("))

        let gpuVM = try repoText("Pulse/ViewModels/MemoryDashboardVM+GPU.swift")
        XCTAssertTrue(gpuVM.contains("guard selectedPage == .gpu else { return }"))
        XCTAssertFalse(gpuVM.contains("Task.sleep"))
        XCTAssertFalse(gpuVM.contains("@MainActor"))
        XCTAssertFalse(gpuVM.contains("@Published"))

        for relative in [
            "Pulse/MenuBar/MenuBarStatus.swift",
            "Pulse/MenuBar/MenuBarPopoverView.swift",
            "Pulse/Models/MenuBarReading.swift",
            "Pulse/Models/SnapshotExport.swift",
            "Pulse/Views/MachineOverviewSection.swift",
            "Pulse/Views/OverviewSection.swift",
            "Pulse/Views/ProcessTablePane.swift",
        ] {
            let text = try repoText(relative)
            XCTAssertFalse(text.contains("GPU 使用率"), relative)
            XCTAssertFalse(text.contains("gpuPage"), relative)
            XCTAssertFalse(text.contains("Device Utilization"), relative)
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

    private func repoText(_ relative: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return try String(contentsOf: root.appendingPathComponent(relative), encoding: .utf8)
    }

    private func occurrenceCount(of needle: String, in source: String) -> Int {
        source.components(separatedBy: needle).count - 1
    }
}
