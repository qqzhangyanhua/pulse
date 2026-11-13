import XCTest
@testable import SamplingCore

/// Network, GPU, thermal, battery, machine, and snapshot transitions on `DashboardCore`.
final class DashboardCorePagesTests: XCTestCase {
    func testPublicIPClickWhileLoadingDoesNothing() {
        var core = DashboardCore(ownPid: 42)
        let clickedAt = Date(timeIntervalSince1970: 1_700_000_000)
        let started = core.requestPublicIP(now: clickedAt)

        XCTAssertEqual(started, [.lookupPublicIP(queriedAt: clickedAt)])
        XCTAssertEqual(core.publicIPRequest, .loading)

        let again = core.requestPublicIP(now: Date(timeIntervalSince1970: 1_700_000_010))
        XCTAssertEqual(again, [])
        XCTAssertEqual(core.publicIPRequest, .loading)
        XCTAssertFalse(again.contains(.requestLocationAuthorization))
    }

    func testFailedPublicIPLookupClearsThePreviousAddress() {
        var core = DashboardCore(ownPid: 42)
        let firstClick = Date(timeIntervalSince1970: 1_700_000_000)
        XCTAssertEqual(core.requestPublicIP(now: firstClick), [.lookupPublicIP(queriedAt: firstClick)])
        _ = core.finishPublicIPLookup(address: "203.0.113.9", queriedAt: firstClick)
        XCTAssertEqual(
            core.publicIPRequest,
            .success(address: "203.0.113.9", queriedAt: firstClick)
        )

        let retryAt = Date(timeIntervalSince1970: 1_700_000_040)
        XCTAssertEqual(core.requestPublicIP(now: retryAt), [.lookupPublicIP(queriedAt: retryAt)])
        _ = core.finishPublicIPLookup(address: nil, queriedAt: retryAt)

        XCTAssertEqual(core.publicIPRequest, .failure)
        if case .success = core.publicIPRequest {
            XCTFail("a failed lookup must not keep the previous address")
        }
    }

    func testLocationPermissionIsRequestedOnlyFromTheAllowClick() {
        var core = DashboardCore(ownPid: 42)
        XCTAssertEqual(core.allowWiFiSSID(), [.requestLocationAuthorization])
        XCTAssertEqual(core.apply(ssidPermission: .authorized), [])
        XCTAssertEqual(core.ssidPermission, .authorized)

        let link = HostConnection(status: .connected, interface: .wifi)
        XCTAssertEqual(core.apply(hostConnection: link), [])
        XCTAssertEqual(core.hostConnection, link)
        XCTAssertFalse(core.selectPage(.network).contains(.requestLocationAuthorization))

        let sampled = core.apply(
            result: Result<SampledFrame, PageDeliveryError>.success(frame(cpu: 20, pid: 7)),
            accepted: true,
            page: .network
        )
        XCTAssertFalse(sampled.contains(.requestLocationAuthorization))
        XCTAssertFalse(containsPublicIPLookup(sampled))
        XCTAssertEqual(core.publicIPRequest, .idle)
        XCTAssertEqual(core.hostWiFi?.ssid, "Office")
    }

