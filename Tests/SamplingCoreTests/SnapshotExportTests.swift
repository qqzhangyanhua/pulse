import Foundation
import XCTest
@testable import SamplingCore

/// 保存当前快照的文档与预览状态。这些测试锁的是纯函数行为：
/// 预览和 HTML 共用同一次格式化；缺失是「不可用」，真实 0 仍是 0；
/// `savedAt` 由调用方传入且重试不变；前 5 按未过滤内存降序；
/// 隐藏进程名同时作用于预览和 HTML；取消保存面板或写入失败都不报成功。
/// 不创建 SwiftUI，不打开系统保存面板，也不当作本机 GUI 已通过。
final class SnapshotExportTests: XCTestCase {
    func testNilSnapshotRefusesWithoutDocument() {
        let refused = SnapshotExport.freeze(
            snapshot: nil,
            rows: [row(pid: 9, name: "still-there", memory: 10)],
            systemCpuPercent: 1,
            busiestCorePercent: 1,
            hostNetworkRates: .missing,
            hostDiskRates: .missing,
            samplingFailed: true,
            processListFailed: false,
            savedAt: savedAt
        )
        XCTAssertNil(refused)
        XCTAssertEqual(SnapshotExportCopy.noSampleMessage, "暂无可保存的采样，请稍后重试")
    }

    func testPreviewAndHTMLShareMissingAndRealZero() throws {
        let frozen = try XCTUnwrap(freeze(
            used: 0,
            swap: nil,
            cpu: nil,
            busiest: 0,
            inbound: nil,
            outbound: 0,
            read: nil,
            write: 0,
            pressure: .normal,
            rows: [row(pid: 4, name: "ZeroApp", memory: 0, cpu: 0, threads: 0)]
        ))
        let doc = document(frozen)
        assertShared("已用", ByteFormat.memory(0), in: doc)
        assertShared("交换", "不可用", in: doc)
        assertShared("整机 CPU", "不可用", in: doc)
        assertShared("最忙一核", "0.0%", in: doc)
        assertShared("网络下行", "不可用", in: doc)
        assertShared("网络上行", "0 字节/秒", in: doc)
        assertShared("磁盘读取", "不可用", in: doc)
        assertShared("磁盘写入", "0 字节/秒", in: doc)
        assertShared("压力", "正常", in: doc)
        XCTAssertTrue(doc.previewText.contains("4 · ZeroApp · 0 字节 · 内存占用 · 0.0% · 0"))
        XCTAssertTrue(doc.html.contains("0 字节"))
        XCTAssertTrue(doc.html.contains("0.0%"))
        XCTAssertFalse(doc.previewText.contains("交换：0 字节"))
        XCTAssertFalse(doc.previewText.contains("整机 CPU：0.0%"))
        XCTAssertFalse(doc.html.contains("交换：0 字节"))
        XCTAssertFalse(doc.html.contains("整机 CPU：0.0%"))
        XCTAssertTrue(doc.previewText.contains(SnapshotExportCopy.notLive))
        XCTAssertTrue(doc.html.contains(SnapshotExportCopy.notLive))
        XCTAssertTrue(doc.previewText.contains(SnapshotExportCopy.rateExplanation))
        XCTAssertTrue(doc.html.contains(SnapshotExportCopy.rateExplanation))
        XCTAssertFalse(doc.previewText.contains(SnapshotExportCopy.staleSample))
        XCTAssertEqual(doc.previewText.contains("不可用"), doc.html.contains("不可用"))
    }

    func testOneSideCanBeMissingWhileTheOtherZeroStaysZero() throws {
        let frozen = try XCTUnwrap(freeze(
            swap: nil,
            cpu: 0,
            busiest: nil,
            inbound: 0,
            outbound: nil,
            read: 0,
            write: nil
        ))
        let doc = document(frozen)
        assertShared("交换", "不可用", in: doc)
        assertShared("已用", ByteFormat.memory(frozen.usedBytes), in: doc)
        assertShared("整机 CPU", "0.0%", in: doc)
        assertShared("最忙一核", "不可用", in: doc)
        assertShared("网络下行", "0 字节/秒", in: doc)
        assertShared("网络上行", "不可用", in: doc)
        assertShared("磁盘读取", "0 字节/秒", in: doc)
        assertShared("磁盘写入", "不可用", in: doc)
    }

