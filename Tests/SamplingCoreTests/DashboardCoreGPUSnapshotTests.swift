import XCTest
@testable import SamplingCore

/// Frozen snapshots publish the GPU readings from the accepted frame, not a later zero.
final class DashboardCoreGPUSnapshotTests: XCTestCase {
    func testFrozenSnapshotWritesThePublishedGPUReadings() throws {
        var core = DashboardCore(ownPid: 1)
        let savedAt = Date(timeIntervalSince1970: 1_700_000_500)
        let capturedAt = Date(timeIntervalSince1970: 1_700_000_000)
        _ = core.apply(
            result: success(frame(rows: [row(pid: 7, name: "Mail", cpu: 12)], capturedAt: capturedAt)),
            accepted: true,
            page: .memory
        )
        let unread = try XCTUnwrap(core.frozenSnapshot(savedAt: savedAt))
        let unreadDoc = snapshotDocument(unread)
        XCTAssertNil(unread.gpuUtilizationPercent)
        XCTAssertNil(unread.gpuInUseMemoryBytes)
        XCTAssertTrue(unreadDoc.previewText.contains("GPU 使用率：不可用"))
        XCTAssertTrue(unreadDoc.previewText.contains("GPU 占用内存：不可用"))
        XCTAssertFalse(unreadDoc.previewText.contains("GPU 使用率：0.0%"))
        XCTAssertFalse(unreadDoc.previewText.contains("GPU 占用内存：0 字节"))

        _ = core.apply(
            result: success(frame(rows: [row(pid: 7, name: "Mail", cpu: 12)], capturedAt: capturedAt, gpu: true)),
            accepted: true,
            page: .cpu
        )
        let frozen = try XCTUnwrap(core.frozenSnapshot(savedAt: savedAt))
        XCTAssertEqual(frozen.gpuUtilizationPercent, 41)
        XCTAssertEqual(frozen.gpuInUseMemoryBytes, 8_192)
        let doc = snapshotDocument(frozen)
        XCTAssertTrue(doc.previewText.contains("GPU 使用率：41.0%"))
        XCTAssertTrue(doc.html.contains("GPU 使用率：41.0%"))
        XCTAssertTrue(doc.markdown.contains("GPU 占用内存：8 KB"))
        XCTAssertFalse(doc.previewText.contains("GPU 功耗"))
        XCTAssertFalse(doc.previewText.contains("GPU 频率"))

        _ = core.apply(
            result: success(frame(
                rows: [row(pid: 7, name: "Mail", cpu: 12)],
                capturedAt: capturedAt,
                gpuNodes: [GPUAcceleratorNode(statistics: [
                    GPUPageProjection.deviceUtilizationKey: .number(0),
                    GPUPageProjection.inUseSystemMemoryKey: .bytes(0),
                ])]
            )),
            accepted: true,
            page: .machine
        )
        let zero = try XCTUnwrap(core.frozenSnapshot(savedAt: savedAt))
        let zeroDoc = snapshotDocument(zero)
        XCTAssertEqual(zero.gpuUtilizationPercent, 0)
        XCTAssertEqual(zero.gpuInUseMemoryBytes, 0)
        XCTAssertTrue(zeroDoc.previewText.contains("GPU 使用率：0.0%"))
        XCTAssertTrue(zeroDoc.previewText.contains("GPU 占用内存：0 字节"))
        XCTAssertFalse(zeroDoc.previewText.contains("GPU 使用率：不可用"))
    }

    private func snapshotDocument(_ frozen: SnapshotExport) -> SnapshotDocument {
        var calendar = Calendar(identifier: .gregorian)
        let zone = TimeZone(secondsFromGMT: 0)!
        calendar.timeZone = zone
        return SnapshotDocument.make(frozen: frozen, calendar: calendar, timeZone: zone)
    }

    private func success(_ frame: SampledFrame) -> Result<SampledFrame, PageDeliveryError> {
        .success(frame)
    }

    private func frame(
        rows: [ProcessRow]? = nil,
        cpu: Double? = nil,
        pid: Int32 = 7,
        capturedAt: Date = Date(timeIntervalSince1970: 1_700_000_000),
        gpu: Bool = false,
        gpuNodes: [GPUAcceleratorNode]? = nil,
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
            gpuNodes: gpuNodes ?? (gpu ? [GPUAcceleratorNode(statistics: [
                GPUPageProjection.deviceUtilizationKey: .number(41),
                GPUPageProjection.inUseSystemMemoryKey: .bytes(8_192),
            ])] : nil),
            hostWiFi: HostWiFiReading(rssi: -42, noise: -90, ssid: "Office"),
            chipTemperatureSensors: chip ? [ChipTemperatureSensor(productName: "PMU tdie", celsius: 62)] : nil
        )
    }

    private func row(pid: Int32, name: String, cpu: Double?, watts: Double? = nil, path: String? = nil) -> ProcessRow {
        ProcessRow(
            pid: pid,
            name: name,
            bundleIdentifier: nil,
            executablePath: path,
            cpuPercent: cpu,
            memoryBytes: 1_000,
            threadCount: 1,
            energyWatts: watts
        )
    }

}

private enum PageDeliveryError: Error {
    case unavailable
}