    func testThermalNoticeAndAdviceFollowTheConditionAndThrottle() {
        var core = DashboardCore(ownPid: 42)
        XCTAssertNil(core.thermalNotice)
        XCTAssertNil(core.thermalAdvice)

        XCTAssertEqual(core.apply(thermalCondition: .nominal), [])
        XCTAssertNil(core.thermalNotice)
        XCTAssertEqual(core.apply(thermalCondition: .fair), [])
        XCTAssertNil(core.thermalNotice)
        XCTAssertEqual(core.apply(thermalCondition: .unknown), [])
        XCTAssertNil(core.thermalNotice)

        XCTAssertEqual(core.apply(thermalCondition: .critical), [])
        XCTAssertEqual(core.thermalNotice, "系统正在降频以控制温度")
        XCTAssertNil(core.thermalAdvice)

        let failed = core.apply(
            result: Result<SampledFrame, PageDeliveryError>.failure(.unavailable),
            accepted: true,
            page: .memory
        )
        XCTAssertFalse(containsPublicIPLookup(failed))
        XCTAssertNil(core.thermalAdvice)

        let firstAt = Date(timeIntervalSince1970: 1_700_000_000)
        _ = core.apply(
            result: success(frame(rows: [
                row(pid: 42, name: "Pulse", cpu: 99),
                row(pid: 7, name: "Mail", cpu: 40),
                row(pid: 8, name: "Notes", cpu: nil),
            ], capturedAt: firstAt)),
            accepted: true,
            page: .memory
        )
        XCTAssertEqual(core.thermalNotice, "系统正在降频以控制温度")
        XCTAssertEqual(core.thermalAdvice?.processes.map(\.pid), [7])
        XCTAssertEqual(core.thermalAdvice?.processes.map(\.cpuPercent), [40])
        XCTAssertEqual(core.thermalAdvice?.noHighLoad, false)

        _ = core.apply(
            result: success(frame(rows: [
                row(pid: 7, name: "Mail", cpu: 90),
                row(pid: 9, name: "Safari", cpu: 80),
            ], capturedAt: firstAt.addingTimeInterval(1))),
            accepted: true,
            page: .memory
        )
        XCTAssertEqual(core.thermalAdvice?.processes.map(\.pid), [7])
        XCTAssertEqual(core.thermalAdvice?.processes.map(\.cpuPercent), [40])

        _ = core.apply(
            result: success(frame(rows: [
                row(pid: 9, name: "Safari", cpu: 80),
                row(pid: 7, name: "Mail", cpu: 10),
            ], capturedAt: firstAt.addingTimeInterval(5))),
            accepted: true,
            page: .memory
        )
        XCTAssertEqual(core.thermalAdvice?.processes.map(\.pid), [9, 7])
        XCTAssertEqual(core.thermalAdvice?.processes.map(\.cpuPercent), [80, 10])

        XCTAssertEqual(core.apply(thermalCondition: .serious), [])
        XCTAssertEqual(core.thermalNotice, "系统正在降频以控制温度")
        XCTAssertEqual(core.apply(thermalCondition: .nominal), [])
        XCTAssertNil(core.thermalNotice)
        XCTAssertNil(core.thermalAdvice)

        XCTAssertEqual(core.apply(thermalCondition: .serious), [])
        _ = core.apply(
            result: success(frame(rows: [row(pid: 3, name: "Finder", cpu: 55)], capturedAt: firstAt.addingTimeInterval(6))),
            accepted: true,
            page: .memory
        )
        XCTAssertEqual(core.thermalAdvice?.processes.map(\.pid), [3])
    }

    func testUnmeasuredThermalAdviceDoesNotThrottleAndLowLoadPublishes() {
        var quiet = DashboardCore(ownPid: 42)
        _ = quiet.apply(thermalCondition: .serious)
        let started = Date(timeIntervalSince1970: 1_800_000_000)
        _ = quiet.apply(
            result: success(frame(rows: [
                row(pid: 42, name: "Pulse", cpu: 70),
                row(pid: 4, name: "Notes", cpu: nil),
            ], capturedAt: started)),
            accepted: true,
            page: .memory
        )
        XCTAssertNil(quiet.thermalAdvice)
        XCTAssertEqual(quiet.thermalNotice, "系统正在降频以控制温度")

        _ = quiet.apply(
            result: success(frame(rows: [row(pid: 4, name: "Notes", cpu: 15)], capturedAt: started.addingTimeInterval(1))),
            accepted: true,
            page: .memory
        )
        XCTAssertEqual(quiet.thermalAdvice?.processes.map(\.pid), [4])

        var low = DashboardCore(ownPid: 1)
        _ = low.apply(thermalCondition: .serious)
        _ = low.apply(
            result: success(frame(rows: [
                row(pid: 5, name: "Mail", cpu: 9.9),
                row(pid: 6, name: "Maps", cpu: 1),
            ], capturedAt: started)),
            accepted: true,
            page: .memory
        )
        XCTAssertEqual(low.thermalAdvice?.processes, [])
        XCTAssertEqual(low.thermalAdvice?.noHighLoad, true)

        _ = low.apply(
            result: success(frame(rows: [row(pid: 5, name: "Mail", cpu: 50)], capturedAt: started.addingTimeInterval(4))),
            accepted: true,
            page: .memory
        )
        XCTAssertEqual(low.thermalAdvice?.noHighLoad, true)
        XCTAssertEqual(low.thermalAdvice?.processes, [])
    }