    func testNonFiniteRatesAreUnavailableNotZero() throws {
        let frozen = try XCTUnwrap(freeze(
            cpu: .nan,
            busiest: .infinity,
            inbound: -.infinity,
            outbound: .nan,
            read: .infinity,
            write: 0
        ))
        let doc = document(frozen)
        for label in ["整机 CPU", "最忙一核", "网络下行", "网络上行", "磁盘读取"] {
            assertShared(label, "不可用", in: doc)
            XCTAssertFalse(doc.previewText.contains("\(label)：0.0%"))
            XCTAssertFalse(doc.previewText.contains("\(label)：0 字节/秒"))
        }
        assertShared("磁盘写入", "0 字节/秒", in: doc)
        let lowered = (doc.previewText + doc.html).lowercased()
        XCTAssertFalse(lowered.contains("nan"))
        XCTAssertFalse(lowered.contains("inf"))
    }

    func testSamplingFailedKeepsCapturedAtAndSavedAtLabels() throws {
        let frozen = try XCTUnwrap(freeze(samplingFailed: true))
        let doc = document(frozen)
        let captured = "采样时间：1999-08-07 06:05:04"
        let saved = "快照生成时间：2001-02-03 04:05:06"
        XCTAssertTrue(doc.previewText.contains(captured))
        XCTAssertTrue(doc.html.contains(captured))
        XCTAssertTrue(doc.previewText.contains(saved))
        XCTAssertTrue(doc.html.contains(saved))
        XCTAssertFalse(doc.previewText.contains("采样时间：2001-02-03 04:05:06"))
        XCTAssertFalse(doc.html.contains("采样时间：2001-02-03 04:05:06"))
        XCTAssertTrue(doc.previewText.contains(SnapshotExportCopy.staleSample))
        XCTAssertTrue(doc.html.contains(SnapshotExportCopy.staleSample))
        XCTAssertFalse(doc.previewText.contains("保存时间"))
        XCTAssertFalse(doc.html.contains("保存时间"))
        XCTAssertEqual(frozen.capturedAt, capturedAt)
        XCTAssertEqual(frozen.savedAt, savedAt)
    }

    func testDocumentDoesNotReadTheClock() throws {
        let frozen = try XCTUnwrap(freeze())
        let first = document(frozen)
        let second = document(frozen)
        XCTAssertEqual(first, second)
        XCTAssertEqual(first.suggestedFilename, "Pulse-快照-20010203-040506.html")
        XCTAssertTrue(first.previewText.contains("1999-08-07 06:05:04"))
        XCTAssertTrue(first.previewText.contains("2001-02-03 04:05:06"))
        XCTAssertFalse(first.suggestedFilename.contains("1999"))
        XCTAssertFalse(first.html.contains("<title>Pulse 采样</title>") == false)
        XCTAssertFalse(first.html.contains("<script"))
        XCTAssertFalse(first.html.contains("href"))
        XCTAssertFalse(first.html.contains("src="))
        XCTAssertFalse(first.html.contains("javascript:"))
        XCTAssertFalse(first.html.contains("<!--"))
    }

