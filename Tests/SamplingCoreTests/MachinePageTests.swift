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
        let label = MachinePageCopy.accessibilityLabel(facts: facts, thermalNotice: nil)
        XCTAssertFalse(label.contains("降频"))
        XCTAssertTrue(label.contains("机型 · Mac14,10"))
        XCTAssertTrue(label.contains("12 核 · 18 GB"))
        XCTAssertTrue(label.contains("开机"))
        XCTAssertTrue(
            MachinePageCopy.accessibilityLabel(facts: facts, thermalNotice: ThermalNotice.throttling)
                .contains("系统正在降频以控制温度")
        )
    }

    func testIdentityAndShortCaptionsDoNotRepeatTheBigNumber() {
        XCTAssertEqual(MachinePageCopy.modelValue(nil), "—")
        XCTAssertEqual(MachinePageCopy.modelValue("  Mac14,10  "), "Mac14,10")
        XCTAssertEqual(
            MachinePageCopy.capacityLine(coreCount: 12, physicalMemoryBytes: 18 * 1_073_741_824),
            "12 核 · 18 GB"
        )
        XCTAssertEqual(
            MachinePageCopy.capacityLine(coreCount: 0, physicalMemoryBytes: nil),
            "— · —"
        )
        XCTAssertFalse(MachinePageCopy.capacityLine(coreCount: 0, physicalMemoryBytes: nil).contains("0 GB"))

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let booted = calendar.date(from: DateComponents(year: 2026, month: 11, day: 7, hour: 9, minute: 5))
        XCTAssertEqual(MachinePageCopy.bootCaption(booted, calendar: calendar), "2026年11月7日 09:05 开机")
        XCTAssertEqual(MachinePageCopy.bootCaption(nil, calendar: calendar), "—")

        XCTAssertEqual(
            MachinePageCopy.powerCaption(source: .battery, percent: 42, lowPowerMode: false),
            "电池"
        )
        XCTAssertEqual(
            MachinePageCopy.powerCaption(source: .battery, percent: 0, lowPowerMode: true),
            "电池 · 低电量模式"
        )
        XCTAssertNil(MachinePageCopy.powerCaption(source: .adapter, percent: nil, lowPowerMode: false))
        XCTAssertEqual(
            MachinePageCopy.powerCaption(source: .adapter, percent: nil, lowPowerMode: true),
            "低电量模式"
        )
        XCTAssertEqual(
            MachinePageCopy.powerCaption(source: .unknown, percent: 80, lowPowerMode: false),
            "—"
        )

        XCTAssertEqual(
            MachinePageCopy.volumeCaption(available: 0, total: 100),
            "共 100 字节 · 已用 100%"
        )
        XCTAssertEqual(
            MachinePageCopy.volumeCaption(available: 100, total: 100),
            "共 100 字节 · 已用 0%"
        )
        XCTAssertEqual(MachinePageCopy.volumeCaption(available: 150, total: 100), "共 100 字节")
        XCTAssertEqual(MachinePageCopy.volumeCaption(available: nil, total: 100), "—")
        XCTAssertEqual(MachinePageCopy.volumeCaption(available: 10, total: 0), "—")
        XCTAssertEqual(
            MachinePageCopy.volumeCaption(available: 1, total: 3),
            "共 3 字节 · 已用 67%"
        )
    }

    func testStatusRowKeepsAHeldSnapshotAndDoesNotInventZero() {
        XCTAssertEqual(MachineStatusCopy.phase(snapshot: nil, loadState: .sampling), .sampling)
        XCTAssertEqual(MachineStatusCopy.phase(snapshot: nil, loadState: .failed), .missing)
        let held = sampleSnapshot()
        XCTAssertEqual(MachineStatusCopy.phase(snapshot: held, loadState: .failed), .ready)

        let sampling = MachineStatusCopy.pressure(snapshot: nil, loadState: .sampling)
        XCTAssertNil(sampling.value)
        XCTAssertEqual(sampling.caption, "正在采样…")
        XCTAssertEqual(sampling.accessibilityValue, "正在采样…")

        let missing = MachineStatusCopy.usedMemory(snapshot: nil, loadState: .failed)
        XCTAssertEqual(missing.value, "—")
        XCTAssertEqual(missing.caption, "暂时读不到")
        XCTAssertFalse(missing.accessibilityValue.contains("0"))

        let pressure = MachineStatusCopy.pressure(snapshot: held, loadState: .ready)
        XCTAssertEqual(pressure.value, "正常")
        XCTAssertEqual(pressure.caption, "42% · 余量充足")
        let elevated = sampleSnapshot(pressure: .elevated, metric: 0.9)
        XCTAssertEqual(
            MachineStatusCopy.pressure(snapshot: elevated, loadState: .ready).caption,
            "余量紧张"
        )

        let used = MachineStatusCopy.usedMemory(snapshot: held, loadState: .ready)
        XCTAssertEqual(used.value, ByteFormat.memory(1_024))
        XCTAssertEqual(used.caption, "共 \(ByteFormat.memory(2_048))")

        let emptySwap = MachineStatusCopy.swap(snapshot: sampleSnapshot(swap: 0), loadState: .ready)
        XCTAssertEqual(emptySwap.value, "0 字节")
        XCTAssertEqual(emptySwap.caption, "已用")
        let unreadSwap = MachineStatusCopy.swap(snapshot: sampleSnapshot(swap: nil), loadState: .ready)
        XCTAssertEqual(unreadSwap.value, "—")
        XCTAssertEqual(unreadSwap.caption, "未采样")

        let cpu = MachineStatusCopy.cpu(snapshot: held, loadState: .ready, percent: 12)
        XCTAssertEqual(cpu.value, "12.0%")
        XCTAssertEqual(cpu.caption, "全机")
        let missingCPU = MachineStatusCopy.cpu(snapshot: held, loadState: .ready, percent: nil)
        XCTAssertEqual(missingCPU.value, "—")
        XCTAssertEqual(missingCPU.caption, "未采样")
        XCTAssertNotEqual(missingCPU.caption, "暂时读不到")

        XCTAssertEqual(
            MachineStatusCopy.buttonLabel(title: "压力", value: "正常", destination: MachineStatusCopy.memoryDestination),
            "压力，正常，打开内存页"
        )
        XCTAssertEqual(
            MachineStatusCopy.buttonLabel(title: "CPU", value: "12.0%", destination: MachineStatusCopy.cpuDestination),
            "CPU，12.0%，打开 CPU 页"
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

        let reader = try repoText("Pulse/Sampling/HostMachineReader.swift")
        XCTAssertTrue(reader.contains("hardwareModel()"))
        XCTAssertTrue(reader.contains("processorCount"))
        XCTAssertTrue(reader.contains("physicalMemory"))
        XCTAssertTrue(reader.contains("bootedAt"))

        let overview = try repoText("Pulse/Views/MachineOverviewSection.swift")
        XCTAssertEqual(occurrenceCount(of: "selectPage(.memory)", in: overview), 1)
        XCTAssertEqual(occurrenceCount(of: "selectPage(.cpu)", in: overview), 1)
        XCTAssertFalse(overview.contains("selectedPage ="))
        XCTAssertTrue(overview.contains("SparklineChart"))
        XCTAssertFalse(overview.contains("Timer"))
        XCTAssertFalse(overview.contains("ProcessTablePane"))
        XCTAssertTrue(overview.contains("vm.thermalNotice"))
    }

    func testBatteryReadStaysOnTheMachinePage() throws {
        let sampler = try repoText("Pulse/Sampling/MemorySampler.swift")
        XCTAssertFalse(sampler.contains("AppleSmartBattery"))
        XCTAssertFalse(sampler.contains("BatteryMath"))

        let reader = try repoText("Pulse/Sampling/HostMachineReader.swift")
        XCTAssertEqual(occurrenceCount(of: "internalBatteryDetails()", in: reader), 2)
        XCTAssertTrue(reader.contains("AppleSmartBattery"))
        XCTAssertTrue(reader.contains("signedMilliamps"))
        XCTAssertEqual(occurrenceCount(of: "signedMilliamps", in: reader), 1)
        XCTAssertTrue(reader.contains("return BatteryMath.plainInteger(uint64: number.uint64Value)"))
        XCTAssertTrue(reader.contains("milliamps: milliamps(properties[\"InstantAmperage\"]) ?? milliamps(properties[\"Amperage\"])"))
        XCTAssertTrue(reader.contains("cycleCount: integer(properties[\"CycleCount\"])"))
        XCTAssertTrue(reader.contains("millivolts: integer(properties[\"Voltage\"])"))
        XCTAssertFalse(reader.contains("milliamps: integer("))
        XCTAssertFalse(reader.contains("电池损坏"))

        let project = try repoText("Pulse.xcodeproj/project.pbxproj")
        XCTAssertEqual(occurrenceCount(of: "BatteryMath.swift in Sources", in: project), 2)
        XCTAssertEqual(occurrenceCount(of: "path = BatteryMath.swift;", in: project), 1)
        XCTAssertEqual(occurrenceCount(of: "A00000000000000000000045 /* BatteryMath.swift */,", in: project), 1)

        let package = try repoText("Package.swift")
        XCTAssertTrue(package.contains("\"Models/BatteryMath.swift\""))
        let excluded = package.components(separatedBy: "exclude:")[1].components(separatedBy: "sources:")[0]
        XCTAssertFalse(excluded.contains("BatteryMath.swift"))

        let dashboard = try repoText("Pulse/ViewModels/MemoryDashboardVM.swift")
        XCTAssertTrue(dashboard.contains("HostMachineReader.read()"))
        XCTAssertFalse(dashboard.contains("AppleSmartBattery"))

        let overview = try repoText("Pulse/Views/MachineOverviewSection.swift")
        XCTAssertTrue(overview.contains("model.battery"))
        XCTAssertTrue(overview.contains("循环次数"))
        XCTAssertTrue(overview.contains("健康度"))
        XCTAssertTrue(overview.contains("功率"))
        XCTAssertFalse(overview.contains("电池损坏"))
    }

    private func sampleFacts() -> MachineFacts {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let booted = calendar.date(from: DateComponents(year: 2026, month: 11, day: 7, hour: 9, minute: 5))
        return MachineFacts(
            chipName: "Apple M3 Pro",
            modelName: "Mac14,10",
            coreCount: 12,
            physicalMemoryBytes: 18 * 1_073_741_824,
            os: MachineOSVersion(major: 15, minor: 6, patch: 1),
            uptime: 90,
            bootedAt: booted,
            power: MachinePower(source: .battery, batteryPercent: 42, lowPowerMode: false),
            volume: MachineVolume(availableBytes: 100, totalBytes: 200)
        )
    }

    private func sampleSnapshot(
        pressure: PressureLevel = .normal,
        metric: Double = 0.42,
        swap: UInt64? = 0
    ) -> MemorySnapshot {
        MemorySnapshot(
            usedBytes: 1_024,
            totalBytes: 2_048,
            breakdown: MemoryBreakdown(
                appBytes: 1_024,
                wiredBytes: 0,
                compressedBytes: 0,
                cachedBytes: 0
            ),
            pressure: pressure,
            pressureMetric: metric,
            pressureSeries: [],
            capturedAt: Date(timeIntervalSince1970: 0),
            swapUsedBytes: swap
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
