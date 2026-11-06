import XCTest
@testable import SamplingCore

final class MachinePageTests: XCTestCase {
    func testChipLineUsesAnEmDashWhenTheNameIsMissing() {
        XCTAssertEqual(MachinePageCopy.chipLine(nil), "芯片 · —")
        XCTAssertEqual(MachinePageCopy.chipLine(""), "芯片 · —")
        XCTAssertEqual(MachinePageCopy.chipLine("   "), "芯片 · —")
        XCTAssertEqual(MachinePageCopy.chipLine("Apple M3 Pro"), "芯片 · Apple M3 Pro")
        XCTAssertFalse(MachinePageCopy.chipLine(nil).contains("0"))
    }

    func testOSLineAlwaysPrintsThreeComponents() {
        XCTAssertEqual(
            MachinePageCopy.osLine(MachineOSVersion(major: 15, minor: 6, patch: 1)),
            "系统 · macOS 15.6.1"
        )
        XCTAssertEqual(
            MachinePageCopy.osLine(MachineOSVersion(major: 15, minor: 0, patch: 0)),
            "系统 · macOS 15.0.0"
        )
    }

    func testUptimeDropsZeroUnitsAndTreatsZeroAsJustBooted() {
        XCTAssertEqual(MachinePageCopy.uptimeLine(0), "已开机 · 不到 1 分钟")
        XCTAssertEqual(MachinePageCopy.uptimeLine(59), "已开机 · 不到 1 分钟")
        XCTAssertEqual(MachinePageCopy.uptimeLine(-1), "已开机 · 不到 1 分钟")
        XCTAssertEqual(MachinePageCopy.uptimeLine(60), "已开机 · 1 分钟")
        XCTAssertEqual(MachinePageCopy.uptimeLine(3_600), "已开机 · 1 小时")
        XCTAssertEqual(MachinePageCopy.uptimeLine(2 * 86_400 + 3 * 3_600), "已开机 · 2 天 3 小时")
        XCTAssertEqual(MachinePageCopy.uptimeLine(2 * 86_400 + 5 * 60), "已开机 · 2 天 5 分钟")
    }

    func testPowerLineOmitsPercentWhenUnknownAndOmitsLowPowerWhenOff() {
        XCTAssertEqual(
            MachinePageCopy.powerLine(source: .battery, percent: 42, lowPowerMode: false),
            "电源 · 电池 · 42%"
        )
        XCTAssertEqual(
            MachinePageCopy.powerLine(source: .battery, percent: nil, lowPowerMode: false),
            "电源 · 电池"
        )
        XCTAssertEqual(
            MachinePageCopy.powerLine(source: .battery, percent: 0, lowPowerMode: false),
            "电源 · 电池 · 0%"
        )
        XCTAssertEqual(
            MachinePageCopy.powerLine(source: .adapter, percent: 80, lowPowerMode: false),
            "电源 · 外接电源 · 80%"
        )
        XCTAssertEqual(
            MachinePageCopy.powerLine(source: .adapter, percent: nil, lowPowerMode: false),
            "电源 · 外接电源"
        )
        XCTAssertEqual(
            MachinePageCopy.powerLine(source: .unknown, percent: 80, lowPowerMode: false),
            "电源 · —"
        )
        XCTAssertEqual(
            MachinePageCopy.powerLine(source: .battery, percent: 42, lowPowerMode: true),
            "电源 · 电池 · 42% · 低电量模式"
        )
        XCTAssertEqual(
            MachinePageCopy.powerLine(source: .adapter, percent: nil, lowPowerMode: true),
            "电源 · 外接电源 · 低电量模式"
        )
        XCTAssertFalse(
            MachinePageCopy.powerLine(source: .battery, percent: 42, lowPowerMode: false).contains("未开启")
        )
    }

    func testVolumeLineKeepsARealZeroAndHidesAMissingOrZeroTotal() {
        XCTAssertEqual(
            MachinePageCopy.volumeLine(available: 0, total: 100),
            "磁盘剩余 · 可用 0 字节 / 共 100 字节"
        )
        XCTAssertEqual(MachinePageCopy.volumeLine(available: nil, total: 100), "磁盘剩余 · —")
        XCTAssertEqual(MachinePageCopy.volumeLine(available: 10, total: nil), "磁盘剩余 · —")
        XCTAssertEqual(MachinePageCopy.volumeLine(available: 10, total: 0), "磁盘剩余 · —")
        let gib: UInt64 = 128 * 1_073_741_824
        XCTAssertEqual(
            MachinePageCopy.volumeLine(available: gib, total: gib),
            "磁盘剩余 · 可用 128 GB / 共 128 GB"
        )
    }

