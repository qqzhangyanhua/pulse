import AppKit
import Foundation
import SQLite3

/// Writes the draft it is given. Retention and bucketing stay on that draft.
final class HistoryStore: @unchecked Sendable {
    static let shared = HistoryStore()

    private let queue = DispatchQueue(label: "pulse.history-store")
    private var database: OpaquePointer?
    private var fileURL: URL?
    private var sleepObserver: NSObjectProtocol?
    private var wakeObserver: NSObjectProtocol?
    private let sampleTables = ["sample", "minute", "quarter"]
    private let historyTables = ["sample", "minute", "quarter", "top_process", "event"]

    private init() {
        queue.sync {
            open()
            startSleepWatch()
        }
    }

    func write(_ draft: HistoryDraft) {
        queue.sync {
            if database == nil { open() }
            guard let database else { return }
            insertSample(draft.sample, into: "sample", database: database)
            insertSample(draft.minute, into: "minute", database: database)
            insertSample(draft.quarter, into: "quarter", database: database)
            deleteTop(at: draft.topAt, database: database)
            insertTop(draft.top, at: draft.topAt, database: database)
            insertEvents(draft.events, at: draft.sample.at, database: database)
            deleteRows(from: "sample", before: draft.dropRawBefore, database: database)
            deleteRows(from: "minute", before: draft.dropMinuteBefore, database: database)
            deleteRows(from: "quarter", before: draft.retentionCutoff, database: database)
            deleteRows(from: "top_process", before: draft.retentionCutoff, database: database)
            deleteRows(from: "event", before: draft.retentionCutoff, database: database)
        }
    }

    /// Bytes of the history file, plus its wal and shm sidecars. Missing file is nil, not 0.
    func byteCount() -> UInt64? {
        queue.sync { occupiedBytes() }
    }

    func deleteAll() {
        queue.sync {
            if let database {
                sqlite3_close(database)
                self.database = nil
            }
            guard let path = fileURL?.path else { return }
            let manager = FileManager.default
            for suffix in ["-wal", "-shm", ""] {
                let item = path + suffix
                if manager.fileExists(atPath: item) {
                    try? manager.removeItem(atPath: item)
                }
            }
            manager.createFile(atPath: path, contents: Data(), attributes: nil)
        }
    }

    func delete(before date: Date) {
        queue.sync {
            if database == nil { open() }
            guard let database else { return }
            for table in historyTables {
                deleteRows(from: table, before: date, database: database)
            }
        }
    }

    /// Minute rows use the shorter cutoff. Everything else uses the retention cutoff.
    func truncate(dropMinuteBefore: Date, retentionCutoff: Date) {
        queue.sync {
            if database == nil { open() }
            guard let database else { return }
            deleteRows(from: "minute", before: dropMinuteBefore, database: database)
            deleteRows(from: "sample", before: retentionCutoff, database: database)
            deleteRows(from: "quarter", before: retentionCutoff, database: database)
            deleteRows(from: "top_process", before: retentionCutoff, database: database)
            deleteRows(from: "event", before: retentionCutoff, database: database)
        }
    }

    func samples(from start: Date, to end: Date) -> [HistorySample] {
        readSamples(from: "sample", start: start, end: end)
    }

    func minuteSamples(from start: Date, to end: Date) -> [HistorySample] {
        readSamples(from: "minute", start: start, end: end)
    }

    func events(from start: Date, to end: Date) -> [HistoryEvent] {
        datedEvents(from: start, to: end).map(\.event)
    }