    func testTopFiveUsesUnfilteredMemoryOrderAndDoesNotMergeNames() throws {
        let rows = [
            row(pid: 10, name: "Low", memory: 500, cpu: 1),
            row(pid: 3, name: "TwinA", memory: 900, cpu: 1, threads: 3),
            row(pid: 7, name: "TwinB", memory: 900, cpu: 1),
            row(pid: 4, name: "TwinA", memory: 900, cpu: nil, threads: 2),
            row(pid: 8, name: "Dropped", memory: 100, cpu: 50),
            row(pid: 1, name: "Mid", memory: 800, cpu: 1, source: .resident),
            row(pid: 2, name: "BusyCPU", memory: 50, cpu: 400, threads: 9),
        ]
        let frozen = try XCTUnwrap(freeze(rows: rows))
        XCTAssertEqual(frozen.processes.map(\.pid), rows.map(\.pid))
        XCTAssertEqual(frozen.processes.map(\.name), rows.map(\.name))
        let doc = document(frozen)
        let order = ["3 · TwinA", "4 · TwinA", "7 · TwinB", "1 · Mid", "10 · Low"]
        assertOrder(order, in: doc.previewText)
        let htmlOrder = ["<td>3</td><td>TwinA</td>", "<td>4</td><td>TwinA</td>", "<td>7</td><td>TwinB</td>", "<td>1</td><td>Mid</td>", "<td>10</td><td>Low</td>"]
        assertOrder(htmlOrder, in: doc.html)
        XCTAssertTrue(doc.previewText.contains("4 · TwinA · 900 字节 · 内存占用 · 不可用 · 2"))
        XCTAssertTrue(doc.html.contains("<td>4</td><td>TwinA</td><td>900 字节</td><td>内存占用</td><td>不可用</td><td>2</td>"))
        XCTAssertTrue(doc.previewText.contains("1 · Mid"))
        XCTAssertTrue(doc.previewText.contains("驻留内存"))
        XCTAssertTrue(doc.html.contains("<td>驻留内存</td>"))
        XCTAssertFalse(doc.previewText.contains("8 · Dropped"))
        XCTAssertFalse(doc.html.contains("Dropped"))
        XCTAssertFalse(doc.previewText.contains("2 · BusyCPU"))
        XCTAssertFalse(doc.html.contains("BusyCPU"))
        XCTAssertFalse(doc.previewText.contains("当前只有"))
        XCTAssertTrue(doc.previewText.contains(SnapshotExportCopy.rankExplanation))
        XCTAssertTrue(doc.html.contains(SnapshotExportCopy.rankExplanation))
    }

    func testShortListStatesTheActualCount() throws {
        let three = try XCTUnwrap(freeze(rows: [
            row(pid: 5, name: "A", memory: 3),
            row(pid: 6, name: "B", memory: 2),
            row(pid: 7, name: "C", memory: 1),
        ]))
        let threeDoc = document(three)
        XCTAssertTrue(threeDoc.previewText.contains("当前只有 3 个进程。"))
        XCTAssertTrue(threeDoc.html.contains("当前只有 3 个进程。"))
        XCTAssertTrue(threeDoc.previewText.contains("5 · A"))
        XCTAssertFalse(threeDoc.previewText.contains("进程列表没有读到。"))

        let none = try XCTUnwrap(freeze(rows: []))
        let noneDoc = document(none)
        XCTAssertTrue(noneDoc.previewText.contains("当前只有 0 个进程。"))
        XCTAssertTrue(noneDoc.html.contains("当前只有 0 个进程。"))
        XCTAssertFalse(noneDoc.previewText.contains("进程列表没有读到。"))
        XCTAssertFalse(noneDoc.html.contains("进程列表没有读到。"))
    }

    func testFailedProcessListDoesNotClaimZeroProcesses() throws {
        let frozen = try XCTUnwrap(freeze(
            rows: [row(pid: 5151, name: "ListFailedSentinel", memory: 80)],
            processListFailed: true
        ))
        let doc = document(frozen)
        XCTAssertTrue(doc.previewText.contains("进程列表没有读到。"))
        XCTAssertTrue(doc.html.contains("进程列表没有读到。"))
        XCTAssertFalse(doc.previewText.contains("当前只有"))
        XCTAssertFalse(doc.html.contains("当前只有"))
        XCTAssertFalse(doc.previewText.contains("ListFailedSentinel"))
        XCTAssertFalse(doc.html.contains("ListFailedSentinel"))
        XCTAssertFalse(doc.previewText.contains("5151"))
        XCTAssertFalse(doc.html.contains("5151"))
        XCTAssertTrue(doc.previewText.contains(SnapshotExportCopy.rankExplanation))
        XCTAssertTrue(doc.html.contains(SnapshotExportCopy.rankExplanation))
    }

