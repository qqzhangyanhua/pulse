import Foundation
import XCTest
@testable import SamplingCore

/// GPU lines in a saved snapshot. Missing is 「不可用」; a real zero stays zero.
final class SnapshotExportGPUTests: XCTestCase {
    func testSnapshotWritesGPUUtilizationAndInUseMemory() throws {
        let frozen = try XCTUnwrap(freeze(gpuUtilizationPercent: 42.5, gpuInUseMemoryBytes: 2_048))
        let doc = document(frozen)
        assertShared("GPU 使用率", "42.5%", in: doc)
        assertShared("GPU 占用内存", "2 KB", in: doc)
        XCTAssertTrue(doc.markdown.contains("GPU 使用率：42.5%"))
        XCTAssertTrue(doc.markdown.contains("GPU 占用内存：2 KB"))
        for absent in ["GPU 功耗", "GPU 频率", "渲染器", "分块器", "GPU 恢复次数", "核 GPU"] {
            XCTAssertFalse(doc.previewText.contains(absent), absent)
            XCTAssertFalse(doc.html.contains(absent), absent)
            XCTAssertFalse(doc.markdown.contains(absent), absent)
        }
    }

    func testSnapshotWritesUnavailableWhenGPUReadingsAreMissing() throws {
        let frozen = try XCTUnwrap(freeze())
        let doc = document(frozen)
        assertShared("GPU 使用率", "不可用", in: doc)
        assertShared("GPU 占用内存", "不可用", in: doc)
        XCTAssertTrue(doc.markdown.contains("GPU 使用率：不可用"))
        XCTAssertTrue(doc.markdown.contains("GPU 占用内存：不可用"))
        XCTAssertFalse(doc.previewText.contains("GPU 使用率：0.0%"))
        XCTAssertFalse(doc.previewText.contains("GPU 占用内存：0 字节"))
        XCTAssertFalse(doc.html.contains("GPU 使用率：0.0%"))
        XCTAssertFalse(doc.html.contains("GPU 占用内存：0 字节"))
        XCTAssertFalse(doc.markdown.contains("GPU 使用率：0.0%"))
        XCTAssertFalse(doc.markdown.contains("GPU 占用内存：0 字节"))
    }

    func testSnapshotWritesRealZeroGPUReadings() throws {
        let frozen = try XCTUnwrap(freeze(gpuUtilizationPercent: 0, gpuInUseMemoryBytes: 0))
        let doc = document(frozen)
        assertShared("GPU 使用率", "0.0%", in: doc)
        assertShared("GPU 占用内存", "0 字节", in: doc)
        XCTAssertTrue(doc.markdown.contains("GPU 使用率：0.0%"))
        XCTAssertTrue(doc.markdown.contains("GPU 占用内存：0 字节"))
        XCTAssertFalse(doc.previewText.contains("GPU 使用率：不可用"))
        XCTAssertFalse(doc.previewText.contains("GPU 占用内存：不可用"))
        XCTAssertFalse(doc.html.contains("GPU 使用率：不可用"))
        XCTAssertFalse(doc.html.contains("GPU 占用内存：不可用"))
    }

    func testSnapshotKeepsOneGPUReadingWhenTheOtherIsMissing() throws {
        let idleMemory = try XCTUnwrap(freeze(gpuUtilizationPercent: 0, gpuInUseMemoryBytes: nil))
        let idleDoc = document(idleMemory)
        assertShared("GPU 使用率", "0.0%", in: idleDoc)
        assertShared("GPU 占用内存", "不可用", in: idleDoc)

        let quietGPU = try XCTUnwrap(freeze(gpuUtilizationPercent: nil, gpuInUseMemoryBytes: 0))
        let quietDoc = document(quietGPU)
        assertShared("GPU 使用率", "不可用", in: quietDoc)
        assertShared("GPU 占用内存", "0 字节", in: quietDoc)

        let unreadable = try XCTUnwrap(freeze(gpuUtilizationPercent: .nan, gpuInUseMemoryBytes: 4_096))
        let unreadableDoc = document(unreadable)
        assertShared("GPU 使用率", "不可用", in: unreadableDoc)
        assertShared("GPU 占用内存", "4 KB", in: unreadableDoc)
        let lowered = (unreadableDoc.previewText + unreadableDoc.html + unreadableDoc.markdown).lowercased()
        XCTAssertFalse(lowered.contains("nan"))
    }

    func testGPUSnapshotLinesLeaveRedactionUnchanged() throws {
        let frozen = try XCTUnwrap(freeze(
            rows: [row(pid: 4, name: "SecretApp", memory: 9, path: "/Users/alice/bin/tool")],
            hostname: "alices-mac.local",
            ipAddress: "203.0.113.9",
            gpuUtilizationPercent: 12,
            gpuInUseMemoryBytes: 0
        ))
        let doc = document(frozen, redaction: .default)
        assertShared("GPU 使用率", "12.0%", in: doc)
        assertShared("GPU 占用内存", "0 字节", in: doc)
        XCTAssertTrue(doc.markdown.contains("GPU 使用率：12.0%"))
        XCTAssertTrue(doc.markdown.contains("GPU 占用内存：0 字节"))
        let hidden = "已隐去：进程名、带用户名的路径、主机名、IP"
        XCTAssertTrue(doc.previewText.contains(hidden))
        XCTAssertTrue(doc.html.contains(hidden))
        XCTAssertTrue(doc.markdown.contains(hidden))
        for secret in ["SecretApp", "/Users/alice", "alice", "alices-mac.local", "203.0.113.9"] {
            XCTAssertFalse(doc.previewText.contains(secret), secret)
            XCTAssertFalse(doc.html.contains(secret), secret)
            XCTAssertFalse(doc.markdown.contains(secret), secret)
        }
        XCTAssertTrue(doc.previewText.contains("4 · 已隐藏 · 9 字节"))
        XCTAssertFalse(doc.previewText.contains("GPU 使用率：不可用"))
    }