    func datedEvents(from start: Date, to end: Date) -> [HistoryStoredEvent] {
        queue.sync {
            if database == nil { open() }
            guard let database else { return [] }
            let sql = "SELECT at, kind, detail FROM event WHERE at >= ? AND at <= ? ORDER BY id"
            var statement: OpaquePointer?
            guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
                return []
            }
            defer { sqlite3_finalize(statement) }
            sqlite3_bind_double(statement, 1, start.timeIntervalSince1970)
            sqlite3_bind_double(statement, 2, end.timeIntervalSince1970)
            var rows: [HistoryStoredEvent] = []
            while sqlite3_step(statement) == SQLITE_ROW {
                guard let event = event(kind: text(statement, 1), detail: text(statement, 2)) else { continue }
                rows.append(HistoryStoredEvent(
                    at: Date(timeIntervalSince1970: sqlite3_column_double(statement, 0)),
                    event: event
                ))
            }
            return rows
        }
    }

    private func event(kind: String?, detail: String?) -> HistoryEvent? {
        switch kind {
        case "pressure":
            guard let detail else { return nil }
            return .pressure(detail)
        case "thermal":
            guard let detail else { return nil }
            return .thermal(detail)
        case "sleep":
            return .sleep
        case "wake":
            return .wake
        default:
            return nil
        }
    }

    private func open() {
        let directory = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("com.qqzhangyanhua.pulse", isDirectory: true)
        fileURL = directory.appendingPathComponent("history.sqlite")
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        } catch {
            return
        }
        let path = directory.appendingPathComponent("history.sqlite").path
        var handle: OpaquePointer?
        guard sqlite3_open(path, &handle) == SQLITE_OK, let handle else {
            sqlite3_close(handle)
            return
        }
        database = handle
        let sql = """
        CREATE TABLE IF NOT EXISTS sample (
          at REAL PRIMARY KEY,
          used_bytes INTEGER,
          pressure TEXT,
          swap_bytes INTEGER,
          cpu REAL,
          net_in REAL,
          net_out REAL,
          disk_read REAL,
          disk_write REAL,
          gpu REAL
        );
        CREATE TABLE IF NOT EXISTS minute (
          at REAL PRIMARY KEY,
          used_bytes INTEGER,
          pressure TEXT,
          swap_bytes INTEGER,
          cpu REAL,
          net_in REAL,
          net_out REAL,
          disk_read REAL,
          disk_write REAL,
          gpu REAL
        );
        CREATE TABLE IF NOT EXISTS quarter (
          at REAL PRIMARY KEY,
          used_bytes INTEGER,
          pressure TEXT,
          swap_bytes INTEGER,
          cpu REAL,
          net_in REAL,
          net_out REAL,
          disk_read REAL,
          disk_write REAL,
          gpu REAL
        );
        CREATE TABLE IF NOT EXISTS top_process (
          at REAL,
          rank INTEGER,
          pid INTEGER,
          name TEXT,
          primary_value REAL
        );
        CREATE TABLE IF NOT EXISTS event (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          at REAL,
          kind TEXT,
          detail TEXT
        );
        """
        var error: UnsafeMutablePointer<CChar>?
        if sqlite3_exec(handle, sql, nil, nil, &error) != SQLITE_OK {
            sqlite3_free(error)
            sqlite3_close(handle)
            database = nil
        }
    }

    private func startSleepWatch() {
        let center = NSWorkspace.shared.notificationCenter
        sleepObserver = center.addObserver(
            forName: NSWorkspace.willSleepNotification,
            object: nil,
            queue: nil
        ) { [weak self] _ in
            self?.writeLifecycle(.sleep)
        }
        wakeObserver = center.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: nil
        ) { [weak self] _ in
            self?.writeLifecycle(.wake)
        }
    }

    private func writeLifecycle(_ lifecycle: HistoryLifecycle) {
        let events = HistoryPolicy.events(
            previousPressure: nil,
            pressure: nil,
            thermal: nil,
            previousThermal: nil,
            lifecycle: lifecycle
        )
        queue.async { [weak self] in
            guard let self else { return }
            if self.database == nil { self.open() }
            guard let database = self.database else { return }
            self.insertEvents(events, at: Date(), database: database)
        }
    }

    private func insertSample(_ sample: HistorySample, into table: String, database: OpaquePointer) {
        guard sampleTables.contains(table) else { return }
        let sql = """
        INSERT OR REPLACE INTO \(table)
        (at, used_bytes, pressure, swap_bytes, cpu, net_in, net_out, disk_read, disk_write, gpu)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        """
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK, let statement else { return }
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_double(statement, 1, sample.at.timeIntervalSince1970)
        bindOptionalInt(statement, 2, sample.usedBytes)
        bindOptionalText(statement, 3, sample.pressure?.rawValue)
        bindOptionalInt(statement, 4, sample.swapUsedBytes)
        bindOptionalDouble(statement, 5, sample.cpuPercent)
        bindOptionalDouble(statement, 6, sample.networkInBytesPerSecond)
        bindOptionalDouble(statement, 7, sample.networkOutBytesPerSecond)
        bindOptionalDouble(statement, 8, sample.diskReadBytesPerSecond)
        bindOptionalDouble(statement, 9, sample.diskWriteBytesPerSecond)
        bindOptionalDouble(statement, 10, sample.gpuPercent)
        sqlite3_step(statement)
    }

    private func deleteTop(at date: Date, database: OpaquePointer) {
        let sql = "DELETE FROM top_process WHERE at = ?"
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK, let statement else { return }
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_double(statement, 1, date.timeIntervalSince1970)
        sqlite3_step(statement)
    }

    private func insertTop(_ rows: [HistoryProcessRank], at date: Date, database: OpaquePointer) {
        let sql = "INSERT INTO top_process (at, rank, pid, name, primary_value) VALUES (?, ?, ?, ?, ?)"
        for (index, row) in rows.enumerated() {
            var statement: OpaquePointer?
            guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK, let statement else { continue }
            defer { sqlite3_finalize(statement) }
            sqlite3_bind_double(statement, 1, date.timeIntervalSince1970)
            sqlite3_bind_int(statement, 2, Int32(index))
            sqlite3_bind_int(statement, 3, row.pid)
            sqlite3_bind_text(statement, 4, row.name, -1, SQLITE_TRANSIENT)
            sqlite3_bind_double(statement, 5, row.primary)
            sqlite3_step(statement)
        }
    }

    private func insertEvents(_ events: [HistoryEvent], at date: Date, database: OpaquePointer) {
        let sql = "INSERT INTO event (at, kind, detail) VALUES (?, ?, ?)"
        for event in events {
            var statement: OpaquePointer?
            guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK, let statement else { continue }
            defer { sqlite3_finalize(statement) }
            sqlite3_bind_double(statement, 1, date.timeIntervalSince1970)
            let kind: String
            let detail: String?
            switch event {
            case .pressure(let value):
                kind = "pressure"
                detail = value
            case .thermal(let value):
                kind = "thermal"
                detail = value
            case .sleep:
                kind = "sleep"
                detail = nil
            case .wake:
                kind = "wake"
                detail = nil
            }
            sqlite3_bind_text(statement, 2, kind, -1, SQLITE_TRANSIENT)
            bindOptionalText(statement, 3, detail)
            sqlite3_step(statement)
        }
    }

    private func deleteRows(from table: String, before date: Date, database: OpaquePointer) {
        guard historyTables.contains(table) else { return }
        let sql = "DELETE FROM \(table) WHERE at < ?"
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK, let statement else { return }
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_double(statement, 1, date.timeIntervalSince1970)
        sqlite3_step(statement)
    }

    private func readSamples(from table: String, start: Date, end: Date) -> [HistorySample] {
        queue.sync {
            guard sampleTables.contains(table) else { return [] }
            if database == nil { open() }
            guard let database else { return [] }
            let sql = """
            SELECT at, used_bytes, pressure, swap_bytes, cpu, net_in, net_out, disk_read, disk_write, gpu
            FROM \(table) WHERE at >= ? AND at <= ? ORDER BY at
            """
            var statement: OpaquePointer?
            guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
                return []
            }
            defer { sqlite3_finalize(statement) }
            sqlite3_bind_double(statement, 1, start.timeIntervalSince1970)
            sqlite3_bind_double(statement, 2, end.timeIntervalSince1970)
            var rows: [HistorySample] = []
            while sqlite3_step(statement) == SQLITE_ROW {
                rows.append(sample(from: statement))
            }
            return rows
        }
    }

    private func sample(from statement: OpaquePointer) -> HistorySample {
        let pressureText = text(statement, 2)
        return HistorySample(
            at: Date(timeIntervalSince1970: sqlite3_column_double(statement, 0)),
            usedBytes: uint64(statement, 1),
            pressure: pressureText.flatMap(PressureLevel.init(rawValue:)),
            swapUsedBytes: uint64(statement, 3),
            cpuPercent: double(statement, 4),
            networkInBytesPerSecond: double(statement, 5),
            networkOutBytesPerSecond: double(statement, 6),
            diskReadBytesPerSecond: double(statement, 7),
            diskWriteBytesPerSecond: double(statement, 8),
            gpuPercent: double(statement, 9)
        )
    }

    private func occupiedBytes() -> UInt64? {
        guard let path = fileURL?.path, let main = byteSize(path) else { return nil }
        var total = main
        if let wal = byteSize(path + "-wal") { total += wal }
        if let shm = byteSize(path + "-shm") { total += shm }
        return total
    }

    private func byteSize(_ path: String) -> UInt64? {
        guard FileManager.default.fileExists(atPath: path) else { return nil }
        guard let number = try? FileManager.default.attributesOfItem(atPath: path)[.size] as? NSNumber else {
            return nil
        }
        return number.uint64Value
    }

    private func double(_ statement: OpaquePointer, _ index: Int32) -> Double? {
        guard sqlite3_column_type(statement, index) != SQLITE_NULL else { return nil }
        return sqlite3_column_double(statement, index)
    }

    private func uint64(_ statement: OpaquePointer, _ index: Int32) -> UInt64? {
        guard sqlite3_column_type(statement, index) != SQLITE_NULL else { return nil }
        return UInt64(bitPattern: sqlite3_column_int64(statement, index))
    }

    private func text(_ statement: OpaquePointer, _ index: Int32) -> String? {
        guard sqlite3_column_type(statement, index) != SQLITE_NULL else { return nil }
        guard let raw = sqlite3_column_text(statement, index) else { return nil }
        return String(cString: UnsafeRawPointer(raw).assumingMemoryBound(to: CChar.self))
    }

    private func bindOptionalInt(_ statement: OpaquePointer, _ index: Int32, _ value: UInt64?) {
        if let value {
            sqlite3_bind_int64(statement, index, Int64(bitPattern: value))
        } else {
            sqlite3_bind_null(statement, index)
        }
    }

    private func bindOptionalDouble(_ statement: OpaquePointer, _ index: Int32, _ value: Double?) {
        if let value {
            sqlite3_bind_double(statement, index, value)
        } else {
            sqlite3_bind_null(statement, index)
        }
    }

    private func bindOptionalText(_ statement: OpaquePointer, _ index: Int32, _ value: String?) {
        if let value {
            sqlite3_bind_text(statement, index, value, -1, SQLITE_TRANSIENT)
        } else {
            sqlite3_bind_null(statement, index)
        }
    }
}

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
