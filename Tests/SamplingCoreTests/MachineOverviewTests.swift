import XCTest
@testable import SamplingCore

final class MachineOverviewTests: XCTestCase {
    func testCPUDeltaIsPercentagePoints() {
        let up = overview(cpuPercent: 63.4, cpuSeries: series([61.1, 63.4]))
        XCTAssertEqual(up.cpu.value, "63.4%")
        XCTAssertEqual(up.cpu.delta, "较上次 +2.3%")
        XCTAssertNotEqual(up.cpu.delta, "较上次 +3.8%")

        let down = overview(cpuPercent: 61.1, cpuSeries: series([63.4, 61.1]))
        XCTAssertEqual(down.cpu.delta, "较上次 -2.3%")

        let flat = overview(cpuPercent: 10.04, cpuSeries: series([10.0, 10.04]))
        XCTAssertEqual(flat.cpu.delta, "较上次 0.0%")

        let exactZero = overview(cpuPercent: 12, cpuSeries: series([12, 12]))
        XCTAssertEqual(exactZero.cpu.delta, "较上次 0.0%")

        let previous = overview(cpuPercent: 12, cpuSeries: series([10, 50, 12]))
        XCTAssertEqual(previous.cpu.delta, "较上次 -38.0%")
    }

    func testCPUDeltaHidesWhenTheSeriesCannotSupportIt() {
        let onePoint = overview(cpuPercent: 63.4, cpuSeries: series([63.4]))
        XCTAssertNil(onePoint.cpu.delta)
        XCTAssertNil(onePoint.cpu.series)

        let missing = overview(cpuPercent: nil, cpuSeries: series([61.1, 63.4]))
        XCTAssertNil(missing.cpu.delta)
        XCTAssertEqual(missing.cpu.value, "—")
        XCTAssertEqual(missing.cpu.seriesNote, "历史曲线 · 当前值暂不可用")

        let mismatch = overview(cpuPercent: 21, cpuSeries: series([10, 20]))
        XCTAssertNil(mismatch.cpu.delta)
        XCTAssertEqual(mismatch.cpu.value, "21.0%")
        XCTAssertNil(mismatch.cpu.seriesNote)
        XCTAssertEqual(mismatch.cpu.series?.map(\.value), [10, 20])
    }

    func testCPUAndMemorySeriesStayUnchangedOnceTheyHaveTwoPoints() {
        XCTAssertNil(overview(cpuSeries: []).cpu.series)
        XCTAssertNil(overview(cpuSeries: series([4])).cpu.series)
        XCTAssertNil(overview(memorySeries: []).memory.series)
        XCTAssertNil(overview(memorySeries: series([4])).memory.series)

        let cpuPoints = series([0, 4])
        let cpu = overview(cpuPercent: 4, cpuSeries: cpuPoints)
        XCTAssertEqual(cpu.cpu.series, cpuPoints)
        XCTAssertNil(cpu.cpu.seriesNote)

        let memoryPoints = series([0, 1_024])
        let memory = overview(memorySeries: memoryPoints)
        XCTAssertEqual(memory.memory.series, memoryPoints)
        XCTAssertNil(memory.memory.seriesNote)
        XCTAssertEqual(memory.memory.value, "1 KB")
        XCTAssertEqual(memory.memory.caption, "共 2 KB")

        let kept = series((0..<90).map(Double.init))
        let long = overview(cpuPercent: 89, cpuSeries: kept, memorySeries: kept)
        XCTAssertEqual(long.cpu.series, kept)
        XCTAssertEqual(long.memory.series, kept)

        let unread = overview(loadState: .failed, memorySeries: memoryPoints, snapshotHeld: false)
        XCTAssertEqual(unread.memory.series, memoryPoints)
        XCTAssertEqual(unread.memory.seriesNote, HistoryCurvePresentation.unavailable)
        XCTAssertEqual(unread.memory.value, "—")
    }