    func testEmptyBatteryReadingHidesTheCard() {
        var core = DashboardCore(ownPid: 1)
        XCTAssertNil(core.energyBatteryCard)
        XCTAssertNil(core.energyBatteryReading)

        _ = core.apply(energyBatteryReading: .absent)
        XCTAssertNil(core.energyBatteryCard)
        XCTAssertEqual(core.energyBatteryReading, .absent)

        let laptop = EnergyBatteryReading(
            hasInternalBattery: true,
            percent: 40,
            supply: .battery,
            charging: false,
            lowPowerMode: true,
            remainingSeconds: 90,
            minutesToFull: nil
        )
        _ = core.apply(energyBatteryReading: laptop)
        XCTAssertEqual(core.energyBatteryCard?.percent, "40%")
        XCTAssertEqual(core.energyBatteryCard?.power, "电池")
        XCTAssertEqual(core.energyBatteryCard?.lowPowerMode, "低电量模式")
        XCTAssertEqual(core.energyBatteryReading, laptop)

        _ = core.apply(energyBatteryReading: .absent)
        XCTAssertNil(core.energyBatteryCard)

        _ = core.apply(energyBatteryReading: laptop)
        let onEnergy = core.apply(
            result: success(frame(rows: [row(pid: 7, name: "Mail", cpu: 1, watts: 6.5)], capturedAt: Date(timeIntervalSince1970: 1_700_000_000))),
            accepted: true,
            page: .energy
        )
        XCTAssertFalse(containsPublicIPLookup(onEnergy))
        XCTAssertEqual(core.energyMachineHistory.points.last?.batteryPercent, 40)

        _ = core.apply(
            result: success(frame(rows: [row(pid: 7, name: "Mail", cpu: 1, watts: 4)], capturedAt: Date(timeIntervalSince1970: 1_700_000_060))),
            accepted: true,
            page: .memory
        )
        XCTAssertNil(core.energyMachineHistory.points.last?.batteryPercent)

        var desktop = DashboardCore(ownPid: 1)
        _ = desktop.apply(energyBatteryReading: .absent)
        _ = desktop.apply(
            result: success(frame(rows: [row(pid: 7, name: "Mail", cpu: 1, watts: 2)], capturedAt: Date(timeIntervalSince1970: 1_700_000_000))),
            accepted: true,
            page: .energy
        )
        XCTAssertNil(desktop.energyBatteryCard)
        XCTAssertNil(desktop.energyMachineHistory.points.last?.batteryPercent)
    }

    func testMachineFactsStayEmptyUntilTheMachinePageIsOpened() {
        var core = DashboardCore(ownPid: 1)
        XCTAssertNil(core.machineFacts)
        XCTAssertFalse(core.selectPage(.cpu).contains(.startMachineWatch))
        XCTAssertNil(core.machineFacts)

        let entered = core.selectPage(.machine)
        XCTAssertTrue(entered.contains(.startMachineWatch))
        XCTAssertFalse(entered.contains(.requestLocationAuthorization))
        XCTAssertNil(core.machineFacts)
        XCTAssertEqual(core.chipTemperature, .initial)

        let facts = machineFacts()
        XCTAssertEqual(core.apply(machineFacts: facts), [])
        XCTAssertEqual(core.machineFacts?.modelName, "Mac14,10")
        XCTAssertEqual(core.machineFacts?.coreCount, 8)

        XCTAssertEqual(core.apply(machineFacts: facts), [])
        XCTAssertEqual(core.machineFacts, facts)

        let left = core.selectPage(.memory)
        XCTAssertTrue(left.contains(.stopMachineWatch))
        XCTAssertEqual(core.machineFacts, facts)
    }

