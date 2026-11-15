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
        let overview = try WiringSourceText.text(for: "GPUOverviewSection")
        XCTAssertTrue(overview.contains("ThermalAdviceCard()"))
        XCTAssertTrue(overview.contains("ScrollView"))
        XCTAssertTrue(overview.contains("GPUPageCopy.utilization"))
        XCTAssertTrue(overview.contains("GPUPageCopy.memory"))
        XCTAssertTrue(overview.contains("GPUPageCopy.power"))
        XCTAssertTrue(overview.contains("GPUPageCopy.frequency"))
        XCTAssertTrue(overview.contains("EnergyModelCopy.gpuPowerReading"))
        XCTAssertTrue(overview.contains("EnergyModelCopy.gpuFrequencyReading"))
        XCTAssertTrue(overview.contains("EnergyModelCopy.gpuPowerLine"))
        XCTAssertTrue(overview.contains("EnergyModelCopy.gpuFrequencyLine"))
        XCTAssertTrue(overview.contains("MachinePageCopy.chipValue"))
        XCTAssertTrue(overview.contains("if let cores = vm.gpuPage.coreCountText"))
        XCTAssertTrue(overview.contains("vm.gpuPage.showsCurve"))
        XCTAssertTrue(overview.contains("vm.gpuPage.coreCountText"))
        XCTAssertTrue(overview.contains("curveSummary("))
        XCTAssertTrue(overview.contains("GPUCurveSummary.meanTitle"))
        XCTAssertTrue(overview.contains("GPUCurveSummary.peakTitle"))
        XCTAssertTrue(overview.contains("HistoryCurvePresentation.annotation"))
        XCTAssertTrue(overview.contains("HistoryRangeControl("))
        XCTAssertTrue(overview.contains("ViewThatFits"))
        XCTAssertTrue(overview.contains("760"))
        XCTAssertTrue(overview.contains(".frame(width: 340)"))
        XCTAssertEqual(occurrenceCount(of: "HistoryAnnotatedChart", in: overview), 1)
        XCTAssertFalse(overview.contains("ProcessTablePane"))
        XCTAssertFalse(overview.contains("ProcessDetailSidebar"))
        XCTAssertFalse(overview.contains("AppFilterField"))
        XCTAssertFalse(overview.replacingOccurrences(of: "GPUOverviewSection", with: "").contains("OverviewSection"))
        XCTAssertFalse(overview.contains("terminateThermalAdvice"))
        for forbidden in ["显存", "VRAM", "即将推出", "危险", "泄漏", "容量"] {
            XCTAssertFalse(overview.contains(forbidden), forbidden)
        }

        let page = try repoText("Pulse/Views/GPUOverviewSection.swift")
        var cursor = page.startIndex
        for token in ["ThermalAdviceCard()", "specLabels", "readingCards", "HistoryRangeControl(", "chartAndShare"] {
            guard let found = page.range(of: token, range: cursor..<page.endIndex) else {
                return XCTFail(token)
            }
            cursor = found.upperBound
        }

        let share = try repoText("Pulse/Views/GPUShareCard.swift")
        XCTAssertTrue(share.contains("row.barFraction"))
        XCTAssertTrue(share.contains("terminateThermalAdvice"))
        XCTAssertEqual(occurrenceCount(of: "terminateThermalAdvice", in: share), 1)
        XCTAssertFalse(share.contains("focusMemoryPage"))
        XCTAssertFalse(share.contains("selectPidIfPresent"))
        XCTAssertFalse(share.contains("TopAppLocation"))
        XCTAssertFalse(share.contains("locateMemoryTopApp"))
        let quitClosure = share.components(separatedBy: "Button(\"退出\")")[1]
            .components(separatedBy: "private func processName")[0]
        XCTAssertTrue(quitClosure.contains("terminateThermalAdvice"))
        XCTAssertFalse(quitClosure.contains("openGPUShareProcess"))
        XCTAssertFalse(quitClosure.contains("gpuShareNameOpensMemoryPage"))
        let nameTap = share.components(separatedBy: "private func processName")[1]
        XCTAssertTrue(nameTap.contains("if vm.gpuShareNameOpensMemoryPage(row.pid)"))
        XCTAssertTrue(nameTap.contains("vm.openGPUShareProcess(row.pid)"))
        XCTAssertFalse(nameTap.contains("terminateThermalAdvice"))
        XCTAssertTrue(share.contains(".accessibilityHidden(true)"))

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
        XCTAssertTrue(projection.contains("Renderer Utilization %"))
        XCTAssertTrue(projection.contains("Tiler Utilization %"))
        XCTAssertTrue(projection.contains("\"recoveryCount\""))
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
        for forbidden in ["GPU 功耗", "GPU 频率", "coreCountText", "核 GPU", "渲染器", "分块器", "GPU 恢复次数", "rendererText", "tilerText", "recoveryText", "显存", "容量", "HistoryAnnotatedChart"] {
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
            "最近 1 小时 GPU 时间",
            "GPU 时间",
            "渲染器",
            "分块器",
            "GPU 恢复次数",
            "Renderer Utilization",
            "Tiler Utilization",
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
        XCTAssertFalse(parts[1].contains("GPUOverviewSection+Readings.swift"))
        XCTAssertFalse(parts[1].contains("GPUOverviewSection+Chart.swift"))
        XCTAssertFalse(parts[1].contains("GPUOverviewSection+Share.swift"))
        XCTAssertFalse(parts[1].contains("GPUOverviewSection+GPUTime.swift"))
        XCTAssertFalse(parts[1].contains("GPUOverviewSection+Recovery.swift"))
        XCTAssertTrue(parts[1].contains("\"Sampling/GPUTimeMinuteLedger.swift\""))
        XCTAssertTrue(parts[0].contains("\"Sampling/HostGPUShareReader.swift\""))

        let project = try repoText("Pulse.xcodeproj/project.pbxproj")
        XCTAssertFalse(project.contains("IOReport.framework"))
        for name in [
            "GPUPage.swift in Sources",
            "HostGPUReader.swift in Sources",
            "GPUOverviewSection.swift in Sources",
            "GPUOverviewSection+Readings.swift in Sources",
            "GPUOverviewSection+Chart.swift in Sources",
            "GPUOverviewSection+Share.swift in Sources",
            "GPUOverviewSection+GPUTime.swift in Sources",
            "GPUOverviewSection+Recovery.swift in Sources",
            "GPUTimeMinuteLedger.swift in Sources",
            "MemoryDashboardVM+GPU.swift in Sources",
        ] {
            XCTAssertTrue(project.contains(name), name)
        }
    }

    func testGPUTimeCardIsBelowTheShareCardAndTheClientReadStaysClosed() throws {
        let page = try repoText("Pulse/Views/GPUOverviewSection.swift")
        guard let share = page.range(of: "chartAndShare")?.upperBound,
              let time = page.range(of: "gpuTimeCard")?.lowerBound
        else {
            return XCTFail("gpu time card")
        }
        XCTAssertLessThan(share, time)

        let card = try repoText("Pulse/Views/GPUOverviewSection+GPUTime.swift")
        XCTAssertTrue(card.contains("GPUTimeCopy.title"))
        XCTAssertTrue(card.contains("GPUTimeCopy.exited"))
        XCTAssertFalse(card.contains("terminateThermalAdvice"))
        XCTAssertFalse(card.contains("IOServiceOpen"))

        let reader = try repoText("Pulse/Sampling/HostGPUShareReader.swift")
        XCTAssertFalse(reader.contains("IOServiceOpen("))
        XCTAssertTrue(reader.contains("IORegistryEntryCreateCFProperties"))
        XCTAssertTrue(reader.contains("AGXDeviceUserClient"))

        let sampler = try repoText("Pulse/Sampling/MemorySampler.swift")
        XCTAssertTrue(sampler.contains("HostGPUShareReader.read()"))
        XCTAssertFalse(sampler.contains("readsGPUShare"))
        XCTAssertEqual(occurrenceCount(of: "HostGPUShareReader.read()", in: sampler), 1)

        let ledger = try repoText("Pulse/Sampling/GPUTimeMinuteLedger.swift")
        XCTAssertTrue(ledger.contains("import Foundation"))
        XCTAssertFalse(ledger.contains("import Darwin"))
        XCTAssertFalse(ledger.contains("import IOKit"))
        XCTAssertFalse(ledger.contains("import SwiftUI"))
        XCTAssertFalse(ledger.contains("IOServiceOpen"))

        let history = try repoText("Pulse/Sampling/HistoryStore.swift")
        XCTAssertFalse(history.contains("GPUTimeMinuteLedger"))
        XCTAssertFalse(history.contains("最近 1 小时 GPU 时间"))
        let snapshot = try repoText("Pulse/Models/SnapshotExport.swift")
        XCTAssertFalse(snapshot.contains("最近 1 小时 GPU 时间"))
        XCTAssertFalse(snapshot.contains("GPUTimeMinuteLedger"))
    }

    func testRendererLabelsAndRecoveryCardStayOnTheGPUPage() throws {
        let readings = try repoText("Pulse/Views/GPUOverviewSection+Readings.swift")
        XCTAssertTrue(readings.contains("GPUPageCopy.renderer"))
        XCTAssertTrue(readings.contains("vm.gpuPage.rendererText"))
        XCTAssertTrue(readings.contains("GPUPageCopy.tiler"))
        XCTAssertTrue(readings.contains("vm.gpuPage.tilerText"))
        XCTAssertFalse(readings.contains("Renderer Utilization"))
        XCTAssertFalse(readings.contains("Tiler Utilization"))

        let recovery = try repoText("Pulse/Views/GPUOverviewSection+Recovery.swift")
        XCTAssertTrue(recovery.contains("GPUPageCopy.recovery"))
        XCTAssertTrue(recovery.contains("GPUPageCopy.recoveryCaption"))
        XCTAssertTrue(recovery.contains("vm.gpuPage.recoveryText"))
        XCTAssertFalse(recovery.contains("最近一次"))
        XCTAssertFalse(recovery.contains("自开机以来"))
        XCTAssertFalse(recovery.contains("recoveryCount"))

        let page = try repoText("Pulse/Views/GPUOverviewSection.swift")
        var cursor = page.startIndex
        for token in ["chartAndShare", "recoveryCard", "gpuTimeCard"] {
            guard let found = page.range(of: token, range: cursor..<page.endIndex) else {
                return XCTFail(token)
            }
            cursor = found.upperBound
        }

        let reader = try repoText("Pulse/Sampling/HostGPUReader.swift")
        XCTAssertFalse(reader.contains("Renderer Utilization"))
        XCTAssertFalse(reader.contains("Tiler Utilization"))
        let projection = try repoText("Pulse/Models/GPUPage.swift")
        XCTAssertTrue(projection.contains("\"Renderer Utilization %\""))
        XCTAssertTrue(projection.contains("\"Tiler Utilization %\""))
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