    func testDiskUsedBytesAndDiagnosticThreshold() {
        let full = overview(facts: facts(available: 0, total: 100))
        XCTAssertEqual(full.disk.title, "磁盘")
        XCTAssertEqual(full.disk.value, "100 字节")
        XCTAssertEqual(full.disk.caption, "共 100 字节 · 已用 100%")
        XCTAssertEqual(status(full, "磁盘空间"), "偏高")
        XCTAssertNil(full.disk.series)

        let empty = overview(facts: facts(available: 100, total: 100))
        XCTAssertEqual(empty.disk.value, "0 字节")
        XCTAssertEqual(empty.disk.caption, "共 100 字节 · 已用 0%")
        XCTAssertEqual(status(empty, "磁盘空间"), "正常")

        let below = overview(facts: facts(available: 11, total: 100))
        XCTAssertEqual(below.disk.value, "89 字节")
        XCTAssertEqual(status(below, "磁盘空间"), "正常")

        let at = overview(facts: facts(available: 10, total: 100))
        XCTAssertEqual(at.disk.value, "90 字节")
        XCTAssertEqual(status(at, "磁盘空间"), "偏高")

        let rounded = overview(facts: facts(available: 105, total: 1_000))
        XCTAssertEqual(status(rounded, "磁盘空间"), "偏高")

        let contradictory = overview(facts: facts(available: 150, total: 100))
        XCTAssertEqual(contradictory.disk.value, "—")
        XCTAssertEqual(contradictory.disk.caption, "共 100 字节")
        XCTAssertEqual(status(contradictory, "磁盘空间"), "暂时读不到")
        XCTAssertNotEqual(status(contradictory, "磁盘空间"), "正常")

        let unread = overview(facts: facts(available: nil, total: nil))
        XCTAssertEqual(unread.disk.value, "—")
        XCTAssertEqual(unread.disk.caption, "—")
        XCTAssertEqual(status(unread, "磁盘空间"), "暂时读不到")

        let zeroTotal = overview(facts: facts(available: 10, total: 0))
        XCTAssertEqual(zeroTotal.disk.value, "—")
        XCTAssertEqual(zeroTotal.disk.caption, "—")
        XCTAssertEqual(status(zeroTotal, "磁盘空间"), "暂时读不到")

        let waiting = overview(facts: nil)
        XCTAssertNil(waiting.disk.value)
        XCTAssertEqual(status(waiting, "磁盘空间"), "暂时读不到")
        XCTAssertNotEqual(status(waiting, "磁盘空间"), "正常")
    }

    func testPowerBarPercentStaysAbsentWithoutAReading() {
        let empty = overview(facts: facts(power: MachinePower(source: .battery, batteryPercent: 0, lowPowerMode: false)))
        XCTAssertEqual(empty.power.value, "0%")
        XCTAssertEqual(empty.power.batteryPercent, 0)
        XCTAssertEqual(empty.power.caption, "电池")
        XCTAssertNil(empty.power.series)

        let desktop = overview(facts: facts(power: MachinePower(source: .adapter, batteryPercent: nil, lowPowerMode: false)))
        XCTAssertEqual(desktop.power.value, "外接电源")
        XCTAssertNil(desktop.power.batteryPercent)
        XCTAssertNil(desktop.power.caption)

        let unknown = overview(facts: facts(power: MachinePower(source: .unknown, batteryPercent: 80, lowPowerMode: false)))
        XCTAssertEqual(unknown.power.value, "—")
        XCTAssertNil(unknown.power.batteryPercent)
        XCTAssertEqual(unknown.power.caption, "—")

        let low = overview(facts: facts(power: MachinePower(source: .battery, batteryPercent: 42, lowPowerMode: true)))
        XCTAssertEqual(low.power.batteryPercent, 42)
        XCTAssertEqual(low.power.caption, "电池 · 低电量模式")
        XCTAssertFalse(visibleText(low).contains("预计"))
    }

    func testPressureRingHasNoScore() {
        let normal = overview(snapshot: sampleSnapshot(pressure: .normal, metric: 0.42))
        XCTAssertEqual(normal.ring.tone, .normal)
        XCTAssertEqual(normal.ring.label, "正常")
        XCTAssertFalse(normal.ring.label?.contains("%") ?? true)
        XCTAssertFalse(normal.ring.label?.contains("0") ?? true)
        XCTAssertEqual(status(normal, "内存压力"), "正常")

        let elevated = overview(snapshot: sampleSnapshot(pressure: .elevated, metric: 0.9))
        XCTAssertEqual(elevated.ring.tone, .elevated)
        XCTAssertEqual(elevated.ring.label, "偏高")
        XCTAssertEqual(status(elevated, "内存压力"), "偏高")

        let sampling = overview(loadState: .sampling, snapshotHeld: false)
        XCTAssertEqual(sampling.ring.tone, .sampling)
        XCTAssertNil(sampling.ring.label)
        XCTAssertEqual(status(sampling, "内存压力"), "正在采样…")
        XCTAssertEqual(sampling.ring.page, .memory)

        let held = overview(snapshot: sampleSnapshot(pressure: .elevated, metric: 0.9), loadState: .failed)
        XCTAssertEqual(held.ring.tone, .elevated)
        XCTAssertEqual(held.ring.label, "偏高")
        XCTAssertEqual(status(held, "内存压力"), "偏高")
    }

