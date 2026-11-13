import XCTest
@testable import SamplingCore

/// Sample application and manual retry on `DashboardCore`. Not a view-model instance.
final class DashboardCoreSampleTests: XCTestCase {
    func testAcceptedSuccessWritesReadingsAndFiveHistories() {
        var core = DashboardCore(ownPid: 42)
        let frame = makeFrame(processListFailed: false)
        let effects = core.apply(
            result: success(frame),
            accepted: true,
            page: .energy,
            batteryPercent: 55,
            selectedPid: nil
        )

        XCTAssertEqual(core.loadState, .ready)
        XCTAssertFalse(core.samplingFailed)
        XCTAssertFalse(core.processListFailed)
        XCTAssertEqual(core.snapshot, frame.snapshot)
        XCTAssertEqual(core.systemCpuPercent, 37.5)
        XCTAssertEqual(core.busiestCorePercent, 91)
        XCTAssertEqual(core.hostNetworkRates.inboundBytesPerSecond, 1_200)
        XCTAssertEqual(core.hostNetworkRates.outboundBytesPerSecond, 340)
        XCTAssertEqual(core.hostDiskRates.readBytesPerSecond, 5_600)
        XCTAssertEqual(core.hostDiskRates.writeBytesPerSecond, 780)
        XCTAssertEqual(core.hostWiFi, HostWiFiReading(rssi: -42, noise: -90, ssid: "Office"))
        XCTAssertEqual(core.rows.map(\.pid), [4242])
        XCTAssertEqual(core.energyWindowRates[4242]?.watts, 4.5)
        XCTAssertEqual(core.energyHourRates[4242]?.watts, 3.25)
        XCTAssertEqual(core.exitedEnergyProcesses.map(\.pid), [77])
        XCTAssertEqual(core.energyLiveGenerations[4242], 4)
        XCTAssertEqual(core.topMemorySeries[4242]?.map(\.value), [999])
        XCTAssertEqual(core.processPermissionFootnote, "footnote-9")
        XCTAssertEqual(core.usageHistory.samples.map(\.value), [12_345_678])
        XCTAssertEqual(core.cpuHistory.samples.map(\.value), [37.5])
        XCTAssertEqual(core.networkHistory.inbound.samples.map(\.value), [1_200])
        XCTAssertEqual(core.networkHistory.outbound.samples.map(\.value), [340])
        XCTAssertEqual(core.diskHistory.read.samples.map(\.value), [5_600])
        XCTAssertEqual(core.diskHistory.write.samples.map(\.value), [780])
        let energyPoint = core.energyMachineHistory.points.last
        XCTAssertEqual(energyPoint?.watts, 6.5)
        XCTAssertEqual(energyPoint?.batteryPercent, 55)
        XCTAssertEqual(core.gpuPage, .initial)
        XCTAssertEqual(core.chipTemperature, .initial)
        XCTAssertEqual(effects, successEffects(now: frame.snapshot.capturedAt.timeIntervalSince1970))
    }

    func testAcceptedSuccessRecordsGPUOrChipOnlyForTheCurrentPage() {
        let frame = makeFrame(processListFailed: false)
        var gpu = DashboardCore(ownPid: 42)
        _ = gpu.apply(
            result: success(frame),
            accepted: true,
            page: .gpu,
            batteryPercent: 55,
            selectedPid: nil
        )
        XCTAssertEqual(gpu.gpuPage.utilizationPercent, 41)
        XCTAssertEqual(gpu.gpuPage.inUseMemoryBytes, 8_192)
        XCTAssertEqual(gpu.gpuPage.chrome, .readings)
        XCTAssertEqual(gpu.gpuPage.history.samples.map(\.value), [41])
        XCTAssertEqual(gpu.chipTemperature, .initial)
        XCTAssertNil(gpu.energyMachineHistory.points.last?.batteryPercent)

        var machine = DashboardCore(ownPid: 42)
        _ = machine.apply(
            result: success(frame),
            accepted: true,
            page: .machine,
            batteryPercent: nil,
            selectedPid: nil
        )
        XCTAssertEqual(machine.chipTemperature.celsius, 62)
        XCTAssertTrue(machine.chipTemperature.visitSucceeded)
        XCTAssertEqual(machine.chipTemperature.history.samples.map(\.value), [62])
        XCTAssertEqual(machine.gpuPage, .initial)
    }

