import Foundation
import XCTest
@testable import SamplingCore

/// 保存面板回调必须带着打开时的会话身份。
/// 旧的、已关闭的、被替换的回调不能写文件，也不能改新会话。
/// 这些测试跑的是纯状态和写入，不是系统保存面板，也不是 VoiceOver。
final class SnapshotExportSavePanelTests: XCTestCase {
    func testClosedOrReplacedCallbackDoesNotWriteOrTouchTheNewSession() throws {
        var gate = SnapshotExportSaveGate()
        gate.present(session(name: "OldName"))
        let oldAttempt = try XCTUnwrap(gate.beginSavePanel())
        let oldHTML = try XCTUnwrap(gate.session?.document.html)
        XCTAssertTrue(oldHTML.contains("OldName"))

        let destination = URL(fileURLWithPath: "/tmp/pulse-snapshot/panel.html")
        let io = PanelFileIO()
        try SnapshotExportFile.commit(data: Data(oldHTML.utf8), to: destination, io: io)
        let writesAfterSave = io.writes.count

        gate.dismiss()
        try deliver(attempt: oldAttempt, confirmed: true, to: destination, io: io, gate: &gate)
        XCTAssertNil(gate.session)
        XCTAssertEqual(io.writes.count, writesAfterSave)
        XCTAssertEqual(io.files[destination.path], Data(oldHTML.utf8))

        gate.present(session(name: "NewName"))
        let newAttempt = try XCTUnwrap(gate.beginSavePanel())
        let newPhaseBefore = gate.session?.phase
        try deliver(attempt: oldAttempt, confirmed: true, to: destination, io: io, gate: &gate)
        XCTAssertEqual(gate.session?.phase, newPhaseBefore)
        XCTAssertNotEqual(gate.session?.banner, "已保存")
        XCTAssertTrue(try XCTUnwrap(gate.session?.document.html).contains("NewName"))
        XCTAssertFalse(try XCTUnwrap(gate.session?.document.html).contains("OldName"))
        XCTAssertEqual(io.files[destination.path], Data(oldHTML.utf8))
        XCTAssertNil(gate.beginSavePanel(), "the new panel stays in flight")

        gate.finishSavePanel(oldAttempt, succeeded: true)
        XCTAssertNotEqual(gate.session?.banner, "已保存")
        XCTAssertEqual(io.files[destination.path], Data(oldHTML.utf8))
        XCTAssertNil(gate.beginSavePanel())

        guard case .write(let html) = gate.receiveSavePanel(newAttempt, confirmed: true) else {
            return XCTFail("the matching panel can still confirm")
        }
        XCTAssertTrue(html.contains("NewName"))
        XCTAssertFalse(html.contains("OldName"))
        XCTAssertNotEqual(gate.session?.banner, "已保存")
        try SnapshotExportFile.commit(data: Data(html.utf8), to: destination, io: io)
        gate.finishSavePanel(newAttempt, succeeded: true)
        XCTAssertEqual(gate.session?.banner, "已保存")
        XCTAssertEqual(io.files[destination.path], Data(html.utf8))
        XCTAssertEqual(gate.session?.frozen.savedAt, savedAt)
        XCTAssertEqual(gate.session?.document.suggestedFilename, "Pulse-快照-20010203-040506.html")
    }

    func testSameSessionCancelKeepsNeedsResaveAndWritesNothing() throws {
        var gate = SnapshotExportSaveGate()
        gate.present(session(name: "VisibleName"))
        gate.noteWriteSucceeded()
        gate.setHideNames(true)
        XCTAssertEqual(gate.session?.banner, SnapshotExportCopy.hideNamesChanged)
        let hidden = try XCTUnwrap(gate.session?.document.html)
        let destination = URL(fileURLWithPath: "/tmp/pulse-snapshot/panel-cancel.html")
        let io = PanelFileIO()
        try SnapshotExportFile.commit(data: Data("OLD".utf8), to: destination, io: io)
        let writes = io.writes.count

        let attempt = try XCTUnwrap(gate.beginSavePanel())
        XCTAssertNil(gate.beginSavePanel())
        let decision = gate.receiveSavePanel(attempt, confirmed: false)
        XCTAssertEqual(decision, .cancelled)
        XCTAssertEqual(gate.session?.banner, SnapshotExportCopy.hideNamesChanged)
        XCTAssertEqual(gate.session?.document.html, hidden)
        XCTAssertEqual(gate.session?.frozen.savedAt, savedAt)
        XCTAssertEqual(gate.session?.document.suggestedFilename, "Pulse-快照-20010203-040506.html")
        XCTAssertEqual(io.writes.count, writes)
        XCTAssertEqual(io.files[destination.path], Data("OLD".utf8))
        XCTAssertNotNil(gate.beginSavePanel())
    }