    func testDiagnosticsStayOnTwoLevels() {
        let quiet = overview(facts: facts(available: 50, total: 100), cpuPercent: 0)
        XCTAssertEqual(status(quiet, "CPU 负载"), "正常")
        XCTAssertEqual(status(quiet, "磁盘空间"), "正常")

        let below = overview(cpuPercent: 79.9)
        XCTAssertEqual(status(below, "CPU 负载"), "正常")
        XCTAssertEqual(below.cpu.value, "79.9%")

        let at = overview(cpuPercent: 80)
        XCTAssertEqual(status(at, "CPU 负载"), "偏高")

        let missing = overview(cpuPercent: nil)
        XCTAssertEqual(status(missing, "CPU 负载"), "暂时读不到")
        XCTAssertNotEqual(status(missing, "CPU 负载"), "正常")

        let titles = quiet.diagnostics.map(\.title)
        XCTAssertEqual(titles, ["内存压力", "磁盘空间", "CPU 负载"])
        XCTAssertEqual(quiet.diagnostics.map(\.page), [.memory, nil, .cpu])
        XCTAssertFalse(titles.contains("总评"))
    }

    func testLiveUpdateUsesTheSnapshotClock() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let captured = Date(timeIntervalSince1970: 3_661)
        let ready = overview(snapshot: sampleSnapshot(capturedAt: captured), calendar: calendar)
        XCTAssertEqual(ready.liveUpdate, "实时更新 · 01:01:01")

        let held = overview(snapshot: sampleSnapshot(capturedAt: captured), loadState: .failed, calendar: calendar)
        XCTAssertEqual(held.liveUpdate, "实时更新 · 01:01:01")

        let sampling = overview(loadState: .sampling, calendar: calendar, snapshotHeld: false)
        XCTAssertEqual(sampling.liveUpdate, "正在采样…")
        XCTAssertFalse(sampling.liveUpdate.contains(":"))

