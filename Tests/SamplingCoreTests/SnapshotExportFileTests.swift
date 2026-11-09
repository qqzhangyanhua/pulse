import Foundation
import XCTest
@testable import SamplingCore

/// 保存当前快照的替换。生成失败或替换前写入失败不得改目标字节；
/// 成功后目标是这份 HTML，目录里不留临时文件。这是文件系统状态，不是保存面板。
final class SnapshotExportFileTests: XCTestCase {
    func testGenerateFailureLeavesExistingBytesUntouched() {
        let destination = URL(fileURLWithPath: "/tmp/pulse-snapshot/Pulse.html")
        let io = MemoryFileIO()
        io.files[destination.path] = Data("OLD".utf8)
        XCTAssertThrowsError(try SnapshotExportFile.commit(data: nil, to: destination, io: io)) { error in
            XCTAssertEqual(error as? SnapshotExportFileError, .generateFailed)
        }
        XCTAssertEqual(io.files[destination.path], Data("OLD".utf8))
        XCTAssertTrue(io.writes.isEmpty)
        XCTAssertTrue(io.replaces.isEmpty)
        XCTAssertFalse(io.files.keys.contains { $0.contains(".pulse-snapshot-") })
    }

    func testWriteFailureBeforeReplaceLeavesExistingBytesAndNoTemp() {
        let destination = URL(fileURLWithPath: "/tmp/pulse-snapshot/Pulse.html")
        let io = MemoryFileIO()
        io.files[destination.path] = Data("OLD".utf8)
        io.writeError = SnapshotExportFileError.writeFailed
        XCTAssertThrowsError(
            try SnapshotExportFile.commit(data: Data("NEW".utf8), to: destination, io: io)
        ) { error in
            XCTAssertEqual(error as? SnapshotExportFileError, .writeFailed)
        }
        XCTAssertEqual(io.files[destination.path], Data("OLD".utf8))
        XCTAssertTrue(io.replaces.isEmpty)
        XCTAssertFalse(io.files.keys.contains { $0.contains(".pulse-snapshot-") })
    }

    func testReplaceFailureLeavesExistingBytesAndRemovesTemp() {
        let destination = URL(fileURLWithPath: "/tmp/pulse-snapshot/Pulse.html")
        let io = MemoryFileIO()
        io.files[destination.path] = Data("OLD".utf8)
        io.replaceError = SnapshotExportFileError.replaceFailed
        XCTAssertThrowsError(
            try SnapshotExportFile.commit(data: Data("NEW".utf8), to: destination, io: io)
        ) { error in
            XCTAssertEqual(error as? SnapshotExportFileError, .replaceFailed)
        }
        XCTAssertEqual(io.files[destination.path], Data("OLD".utf8))
        XCTAssertEqual(io.replaces.count, 1)
        XCTAssertFalse(io.files.keys.contains { $0.contains(".pulse-snapshot-") })
    }

    func testSuccessfulReplaceOverwritesTargetAndLeavesNoTemp() throws {
        let destination = URL(fileURLWithPath: "/tmp/pulse-snapshot/Pulse.html")
        let io = MemoryFileIO()
        io.files[destination.path] = Data("OLD".utf8)
        let html = "<html><title>Pulse 采样</title><p>已隐藏</p></html>"
        try SnapshotExportFile.commit(data: Data(html.utf8), to: destination, io: io)
        XCTAssertEqual(io.files[destination.path], Data(html.utf8))
        XCTAssertFalse(io.files.keys.contains { $0.contains(".pulse-snapshot-") })
        XCTAssertEqual(io.writes.count, 1)
        XCTAssertTrue(io.writes[0].lastPathComponent.hasPrefix(".pulse-snapshot-"))
        XCTAssertEqual(io.writes[0].deletingLastPathComponent().path, destination.deletingLastPathComponent().path)
    }

    func testLiveGenerateFailureDoesNotTouchTheTarget() throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let destination = directory.appendingPathComponent("Pulse.html")
        let original = Data("OLD".utf8)
        try original.write(to: destination)
        XCTAssertThrowsError(try SnapshotExportFile.commit(data: nil, to: destination)) { error in
            XCTAssertEqual(error as? SnapshotExportFileError, .generateFailed)
        }
        XCTAssertEqual(try Data(contentsOf: destination), original)
        XCTAssertTrue(try tempNames(in: directory).isEmpty)
    }

    func testLiveWriteFailureBeforeReplaceKeepsExistingBytes() throws {
        let directory = try makeDirectory()
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: directory.path)
            try? FileManager.default.removeItem(at: directory)
        }
        let destination = directory.appendingPathComponent("Pulse.html")
        let original = Data("OLD".utf8)
        try original.write(to: destination)
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: directory.path)
        XCTAssertThrowsError(try SnapshotExportFile.commit(html: "<html></html>", to: destination))
        XCTAssertEqual(try Data(contentsOf: destination), original)
    }

    func testLiveSuccessReplacesTargetAndLeavesNoTemp() throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let destination = directory.appendingPathComponent("Pulse-快照-20010203-040506.html")
        try Data("OLD".utf8).write(to: destination)
        let html = "<html><head><title>Pulse 采样</title></head><body><p>非实时。采样时间不是现在，也不是打开文件的时间。</p></body></html>"
        try SnapshotExportFile.commit(html: html, to: destination)
        XCTAssertEqual(try String(contentsOf: destination, encoding: .utf8), html)
        XCTAssertTrue(try tempNames(in: directory).isEmpty)
    }

    private func makeDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("pulse-snapshot-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private func tempNames(in directory: URL) throws -> [String] {
        try FileManager.default.contentsOfDirectory(atPath: directory.path)
            .filter { $0.hasPrefix(".pulse-snapshot-") }
    }
}

private final class MemoryFileIO: SnapshotExportFileIO {
    var files: [String: Data] = [:]
    var writes: [URL] = []
    var replaces: [(URL, URL)] = []
    var writeError: Error?
    var replaceError: Error?

    func write(_ data: Data, to url: URL) throws {
        writes.append(url)
        if let writeError { throw writeError }
        files[url.path] = data
    }

    func replaceItem(at destination: URL, withItemAt temp: URL) throws {
        replaces.append((destination, temp))
        if let replaceError { throw replaceError }
        guard let data = files[temp.path] else {
            throw SnapshotExportFileError.replaceFailed
        }
        files[destination.path] = data
        files[temp.path] = nil
    }

    func removeItem(at url: URL) throws {
        files[url.path] = nil
    }
}
