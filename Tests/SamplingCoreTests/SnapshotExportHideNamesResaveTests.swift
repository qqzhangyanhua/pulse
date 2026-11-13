import Foundation
import XCTest
@testable import SamplingCore

/// 保存成功后切换「隐藏进程名」必须撤销「已保存」。
/// 预览可以变，磁盘上一次成功的文件保持不动，直到下一次写入成功。
/// 相同开关值不撤销。正反两个方向的实际变化都撤销。
final class SnapshotExportHideNamesResaveTests: XCTestCase {
    private let resavePrompt = "隐去项已改变。当前预览还没写入文件，请重新保存。"

    func testSuccessfulSaveThenHideNamesRevokesSavedAcrossCancelFailureAndResave() throws {
        let frozen = try XCTUnwrap(freeze(name: "VisibleName"))
        var session = SnapshotExportSession(frozen: frozen, hideNames: false, calendar: gregorian, timeZone: zone)
        let visibleHTML = session.document.html
        let filename = session.document.suggestedFilename
        session.noteWriteSucceeded()
        XCTAssertEqual(session.banner, "已保存")

        let destination = URL(fileURLWithPath: "/tmp/pulse-snapshot/Pulse.html")
        let io = ResaveFileIO()
        try SnapshotExportFile.commit(data: Data(visibleHTML.utf8), to: destination, io: io)
        XCTAssertEqual(io.files[destination.path], Data(visibleHTML.utf8))
        let writesAfterFirstSave = io.writes.count

        session.setHideNames(true)
        XCTAssertEqual(session.banner, resavePrompt)
        XCTAssertFalse(session.banner?.contains("已保存") ?? false)
        XCTAssertFalse(session.document.previewText.contains("VisibleName"))
        XCTAssertTrue(session.document.previewText.contains("已隐藏"))
        XCTAssertFalse(session.document.html.contains("VisibleName"))
        XCTAssertEqual(session.frozen, frozen)
        XCTAssertEqual(session.frozen.savedAt, savedAt)
        XCTAssertEqual(session.frozen.capturedAt, capturedAt)
        XCTAssertTrue(session.document.previewText.contains("采样时间：1999-08-07 06:05:04"))
        XCTAssertTrue(session.document.previewText.contains("快照生成时间：2001-02-03 04:05:06"))
        XCTAssertEqual(session.document.suggestedFilename, filename)
        XCTAssertEqual(io.writes.count, writesAfterFirstSave)
        XCTAssertEqual(io.files[destination.path], Data(visibleHTML.utf8))

        session.cancelSavePanel()
        XCTAssertEqual(session.banner, resavePrompt)
        XCTAssertFalse(session.banner?.contains("已保存") ?? false)
        XCTAssertEqual(session.frozen, frozen)
        XCTAssertEqual(io.files[destination.path], Data(visibleHTML.utf8))

        let hiddenHTML = session.document.html
        XCTAssertNotEqual(hiddenHTML, visibleHTML)
        io.replaceError = SnapshotExportFileError.replaceFailed
        XCTAssertThrowsError(try SnapshotExportFile.commit(data: Data(hiddenHTML.utf8), to: destination, io: io))
        session.noteWriteFailed()
        XCTAssertEqual(session.banner, "没能写入所选位置。这一份采样还在，可以再试。")
        XCTAssertFalse(session.banner?.contains("已保存") ?? false)
        XCTAssertEqual(io.files[destination.path], Data(visibleHTML.utf8))
        XCTAssertFalse(io.files.keys.contains { $0.contains(".pulse-snapshot-") })

        session.cancelSavePanel()
        XCTAssertNotEqual(session.banner, "已保存")
        XCTAssertFalse(session.banner?.contains("已保存") ?? false)
        XCTAssertEqual(io.files[destination.path], Data(visibleHTML.utf8))
        XCTAssertEqual(session.document.suggestedFilename, filename)
        XCTAssertEqual(session.frozen.savedAt, savedAt)

        io.replaceError = nil
        try SnapshotExportFile.commit(data: Data(session.document.html.utf8), to: destination, io: io)
        session.noteWriteSucceeded()
        XCTAssertEqual(session.banner, "已保存")
        XCTAssertEqual(io.files[destination.path], Data(hiddenHTML.utf8))
        XCTAssertFalse(io.files.keys.contains { $0.contains(".pulse-snapshot-") })
        XCTAssertEqual(session.frozen, frozen)
        XCTAssertEqual(session.document.suggestedFilename, filename)
        XCTAssertTrue(session.document.previewText.contains("已隐藏"))
    }

    func testSameHideNamesValueDoesNotRevokeSaved() throws {
        let frozen = try XCTUnwrap(freeze(name: "VisibleName"))
        var shown = SnapshotExportSession(frozen: frozen, hideNames: false, calendar: gregorian, timeZone: zone)
        shown.noteWriteSucceeded()
        shown.setHideNames(false)
        XCTAssertEqual(shown.banner, "已保存")
        XCTAssertFalse(shown.hideNames)

        var hidden = SnapshotExportSession(frozen: frozen, calendar: gregorian, timeZone: zone)
        hidden.noteWriteSucceeded()
        hidden.setHideNames(true)
        XCTAssertEqual(hidden.banner, "已保存")
        XCTAssertTrue(hidden.hideNames)
        XCTAssertTrue(hidden.document.previewText.contains("已隐藏"))
        XCTAssertEqual(hidden.frozen, frozen)
    }