    func testHiddenNamesStayOutOfPreviewHTMLAndFilename() throws {
        let sentinel = "Name<script>alert(\"x\")'https://pulse.example/\u{0}Z\u{2028}\u{2029}"
        let frozen = try XCTUnwrap(freeze(rows: [row(pid: 11, name: sentinel, memory: 12, path: nil, bundle: nil)]))
        XCTAssertEqual(frozen.processes.first?.name, sentinel)
        var session = SnapshotExportSession(frozen: frozen, calendar: gregorian, timeZone: zone)
        session.setHideNames(true)
        let hidden = session.document
        XCTAssertFalse(hidden.previewText.contains(sentinel))
        XCTAssertFalse(hidden.previewText.contains("Name<script"))
        XCTAssertFalse(hidden.previewText.contains("pulse.example"))
        XCTAssertFalse(hidden.html.contains(sentinel))
        XCTAssertFalse(hidden.html.contains("Name"))
        XCTAssertFalse(hidden.html.contains("pulse.example"))
        XCTAssertFalse(hidden.html.contains("<script"))
        XCTAssertFalse(hidden.suggestedFilename.contains("Name"))
        XCTAssertFalse(hidden.suggestedFilename.contains("pulse.example"))
        XCTAssertTrue(hidden.previewText.contains("已隐藏"))
        XCTAssertTrue(hidden.html.contains("已隐藏"))
        XCTAssertEqual(session.frozen.processes.first?.name, sentinel)
        XCTAssertEqual(hidden.suggestedFilename, "Pulse-快照-20010203-040506.html")

        session.setHideNames(false)
        let shown = session.document
        XCTAssertTrue(shown.previewText.contains(sentinel))
        XCTAssertEqual(shown.suggestedFilename, hidden.suggestedFilename)
        XCTAssertTrue(shown.previewText.contains("采样时间：1999-08-07 06:05:04"))
        XCTAssertTrue(shown.previewText.contains("快照生成时间：2001-02-03 04:05:06"))
        XCTAssertEqual(session.frozen.savedAt, savedAt)
    }