        let failed = overview(loadState: .failed, calendar: calendar, snapshotHeld: false)
        XCTAssertEqual(failed.liveUpdate, "暂时读不到")
        XCTAssertFalse(failed.liveUpdate.contains("实时更新"))
    }

    func testUptimeDoesNotHandOverASeries() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let model = overview(
            facts: sampleFacts(calendar: calendar),
            cpuSeries: series([1, 2, 3]),
            memorySeries: series([4, 5]),
            calendar: calendar
        )
        XCTAssertEqual(model.identity.model, "Mac14,10")
        XCTAssertEqual(model.identity.chip, "Apple M3 Pro")
        XCTAssertEqual(model.identity.system, "macOS 15.6.1")
        XCTAssertEqual(model.identity.capacity, "12 核 · 18 GB")
        XCTAssertFalse(model.identity.loading)
        XCTAssertEqual(model.uptime.value, "1 分钟")
        XCTAssertEqual(model.uptime.caption, "2026年11月7日 09:05 开机")
        XCTAssertNil(model.uptime.series)
        XCTAssertNil(model.uptime.delta)
        XCTAssertNil(model.disk.series)
        XCTAssertNil(model.power.series)
        XCTAssertNil(model.swap.series)
        XCTAssertEqual(model.swap.value, "0 字节")
        XCTAssertEqual(model.swap.caption, "已用")
        XCTAssertEqual(model.swap.page, .memory)
    }

    func testOverviewCopyAvoidsAlarmWords() {
        var facts = sampleFacts()
        facts.power.lowPowerMode = true
        facts.volume = MachineVolume(availableBytes: 0, totalBytes: 100)
        let model = overview(
            facts: facts,
            snapshot: sampleSnapshot(pressure: .elevated, metric: 0.9),
            cpuPercent: 80,
            cpuSeries: series([70, 80]),
            memorySeries: series([1, 2]),
            thermalNotice: ThermalNotice.throttling
        )
        let text = visibleText(model)
        for word in ["危险", "过热", "一切正常", "良好", "预计"] {
            XCTAssertFalse(text.contains(word), word)
        }
        XCTAssertTrue(text.contains("系统正在降频以控制温度"))
        XCTAssertTrue(text.contains("低电量模式"))
        XCTAssertEqual(model.cpu.page, .cpu)
        XCTAssertEqual(model.memory.page, .memory)
        XCTAssertNil(model.disk.page)
        XCTAssertNil(model.power.page)
        XCTAssertNil(model.uptime.page)
    }

    func testMachineOverviewStaysPortable() throws {
        let package = try repoText("Package.swift")
        XCTAssertTrue(package.contains("\"Models/MachineOverview.swift\""))

        let projection = try repoText("Pulse/Models/MachineOverview.swift")
        XCTAssertFalse(projection.contains("import Darwin"))
        XCTAssertFalse(projection.contains("import AppKit"))
        XCTAssertFalse(projection.contains("import SwiftUI"))
        XCTAssertFalse(projection.contains("import IOKit"))
        XCTAssertFalse(projection.contains("HostMachineReader"))
        XCTAssertFalse(projection.contains("Timer"))

        let overview = try repoText("Pulse/Views/MachineOverviewSection.swift")
        XCTAssertEqual(occurrenceCount(of: "selectPage(.memory)", in: overview), 1)
        XCTAssertEqual(occurrenceCount(of: "selectPage(.cpu)", in: overview), 1)
        XCTAssertFalse(overview.contains("selectedPage ="))
        XCTAssertTrue(overview.contains("SparklineChart"))
        XCTAssertFalse(overview.contains("Timer"))
        XCTAssertFalse(overview.contains("预计"))
        XCTAssertFalse(overview.contains("风扇"))
        XCTAssertFalse(overview.contains("ProcessTablePane"))
        XCTAssertFalse(overview.contains("ProcessDetailSidebar"))
        XCTAssertTrue(overview.contains("vm.thermalNotice"))
        XCTAssertTrue(overview.contains("vm.cpuHistory.samples"))
        XCTAssertTrue(overview.contains("vm.usageHistory.samples"))

        let menu = try repoText("Pulse/MenuBar/MenuBarStatus.swift")
        let popover = try repoText("Pulse/MenuBar/MenuBarPopoverView.swift")
        for source in [menu, popover] {
            XCTAssertFalse(source.contains("磁盘空间"))
            XCTAssertFalse(source.contains("CPU 负载"))
            XCTAssertFalse(source.contains("MachineOverview"))
        }

        let reader = try repoText("Pulse/Sampling/HostMachineReader.swift")
        XCTAssertFalse(reader.contains("风扇"))
        XCTAssertFalse(reader.contains("预计"))
    }

    private func overview(
        facts: MachineFacts? = nil,
        snapshot: MemorySnapshot? = nil,
        loadState: LoadState = .ready,
        cpuPercent: Double? = nil,
        cpuSeries: [ChartSample] = [],
        memorySeries: [ChartSample] = [],
        thermalNotice: String? = nil,
        calendar: Calendar? = nil,
        snapshotHeld: Bool = true
    ) -> MachineOverview.Model {
        var resolved = calendar ?? Calendar(identifier: .gregorian)
        if calendar == nil {
            resolved.timeZone = TimeZone(secondsFromGMT: 0)!
        }
        let resolvedSnapshot = snapshotHeld ? (snapshot ?? sampleSnapshot()) : nil
        return MachineOverview.project(
            facts: facts,
            snapshot: resolvedSnapshot,
            loadState: loadState,
            cpuPercent: cpuPercent,
            cpuSeries: cpuSeries,
            memorySeries: memorySeries,
            thermalNotice: thermalNotice,
            calendar: resolved
        )
    }

    private func status(_ model: MachineOverview.Model, _ title: String) -> String {
        model.diagnostics.first { $0.title == title }?.status ?? ""
    }

    private func visibleText(_ model: MachineOverview.Model) -> String {
        var parts = [model.liveUpdate, model.identity.title, model.ring.label ?? "", model.thermalNotice ?? ""]
        parts.append(contentsOf: [
            model.identity.model, model.identity.chip, model.identity.system, model.identity.capacity,
        ].compactMap { $0 })
        for card in [model.cpu, model.memory, model.disk, model.power, model.uptime, model.swap] {
            parts.append(contentsOf: [card.title, card.value ?? "", card.caption ?? "", card.delta ?? "", card.seriesNote ?? ""])
        }
        for item in model.diagnostics {
            parts.append(item.title)
            parts.append(item.status)
        }
        return parts.joined(separator: "\n")
    }

    private func series(_ values: [Double]) -> [ChartSample] {
        values.enumerated().map { index, value in
            ChartSample(id: UInt64(index + 1), date: Date(timeIntervalSince1970: TimeInterval(index)), value: value)
        }
    }

    private func facts(
        available: UInt64? = 100,
        total: UInt64? = 200,
        power: MachinePower = MachinePower(source: .battery, batteryPercent: 42, lowPowerMode: false)
    ) -> MachineFacts {
        var facts = sampleFacts()
        facts.volume = MachineVolume(availableBytes: available, totalBytes: total)
        facts.power = power
        return facts
    }

    private func sampleFacts(calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }()) -> MachineFacts {
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
        swap: UInt64? = 0,
        capturedAt: Date = Date(timeIntervalSince1970: 0)
    ) -> MemorySnapshot {
        MemorySnapshot(
            usedBytes: 1_024,
            totalBytes: 2_048,
            breakdown: MemoryBreakdown(appBytes: 1_024, wiredBytes: 0, compressedBytes: 0, cachedBytes: 0),
            pressure: pressure,
            pressureMetric: metric,
            pressureSeries: [],
            capturedAt: capturedAt,
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