    func testSameSessionConfirmWritesTheCurrentHiddenDocumentOnlyAfterSuccess() throws {
        var gate = SnapshotExportSaveGate()
        gate.present(session(name: "VisibleName"))
        let attempt = try XCTUnwrap(gate.beginSavePanel())
        gate.setHideNames(true)
        guard case .write(let html) = gate.receiveSavePanel(attempt, confirmed: true) else {
            return XCTFail("confirm returns the current document")
        }
        XCTAssertFalse(html.contains("VisibleName"))
        XCTAssertTrue(html.contains("已隐藏"))
        XCTAssertTrue(html.contains("快照生成时间：2001-02-03 04:05:06"))
        XCTAssertNotEqual(gate.session?.banner, "已保存")
        XCTAssertEqual(gate.session?.document.suggestedFilename, "Pulse-快照-20010203-040506.html")

        let destination = URL(fileURLWithPath: "/tmp/pulse-snapshot/panel-confirm.html")
        let io = PanelFileIO()
        try SnapshotExportFile.commit(data: Data("OLD".utf8), to: destination, io: io)
        io.replaceError = SnapshotExportFileError.replaceFailed
        XCTAssertThrowsError(try SnapshotExportFile.commit(data: Data(html.utf8), to: destination, io: io))
        gate.finishSavePanel(attempt, succeeded: false)
        XCTAssertEqual(gate.session?.banner, SnapshotExportCopy.writeFailure)
        XCTAssertFalse(gate.session?.banner?.contains("已保存") ?? false)
        XCTAssertEqual(io.files[destination.path], Data("OLD".utf8))
        XCTAssertFalse(io.files.keys.contains { $0.contains(".pulse-snapshot-") })

        let retry = try XCTUnwrap(gate.beginSavePanel())
        guard case .write(let retryHTML) = gate.receiveSavePanel(retry, confirmed: true) else {
            return XCTFail("failure releases the panel")
        }
        io.replaceError = nil
        try SnapshotExportFile.commit(data: Data(retryHTML.utf8), to: destination, io: io)
        XCTAssertNotEqual(gate.session?.banner, "已保存")
        gate.finishSavePanel(retry, succeeded: true)
        XCTAssertEqual(gate.session?.banner, "已保存")
        XCTAssertEqual(io.files[destination.path], Data(retryHTML.utf8))
        XCTAssertEqual(gate.session?.frozen.savedAt, savedAt)

        XCTAssertEqual(gate.receiveSavePanel(retry, confirmed: true), .ignore)
        gate.finishSavePanel(retry, succeeded: false)
        XCTAssertEqual(gate.session?.banner, "已保存")
        XCTAssertEqual(io.files[destination.path], Data(retryHTML.utf8))
        XCTAssertNotNil(gate.beginSavePanel())
    }

    func testForeignCallbackDoesNotReleaseTheOpenPanel() throws {
        var gate = SnapshotExportSaveGate()
        gate.present(session(name: "VisibleName"))
        let attempt = try XCTUnwrap(gate.beginSavePanel())
        let stranger = SnapshotExportSaveAttempt(id: UUID(), sessionID: attempt.sessionID)
        XCTAssertEqual(gate.receiveSavePanel(stranger, confirmed: true), .ignore)
        gate.finishSavePanel(stranger, succeeded: true)
        XCTAssertNotEqual(gate.session?.banner, "已保存")
        XCTAssertNil(gate.beginSavePanel())
        XCTAssertEqual(gate.receiveSavePanel(attempt, confirmed: false), .cancelled)
        XCTAssertNil(gate.session?.banner)
        XCTAssertNotNil(gate.beginSavePanel())
    }

    private func deliver(
        attempt: SnapshotExportSaveAttempt,
        confirmed: Bool,
        to destination: URL,
        io: PanelFileIO,
        gate: inout SnapshotExportSaveGate
    ) throws {
        switch gate.receiveSavePanel(attempt, confirmed: confirmed) {
        case .ignore, .cancelled:
            return
        case .write(let html):
            do {
                try SnapshotExportFile.commit(data: Data(html.utf8), to: destination, io: io)
                gate.finishSavePanel(attempt, succeeded: true)
            } catch {
                gate.finishSavePanel(attempt, succeeded: false)
            }
        }
    }

    private func session(name: String) -> SnapshotExportSession {
        let frozen = SnapshotExport.freeze(
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
                    pid: 4,
                    name: name,
                    bundleIdentifier: nil,
                    executablePath: nil,
                    cpuPercent: nil,
                    memoryBytes: 50,
                    threadCount: 1
                ),
            ],
            systemCpuPercent: nil,
            busiestCorePercent: nil,
            hostNetworkRates: .missing,
            hostDiskRates: .missing,
            samplingFailed: false,
            processListFailed: false,
            savedAt: savedAt
        )
        return SnapshotExportSession(frozen: frozen!, calendar: gregorian, timeZone: zone)
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

private final class PanelFileIO: SnapshotExportFileIO {
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