    func testAcceptedFailureKeepsReadingsAndMarksTheCurrentPageFailed() {
        var core = DashboardCore(ownPid: 7)
        let frame = makeFrame(processListFailed: false)
        _ = core.apply(
            result: success(frame),
            accepted: true,
            page: .memory,
            batteryPercent: nil,
            selectedPid: nil
        )
        let effects = core.apply(
            result: unavailable(),
            accepted: true,
            page: .gpu,
            batteryPercent: nil,
            selectedPid: nil
        )

        XCTAssertEqual(core.snapshot?.usedBytes, 12_345_678)
        XCTAssertEqual(core.systemCpuPercent, 37.5)
        XCTAssertNotEqual(core.systemCpuPercent, 0)
        XCTAssertEqual(core.busiestCorePercent, 91)
        XCTAssertEqual(core.rows.map(\.pid), [4242])
        XCTAssertEqual(core.hostNetworkRates.inboundBytesPerSecond, 1_200)
        XCTAssertEqual(core.hostDiskRates.readBytesPerSecond, 5_600)
        XCTAssertEqual(core.hostWiFi?.rssi, -42)
        XCTAssertEqual(core.usageHistory.samples.map(\.value), [12_345_678])
        XCTAssertEqual(core.loadState, .ready)
        XCTAssertTrue(core.samplingFailed)
        XCTAssertFalse(core.processListFailed)
        XCTAssertEqual(core.gpuPage.chrome, .samplingFailure)
        XCTAssertNil(core.gpuPage.utilizationPercent)
        XCTAssertNil(core.gpuPage.inUseMemoryBytes)
        XCTAssertEqual(effects, failureEffects())

        var machine = DashboardCore(ownPid: 7)
        _ = machine.apply(
            result: success(frame),
            accepted: true,
            page: .machine,
            batteryPercent: nil,
            selectedPid: nil
        )
        _ = machine.apply(
            result: unavailable(),
            accepted: true,
            page: .machine,
            batteryPercent: nil,
            selectedPid: nil
        )
        XCTAssertEqual(machine.chipTemperature.celsius, 62)
        XCTAssertNotEqual(machine.chipTemperature.celsius, 0)
        XCTAssertEqual(machine.rows.map(\.pid), [4242])
        XCTAssertTrue(machine.samplingFailed)

        var cold = DashboardCore(ownPid: 7)
        _ = cold.apply(
            result: unavailable(),
            accepted: true,
            page: .gpu,
            batteryPercent: nil,
            selectedPid: nil
        )
        XCTAssertEqual(cold.loadState, .failed)
        XCTAssertTrue(cold.samplingFailed)
        XCTAssertNil(cold.snapshot)
        XCTAssertNil(cold.systemCpuPercent)
        XCTAssertTrue(cold.rows.isEmpty)
        XCTAssertEqual(cold.hostNetworkRates, .missing)
        XCTAssertEqual(cold.hostDiskRates, .missing)
        XCTAssertEqual(cold.gpuPage.chrome, .samplingFailure)
        XCTAssertTrue(cold.cpuHistory.samples.isEmpty)
    }

    func testStaleSampleDoesNotWriteRows() {
        var core = DashboardCore(ownPid: 3)
        _ = core.apply(
            result: success(makeFrame(processListFailed: false)),
            accepted: true,
            page: .memory,
            batteryPercent: nil,
            selectedPid: nil
        )
        var stale = makeFrame(processListFailed: false)
        stale = SampledFrame(
            snapshot: stale.snapshot,
            rows: [row(pid: 111, memory: 1, watts: nil)],
            detail: nil,
            processListFailed: false,
            systemCpuPercent: 1,
            hostNetworkRates: HostNetworkRates(inboundBytesPerSecond: 9, outboundBytesPerSecond: 9),
            hostDiskRates: .missing,
            topMemorySeries: [:],
            busiestCorePercent: 1
        )
        let effects = core.apply(
            result: success(stale),
            accepted: false,
            page: .memory,
            batteryPercent: nil,
            selectedPid: nil
        )

        XCTAssertEqual(core.rows.map(\.pid), [4242])
        XCTAssertEqual(core.systemCpuPercent, 37.5)
        XCTAssertFalse(core.samplingFailed)
        XCTAssertEqual(core.loadState, .ready)
        XCTAssertFalse(effects.contains(.refreshThermalAdvice(now: stale.snapshot.capturedAt.timeIntervalSince1970)))
        XCTAssertFalse(effects.contains(.applyRisingAndWindowedSelection))
        XCTAssertEqual(effects, failureEffects())
    }

    func testProcessListFailureFramePublishesTheFlagWithoutSamplingFailure() {
        var core = DashboardCore(ownPid: 5)
        let capturedAt = Date(timeIntervalSince1970: 1_700_000_100)
        let frame = makeFrame(processListFailed: true, capturedAt: capturedAt, rowPid: 8)
        let effects = core.apply(
            result: success(frame),
            accepted: true,
            page: .memory,
            batteryPercent: nil,
            selectedPid: nil
        )

        XCTAssertTrue(core.processListFailed)
        XCTAssertFalse(core.samplingFailed)
        XCTAssertEqual(core.loadState, .ready)
        XCTAssertEqual(core.snapshot?.usedBytes, 12_345_678)
        XCTAssertEqual(core.rows.map(\.pid), [8])
        XCTAssertNil(core.processPermissionFootnote)
        XCTAssertEqual(effects, successEffects(now: capturedAt.timeIntervalSince1970))
    }