    func testGPUAndChipPagesResetWhenEnteredAndLeft() {
        var core = DashboardCore(ownPid: 1)
        let entered = core.selectPage(.gpu)
        XCTAssertTrue(entered.contains(.setGPUSampling(on: true)))
        XCTAssertEqual(core.gpuPage.chrome, .skeleton)
        XCTAssertFalse(core.gpuPage.visitSucceeded)

        let capturedAt = Date(timeIntervalSince1970: 1_700_000_000)
        _ = core.apply(
            result: success(frame(rows: [row(pid: 7, name: "Mail", cpu: 1)], capturedAt: capturedAt, gpu: true)),
            accepted: true,
            page: .gpu
        )
        XCTAssertEqual(core.gpuPage.chrome, .readings)
        XCTAssertEqual(core.gpuPage.history.samples.map(\.value), [41])

        _ = core.selectPage(.memory)
        XCTAssertTrue(core.gpuPage.history.samples.isEmpty)
        XCTAssertEqual(core.gpuPage.utilizationPercent, 41)

        _ = core.selectPage(.gpu)
        XCTAssertEqual(core.gpuPage.chrome, .skeleton)
        XCTAssertNil(core.gpuPage.utilizationPercent)
        XCTAssertFalse(core.gpuPage.visitSucceeded)

        var failed = DashboardCore(ownPid: 1)
        _ = failed.apply(
            result: unavailable(),
            accepted: true,
            page: .memory
        )
        XCTAssertTrue(failed.samplingFailed)
        _ = failed.selectPage(.gpu)
        XCTAssertEqual(failed.gpuPage.chrome, .samplingFailure)

        var machine = DashboardCore(ownPid: 1)
        _ = machine.selectPage(.machine)
        _ = machine.apply(
            result: success(frame(rows: [row(pid: 7, name: "Mail", cpu: 1)], capturedAt: capturedAt, chip: true)),
            accepted: true,
            page: .machine
        )
        XCTAssertEqual(machine.chipTemperature.celsius, 62)
        XCTAssertEqual(machine.chipTemperature.history.samples.map(\.value), [62])
        _ = machine.selectPage(.cpu)
        XCTAssertTrue(machine.chipTemperature.history.samples.isEmpty)
        XCTAssertEqual(machine.chipTemperature.celsius, 62)
        _ = machine.selectPage(.machine)
        XCTAssertEqual(machine.chipTemperature, .initial)
    }

    func testSnapshotFreezeUsesThePublishedFrameAndRefusesAnEmptyDashboard() {
        var core = DashboardCore(ownPid: 1)
        let savedAt = Date(timeIntervalSince1970: 1_700_000_500)
        XCTAssertNil(core.frozenSnapshot(savedAt: savedAt))

        let capturedAt = Date(timeIntervalSince1970: 1_700_000_000)
        _ = core.apply(thermalCondition: .serious)
        _ = core.apply(machineFacts: machineFacts())
        _ = core.apply(
            result: success(frame(rows: [row(pid: 7, name: "Mail", cpu: 12, watts: 3)], capturedAt: capturedAt)),
            accepted: true,
            page: .memory
        )
        let frozen = core.frozenSnapshot(savedAt: savedAt)
        XCTAssertEqual(frozen?.savedAt, savedAt)
        XCTAssertEqual(frozen?.capturedAt, capturedAt)
        XCTAssertEqual(frozen?.systemCpuPercent, 37.5)
        XCTAssertEqual(frozen?.busiestCorePercent, 91)
        XCTAssertEqual(frozen?.networkInboundBytesPerSecond, 1_200)
        XCTAssertEqual(frozen?.diskReadBytesPerSecond, 5_600)
        XCTAssertEqual(frozen?.processes.map(\.pid), [7])
        XCTAssertEqual(frozen?.processes.map(\.name), ["Mail"])
        XCTAssertEqual(frozen?.samplingFailed, false)
        XCTAssertNotEqual(frozen?.savedAt, capturedAt)
    }