    func testCardValuesKeepARealZeroAndDoNotPromoteAMissingReading() {
        XCTAssertEqual(MachinePageCopy.chipValue(nil), "—")
        XCTAssertEqual(MachinePageCopy.chipValue("Apple M3 Pro"), "Apple M3 Pro")
        XCTAssertEqual(MachinePageCopy.uptimeValue(0), "不到 1 分钟")
        XCTAssertEqual(MachinePageCopy.uptimeValue(3_600), "1 小时")
        XCTAssertEqual(
            MachinePageCopy.powerValue(source: .battery, percent: 0),
            "0%"
        )
        XCTAssertEqual(
            MachinePageCopy.powerValue(source: .adapter, percent: nil),
            "外接电源"
        )
        XCTAssertEqual(
            MachinePageCopy.powerValue(source: .unknown, percent: 80),
            "—"
        )
        XCTAssertEqual(MachinePageCopy.volumeValue(available: 0, total: 100), "0 字节")
        XCTAssertEqual(MachinePageCopy.volumeValue(available: nil, total: 100), "—")
        XCTAssertEqual(MachinePageCopy.volumeValue(available: 10, total: 0), "—")
    }

    func testThermalLineIsAbsentUntilTheExistingNoticeIsSet() {
        XCTAssertNil(MachinePageCopy.thermalLine(nil))
        XCTAssertNil(MachinePageCopy.thermalLine(""))
        XCTAssertEqual(
            MachinePageCopy.thermalLine(ThermalNotice.throttling),
            "系统正在降频以控制温度"
        )
        let facts = sampleFacts()
        XCTAssertEqual(MachinePageCopy.factLines(facts).count, 5)
        XCTAssertFalse(MachinePageCopy.accessibilityLabel(facts: facts, thermalNotice: nil).contains("降频"))
        XCTAssertTrue(
            MachinePageCopy.accessibilityLabel(facts: facts, thermalNotice: ThermalNotice.throttling)
                .contains("系统正在降频以控制温度")
        )
    }

    func testMachinePageIsSelectableAndDoesNotInventAResourceReading() {
        XCTAssertTrue(DashboardPage.machine.isSelectable)
        XCTAssertFalse(DashboardPage.machine.allowsProcessQuit)
        XCTAssertTrue(DashboardPage.memory.allowsProcessQuit)
        XCTAssertFalse(DashboardPage.gpu.isSelectable)
        XCTAssertEqual(
            ProcessTableSort.defaultSort(for: .machine),
            ProcessTableSort.defaultSort(for: .memory)
        )
        let detail = ProcessDetail(
            row: ProcessRow(
                pid: 1,
                name: "a",
                bundleIdentifier: nil,
                executablePath: nil,
                cpuPercent: 1,
                memoryBytes: 2,
                threadCount: 1
            ),
            memorySeries: [],
            cpuSeries: []
        )
        let projected = ResourceDetailPageProjection.project(
            page: .machine,
            detail: detail,
            physicalTotalBytes: nil,
            frozen: nil
        )
        guard case .noResourceUpgrade = projected else {
            return XCTFail("machine page must not invent a resource reading")
        }
    }

    func testMachinePageStaysOutOfTheSampler() throws {
        let sampler = try repoText("Pulse/Sampling/MemorySampler.swift")
        XCTAssertFalse(sampler.contains("HostMachineReader"))
        XCTAssertFalse(sampler.contains("volumeAvailableCapacityForImportantUsage"))
        XCTAssertFalse(sampler.contains("IOPSCopyPowerSourcesInfo"))
        XCTAssertFalse(sampler.contains("machineFacts"))

        let package = try repoText("Package.swift")
        XCTAssertTrue(package.contains("\"Models/MachinePage.swift\""))
        XCTAssertTrue(package.contains("\"Sampling/HostMachineReader.swift\""))

        let dashboard = try repoText("Pulse/Views/MemoryDashboardView.swift")
        let machine = dashboard.components(separatedBy: "private var machinePage")
        let resource = dashboard.components(separatedBy: "private var resourcePage")
        XCTAssertEqual(machine.count, 2)
        XCTAssertEqual(resource.count, 2)
        let machineBody = machine[1].components(separatedBy: "private var resourcePage")[0]
        XCTAssertTrue(machineBody.contains("MachineOverviewSection()"))
        XCTAssertFalse(machineBody.contains("ProcessTablePane"))
        XCTAssertFalse(machineBody.contains("ProcessDetailSidebar"))
        XCTAssertTrue(dashboard.contains("vm.selectedPage != .machine"))

        let app = try repoText("Pulse/PulseApp.swift")
        XCTAssertTrue(app.contains("selectPage(.machine)"))
        XCTAssertTrue(app.contains(".keyboardShortcut(\"5\", modifiers: .command)"))
        XCTAssertTrue(app.contains(".disabled(!dashboard.selectedPage.allowsProcessQuit)"))
        XCTAssertFalse(app.contains("selectedPage ="))
        XCTAssertFalse(app.contains("selectPage(.gpu)"))

        let quit = try repoText("Pulse/ViewModels/MemoryDashboardVM+QuitSession.swift")
        XCTAssertEqual(occurrenceCount(of: "guard selectedPage.allowsProcessQuit else { return }", in: quit), 2)
    }

    private func sampleFacts() -> MachineFacts {
        MachineFacts(
            chipName: "Apple M3 Pro",
            os: MachineOSVersion(major: 15, minor: 6, patch: 1),
            uptime: 90,
            power: MachinePower(source: .battery, batteryPercent: 42, lowPowerMode: false),
            volume: MachineVolume(availableBytes: 100, totalBytes: 200)
        )
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