    func testHidingAndShowingBothRevokeASuccessfulSave() throws {
        let frozen = try XCTUnwrap(freeze(name: "VisibleName"))
        var shown = SnapshotExportSession(frozen: frozen, hideNames: false, calendar: gregorian, timeZone: zone)
        shown.noteWriteSucceeded()
        shown.setHideNames(true)
        XCTAssertEqual(shown.banner, resavePrompt)
        XCTAssertFalse(shown.document.previewText.contains("VisibleName"))
        shown.setHideNames(false)
        XCTAssertEqual(shown.banner, resavePrompt)
        XCTAssertFalse(shown.banner?.contains("已保存") ?? false)
        XCTAssertTrue(shown.document.previewText.contains("VisibleName"))
        XCTAssertEqual(shown.frozen.savedAt, savedAt)
        XCTAssertEqual(shown.document.suggestedFilename, "Pulse-快照-20010203-040506.html")

        var hidden = SnapshotExportSession(frozen: frozen, calendar: gregorian, timeZone: zone)
        hidden.noteWriteSucceeded()
        XCTAssertEqual(hidden.banner, "已保存")
        XCTAssertTrue(hidden.hideNames)
        hidden.setHideNames(false)
        XCTAssertEqual(hidden.banner, resavePrompt)
        XCTAssertTrue(hidden.document.previewText.contains("VisibleName"))
        XCTAssertEqual(hidden.frozen, frozen)
        XCTAssertEqual(hidden.document.suggestedFilename, "Pulse-快照-20010203-040506.html")
    }

    func testHideNamesBeforeAnySaveDoesNotClaimAResave() throws {
        let frozen = try XCTUnwrap(freeze(name: "VisibleName"))
        var session = SnapshotExportSession(frozen: frozen, calendar: gregorian, timeZone: zone)
        XCTAssertTrue(session.hideNames)
        XCTAssertFalse(session.document.previewText.contains("VisibleName"))
        session.setHideNames(false)
        XCTAssertNil(session.banner)
        XCTAssertNotEqual(session.banner, resavePrompt)
        XCTAssertNotEqual(session.banner, "已保存")
        XCTAssertTrue(session.document.previewText.contains("VisibleName"))
        session.setHidesIPAddress(false)
        XCTAssertNil(session.banner)
    }

    func testTurningOffAddressRedactionAfterSaveNeedsAnotherWrite() throws {
        let frozen = try XCTUnwrap(freeze(name: "VisibleName", ipAddress: "203.0.113.9"))
        var session = SnapshotExportSession(frozen: frozen, calendar: gregorian, timeZone: zone)
        XCTAssertFalse(session.document.previewText.contains("203.0.113.9"))
        XCTAssertTrue(session.document.previewText.contains("已隐去：进程名、IP"))
        XCTAssertTrue(session.document.markdown.contains("已隐去：进程名、IP"))
        let hiddenHTML = session.document.html
        XCTAssertFalse(hiddenHTML.contains("203.0.113.9"))
        session.noteWriteSucceeded()
        session.setHidesIPAddress(false)
        XCTAssertEqual(session.banner, resavePrompt)
        XCTAssertFalse(session.banner?.contains("已保存") ?? false)
        XCTAssertTrue(session.document.previewText.contains("IP：203.0.113.9"))
        XCTAssertTrue(session.document.html.contains("IP：203.0.113.9"))
        XCTAssertTrue(session.document.markdown.contains("IP：203.0.113.9"))
        XCTAssertFalse(session.document.previewText.contains("VisibleName"))
        XCTAssertNotEqual(session.document.html, hiddenHTML)
        XCTAssertEqual(session.frozen.ipAddress, "203.0.113.9")
        session.setHidesIPAddress(false)
        XCTAssertEqual(session.banner, resavePrompt)
    }

    private func freeze(name: String, ipAddress: String? = nil) -> SnapshotExport? {
        SnapshotExport.freeze(
            snapshot: MemorySnapshot(
                usedBytes: 50,
                totalBytes: 100,
                breakdown: MemoryBreakdown(appBytes: 10, wiredBytes: 10, compressedBytes: 10, cachedBytes: 10),
                pressure: .normal,
                pressureMetric: 0,
                pressureSeries: [],
                capturedAt: capturedAt,
                swapUsedBytes: 0
            ),
            rows: [
                ProcessRow(
                    pid: 7,
                    name: name,
                    bundleIdentifier: nil,
                    executablePath: nil,
                    cpuPercent: 0,
                    memoryBytes: 50,
                    threadCount: 1
                ),
            ],
            systemCpuPercent: 0,
            busiestCorePercent: 0,
            hostNetworkRates: HostNetworkRates(inboundBytesPerSecond: 0, outboundBytesPerSecond: 0),
            hostDiskRates: HostDiskRates(readBytesPerSecond: 0, writeBytesPerSecond: 0),
            samplingFailed: false,
            processListFailed: false,
            savedAt: savedAt,
            ipAddress: ipAddress
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

private final class ResaveFileIO: SnapshotExportFileIO {
    var files: [String: Data] = [:]
    var writes: [URL] = []
    var replaceError: Error?

    func write(_ data: Data, to url: URL) throws {
        writes.append(url)
        files[url.path] = data
    }

    func replaceItem(at destination: URL, withItemAt temp: URL) throws {
        if let replaceError { throw replaceError }
        guard let data = files[temp.path] else { throw SnapshotExportFileError.replaceFailed }
        files[destination.path] = data
        files[temp.path] = nil
    }

    func removeItem(at url: URL) throws {
        files[url.path] = nil
    }
}