    private func success(_ frame: SampledFrame) -> Result<SampledFrame, PageDeliveryError> {
        .success(frame)
    }

    private func unavailable() -> Result<SampledFrame, PageDeliveryError> {
        .failure(.unavailable)
    }

    private func containsPublicIPLookup(_ effects: [DashboardEffect]) -> Bool {
        effects.contains { effect in
            if case .lookupPublicIP = effect { return true }
            return false
        }
    }

    private func frame(
        rows: [ProcessRow]? = nil,
        cpu: Double? = nil,
        pid: Int32 = 7,
        capturedAt: Date = Date(timeIntervalSince1970: 1_700_000_000),
        gpu: Bool = false,
        chip: Bool = false
    ) -> SampledFrame {
        let listed = rows ?? [row(pid: pid, name: "Mail", cpu: cpu ?? 12)]
        return SampledFrame(
            snapshot: MemorySnapshot(
                usedBytes: 12_345_678,
                totalBytes: 34_000_000,
                breakdown: MemoryBreakdown(appBytes: 10_000, wiredBytes: 2_000, compressedBytes: 300, cachedBytes: 400),
                pressure: .normal,
                pressureMetric: 0.2,
                pressureSeries: [],
                capturedAt: capturedAt,
                swapUsedBytes: nil
            ),
            rows: listed,
            detail: nil,
            processListFailed: false,
            systemCpuPercent: 37.5,
            hostNetworkRates: HostNetworkRates(inboundBytesPerSecond: 1_200, outboundBytesPerSecond: 340),
            hostDiskRates: HostDiskRates(readBytesPerSecond: 5_600, writeBytesPerSecond: 780),
            topMemorySeries: [:],
            busiestCorePercent: 91,
            gpuNodes: gpu ? [GPUAcceleratorNode(statistics: [
                GPUPageProjection.deviceUtilizationKey: .number(41),
                GPUPageProjection.inUseSystemMemoryKey: .bytes(8_192),
            ])] : nil,
            hostWiFi: HostWiFiReading(rssi: -42, noise: -90, ssid: "Office"),
            chipTemperatureSensors: chip ? [ChipTemperatureSensor(productName: "PMU tdie", celsius: 62)] : nil
        )
    }

    private func row(pid: Int32, name: String, cpu: Double?, watts: Double? = nil) -> ProcessRow {
        ProcessRow(
            pid: pid,
            name: name,
            bundleIdentifier: nil,
            executablePath: nil,
            cpuPercent: cpu,
            memoryBytes: 1_000,
            threadCount: 1,
            energyWatts: watts
        )
    }

    private func machineFacts() -> MachineFacts {
        MachineFacts(
            chipName: "Apple M3",
            modelName: "Mac14,10",
            coreCount: 8,
            physicalMemoryBytes: 16,
            os: MachineOSVersion(major: 14, minor: 5, patch: 0),
            uptime: 30,
            bootedAt: Date(timeIntervalSince1970: 1_699_000_000),
            power: MachinePower(source: .adapter, batteryPercent: nil, lowPowerMode: false),
            battery: nil,
            volume: MachineVolume(availableBytes: 1, totalBytes: 2)
        )
    }
}

private enum PageDeliveryError: Error {
    case unavailable
}