    func testVisibleSentinelIsEscapedInHTML() throws {
        let sentinel = "Name<script>alert(\"x\")'https://pulse.example/\u{0}Z\u{2028}\u{2029}"
        let frozen = try XCTUnwrap(freeze(rows: [row(pid: 11, name: sentinel, memory: 12, path: nil, bundle: nil)]))
        let doc = document(frozen, hideNames: false)
        let escaped = "Name&lt;script&gt;alert(&quot;x&quot;)&#39;https://pulse.example/&#0;Z&#8232;&#8233;"
        XCTAssertTrue(doc.previewText.contains(sentinel))
        XCTAssertTrue(doc.html.contains(escaped))
        XCTAssertFalse(doc.html.contains("<script"))
        XCTAssertFalse(doc.html.contains("alert(\"x\")"))
        XCTAssertFalse(doc.html.contains("href"))
        XCTAssertFalse(doc.html.contains("src="))
        XCTAssertFalse(doc.html.contains("javascript:"))
        XCTAssertFalse(doc.html.contains("data:"))
        XCTAssertNil(doc.html.range(of: #"\son[a-zA-Z]+="#, options: .regularExpression))
        XCTAssertFalse(doc.html.unicodeScalars.contains { $0.value == 0 || $0.value == 0x2028 || $0.value == 0x2029 })
        XCTAssertTrue(doc.html.contains("<title>Pulse 采样</title>"))
        XCTAssertFalse(doc.html.contains(sentinel))
    }

    func testHTMLOmitsPathsBundlesCurvesDiskEnergyAndWakeups() throws {
        let frozen = try XCTUnwrap(freeze(rows: [
            row(pid: 15, name: "Plain", memory: 20),
        ]))
        let doc = document(frozen)
        let blob = doc.previewText + "\n" + doc.html
        for secret in [
            "/opt/secret-executable-path-sentinel",
            "secret.bundle.identifier.sentinel",
            "111222333",
            "222333444",
            "654321",
            "777888",
            "424242",
            "executablePath",
            "bundleIdentifier",
            "energyWatts",
            "wakeupsPerSecond",
            "diskReadBytesPerSecond",
            "diskWriteBytesPerSecond",
            "pressureSeries",
            "pressureMetric",
            "memorySeries",
        ] {
            XCTAssertFalse(blob.contains(secret), secret)
        }
    }

    func testUsedBytesAreNotRebuiltFromCategories() throws {
        let frozen = try XCTUnwrap(freeze(used: 50, app: 100, wired: 100, compressed: 100, cached: 100))
        let doc = document(frozen)
        assertShared("已用", "50 字节", in: doc)
        assertShared("App", "100 字节", in: doc)
        assertShared("联动", "100 字节", in: doc)
        assertShared("被压缩", "100 字节", in: doc)
        assertShared("已缓存", "100 字节", in: doc)
        XCTAssertFalse(doc.previewText.contains("已用：400 字节"))
        XCTAssertFalse(doc.html.contains("已用：400 字节"))
    }

    func testCancelSavePanelKeepsTheSamePreview() throws {
        let frozen = try XCTUnwrap(freeze(rows: [row(pid: 3, name: "Keep", memory: 9)]))
        var session = SnapshotExportSession(frozen: frozen, calendar: gregorian, timeZone: zone)
        let before = session.document
        session.cancelSavePanel()
        XCTAssertEqual(session.phase, .preview)
        XCTAssertNil(session.banner)
        XCTAssertEqual(session.document, before)
        XCTAssertEqual(session.frozen, frozen)
        XCTAssertFalse(session.document.previewText.contains("已保存"))
        XCTAssertFalse(session.document.html.contains("已保存"))
    }

    func testWriteFailureKeepsTheFrameAndDoesNotClaimSaved() throws {
        let frozen = try XCTUnwrap(freeze())
        var session = SnapshotExportSession(frozen: frozen, calendar: gregorian, timeZone: zone)
        let before = session.document
        session.noteWriteFailed()
        XCTAssertEqual(session.phase, .writeFailed)
        XCTAssertEqual(session.banner, "没能写入所选位置。这一份采样还在，可以再试。")
        XCTAssertEqual(session.document, before)
        XCTAssertEqual(session.frozen.savedAt, savedAt)
        XCTAssertEqual(session.document.suggestedFilename, before.suggestedFilename)
        XCTAssertFalse(session.banner?.contains("已保存") ?? false)
        session.cancelSavePanel()
        XCTAssertEqual(session.phase, .writeFailed)
        XCTAssertEqual(session.document, before)
    }

    func testWriteSuccessBannerAppearsOnlyAfterSuccess() throws {
        let frozen = try XCTUnwrap(freeze())
        var session = SnapshotExportSession(frozen: frozen, calendar: gregorian, timeZone: zone)
        XCTAssertNil(session.banner)
        XCTAssertNotEqual(session.banner, "已保存")
        let before = session.document
        session.noteWriteSucceeded()
        XCTAssertEqual(session.phase, .saved)
        XCTAssertEqual(session.banner, "已保存")
        XCTAssertEqual(session.document, before)
        XCTAssertEqual(session.frozen.savedAt, savedAt)
        XCTAssertEqual(session.frozen.capturedAt, capturedAt)
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

    private func assertOrder(_ tokens: [String], in text: String, file: StaticString = #filePath, line: UInt = #line) {
        var cursor = text.startIndex
        for token in tokens {
            guard let range = text.range(of: token, range: cursor..<text.endIndex) else {
                XCTFail("missing \(token)", file: file, line: line)
                return
            }
            cursor = range.upperBound
        }
    }

    private func document(_ frozen: SnapshotExport, hideNames: Bool = false) -> SnapshotDocument {
        SnapshotDocument.make(
            frozen: frozen,
            hideNames: hideNames,
            calendar: gregorian,
            timeZone: zone
        )
    }

    private func freeze(
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
        processListFailed: Bool = false
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
            savedAt: savedAt
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

    private func row(
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

    private var zone: TimeZone { TimeZone(secondsFromGMT: 8 * 3600)! }

    private var gregorian: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        calendar.locale = Locale(identifier: "en_US_POSIX")
        return calendar
    }

    private var capturedAt: Date { date("1999-08-07 06:05:04") }
    private var savedAt: Date { date("2001-02-03 04:05:06") }

    private func date(_ text: String) -> Date {
        let formatter = DateFormatter()
        formatter.calendar = gregorian
        formatter.timeZone = zone
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter.date(from: text)!
    }
}