    func testRetryKeepsTheFailurePhaseAndRequestsWake() {
        var cold = DashboardCore(ownPid: 11)
        _ = cold.apply(
            result: unavailable(),
            accepted: true,
            page: .memory,
            batteryPercent: nil,
            selectedPid: nil
        )
        let failedWake = cold.retry()
        XCTAssertEqual(failedWake, [.requestRetryWake])
        XCTAssertEqual(cold.loadState, .failed)
        XCTAssertTrue(cold.samplingFailed)
        XCTAssertFalse(cold.processListFailed)
        XCTAssertNil(cold.snapshot)
        XCTAssertTrue(cold.rows.isEmpty)

        var listed = DashboardCore(ownPid: 11)
        _ = listed.apply(
            result: success(makeFrame(processListFailed: true)),
            accepted: true,
            page: .memory,
            batteryPercent: nil,
            selectedPid: nil
        )
        let listedWake = listed.retry()
        XCTAssertEqual(listedWake, [.requestRetryWake])
        XCTAssertEqual(listed.loadState, .ready)
        XCTAssertFalse(listed.samplingFailed)
        XCTAssertTrue(listed.processListFailed)
        XCTAssertEqual(listed.snapshot?.usedBytes, 12_345_678)
    }

    private func success(_ frame: SampledFrame) -> Result<SampledFrame, SampleDeliveryError> {
        .success(frame)
    }

    private func unavailable() -> Result<SampledFrame, SampleDeliveryError> {
        .failure(.unavailable)
    }

    private func successEffects(now: Double) -> [DashboardEffect] {
        [.refreshThermalAdvice(now: now)] + failureEffects() + [.applyRisingAndWindowedSelection]
    }

    private func failureEffects() -> [DashboardEffect] {
        [
            .replaceListSelection(nil),
            .reconcileEnergySelection,
            .replaceSidebarSubject(nil),
            .replaceDetail(nil),
        ]
    }

    private func makeFrame(
        processListFailed: Bool,
        capturedAt: Date = Date(timeIntervalSince1970: 1_700_000_000),
        rowPid: Int32 = 4242
    ) -> SampledFrame {
        let snapshot = MemorySnapshot(
            usedBytes: 12_345_678,
            totalBytes: 34_000_000,
            breakdown: MemoryBreakdown(
                appBytes: 10_000,
                wiredBytes: 2_000,
                compressedBytes: 300,
                cachedBytes: 400
            ),
            pressure: .elevated,
            pressureMetric: 0.42,
            pressureSeries: [],
            capturedAt: capturedAt,
            swapUsedBytes: 4_096
        )
        return SampledFrame(
            snapshot: snapshot,
            rows: [row(pid: rowPid, memory: 999_000, watts: 6.5)],
            detail: nil,
            processListFailed: processListFailed,
            systemCpuPercent: 37.5,
            hostNetworkRates: HostNetworkRates(inboundBytesPerSecond: 1_200, outboundBytesPerSecond: 340),
            hostDiskRates: HostDiskRates(readBytesPerSecond: 5_600, writeBytesPerSecond: 780),
            topMemorySeries: [rowPid: [ChartSample(id: 7, date: capturedAt, value: 999)]],
            busiestCorePercent: 91,
            permissionFootnote: processListFailed ? nil : "footnote-9",
            energyWindowRates: [rowPid: ProcessEnergyRates(watts: 4.5, wakeupsPerSecond: 3)],
            energyHourRates: [rowPid: ProcessEnergyRates(watts: 3.25, wakeupsPerSecond: 1)],
            exitedEnergyProcesses: [
                ExitedEnergyProcess(
                    pid: 77,
                    generation: 2,
                    name: "Old",
                    rates: ProcessEnergyRates(watts: 1.25, wakeupsPerSecond: 0.5)
                ),
            ],
            energyLiveGenerations: [rowPid: 4],
            gpuNodes: [
                GPUAcceleratorNode(statistics: [
                    GPUPageProjection.deviceUtilizationKey: .number(41),
                    GPUPageProjection.inUseSystemMemoryKey: .bytes(8_192),
                ]),
            ],
            hostWiFi: HostWiFiReading(rssi: -42, noise: -90, ssid: "Office"),
            chipTemperatureSensors: [ChipTemperatureSensor(productName: "PMU tdie", celsius: 62)]
        )
    }

    private func row(pid: Int32, memory: UInt64, watts: Double?) -> ProcessRow {
        ProcessRow(
            pid: pid,
            name: "Mail",
            bundleIdentifier: nil,
            executablePath: nil,
            cpuPercent: 12,
            memoryBytes: memory,
            threadCount: 2,
            energyWatts: watts,
            wakeupsPerSecond: 1.5
        )
    }
}

private enum SampleDeliveryError: Error {
    case unavailable
}