    private func assertShared(
        _ label: String,
        _ value: String,
        in doc: SnapshotDocument,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let expected = "\(label)：\(value)"
        XCTAssertTrue(doc.previewText.contains(expected), expected, file: file, line: line)
        XCTAssertTrue(doc.html.contains(expected), expected, file: file, line: line)
    }

    func document(
        _ frozen: SnapshotExport,
        hideNames: Bool = false,
        redaction: SnapshotRedaction? = nil
    ) -> SnapshotDocument {
        SnapshotDocument.make(
            frozen: frozen,
            redaction: redaction ?? SnapshotRedaction(
                hidesProcessName: hideNames,
                hidesUsernamePath: true,
                hidesHostname: true,
                hidesIPAddress: true
            ),
            calendar: gregorian,
            timeZone: zone
        )
    }

    func freeze(
        used: UInt64 = 2_000,
        total: UInt64 = 8_000,
        app: UInt64 = 100,
        wired: UInt64 = 200,
        compressed: UInt64 = 300,
        cached: UInt64 = 400,
        swap: UInt64? = 0,
        cpu: Double? = 1,
        busiest: Double? = 2,
        inbound: Double? = 3,
        outbound: Double? = 4,
        read: Double? = 5,
        write: Double? = 6,
        pressure: PressureLevel = .elevated,
        rows: [ProcessRow] = [],
        samplingFailed: Bool = false,
        processListFailed: Bool = false,
        hostname: String? = nil,
        ipAddress: String? = nil,
        gpuUtilizationPercent: Double? = nil,
        gpuInUseMemoryBytes: UInt64? = nil
    ) -> SnapshotExport? {
        SnapshotExport.freeze(
            snapshot: hostSnapshot(
                used: used,
                total: total,
                app: app,
                wired: wired,
                compressed: compressed,
                cached: cached,
                swap: swap,
                pressure: pressure
            ),
            rows: rows,
            systemCpuPercent: cpu,
            busiestCorePercent: busiest,
            hostNetworkRates: HostNetworkRates(
                inboundBytesPerSecond: inbound,
                outboundBytesPerSecond: outbound
            ),
            hostDiskRates: HostDiskRates(
                readBytesPerSecond: read,
                writeBytesPerSecond: write
            ),
            samplingFailed: samplingFailed,
            processListFailed: processListFailed,
            savedAt: savedAt,
            hostname: hostname,
            ipAddress: ipAddress,
            gpuUtilizationPercent: gpuUtilizationPercent,
            gpuInUseMemoryBytes: gpuInUseMemoryBytes
        )
    }

    private func hostSnapshot(
        used: UInt64,
        total: UInt64,
        app: UInt64,
        wired: UInt64,
        compressed: UInt64,
        cached: UInt64,
        swap: UInt64?,
        pressure: PressureLevel
    ) -> MemorySnapshot {
        MemorySnapshot(
            usedBytes: used,
            totalBytes: total,
            breakdown: MemoryBreakdown(
                appBytes: app,
                wiredBytes: wired,
                compressedBytes: compressed,
                cachedBytes: cached
            ),
            pressure: pressure,
            pressureMetric: 0.424242,
            pressureSeries: [ChartSample(id: 7, date: capturedAt, value: 424242)],
            capturedAt: capturedAt,
            swapUsedBytes: swap
        )
    }

    func row(
        pid: Int32,
        name: String,
        memory: UInt64,
        cpu: Double? = nil,
        threads: Int = 1,
        source: ProcessMemorySource = .footprint,
        path: String? = "/opt/secret-executable-path-sentinel",
        bundle: String? = "secret.bundle.identifier.sentinel"
    ) -> ProcessRow {
        ProcessRow(
            pid: pid,
            name: name,
            bundleIdentifier: bundle,
            executablePath: path,
            cpuPercent: cpu,
            memoryBytes: memory,
            memorySource: source,
            threadCount: threads,
            diskReadBytesPerSecond: 111_222_333,
            diskWriteBytesPerSecond: 222_333_444,
            energyWatts: 654_321.25,
            wakeupsPerSecond: 777_888.5
        )
    }

    var zone: TimeZone { TimeZone(secondsFromGMT: 8 * 3600)! }

    var gregorian: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        calendar.locale = Locale(identifier: "en_US_POSIX")
        return calendar
    }

    private var capturedAt: Date { date("1999-08-07 06:05:04") }
    var savedAt: Date { date("2001-02-03 04:05:06") }

    private func date(_ text: String) -> Date {
        let formatter = DateFormatter()
        formatter.calendar = gregorian
        formatter.timeZone = zone
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter.date(from: text)!
    }
}
