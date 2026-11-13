import AppKit
import Foundation
import SQLite3

/// Writes rows it is given. Retention and gaps stay in `HistoryPolicy`.
final class HistoryStore: @unchecked Sendable {
    static let shared = HistoryStore()

    private let queue = DispatchQueue(label: "pulse.history-store")
    private var database: OpaquePointer?
    private var sleepObserver: NSObjectProtocol?
    private var wakeObserver: NSObjectProtocol?

    private init() {
        queue.sync {
            open()
            startSleepWatch()
        }
    }

    func samples(from start: Date, to end: Date) -> [HistorySample] {
        queue.sync {
            guard let database else { return [] }
            return readSamples(table: "sample", from: start, to: end, database: database)
        }
    }

    func minuteSamples(from start: Date, to end: Date) -> [HistorySample] {
        queue.sync {
            guard let database else { return [] }
            return readSamples(table: "minute", from: start, to: end, database: database)
        }
    }

    func events(from start: Date, to end: Date) -> [HistoryEvent] {
        queue.sync {
            guard let database else { return [] }
            return readEvents(from: start, to: end, database: database)
        }
    }

    func write(_ draft: HistoryDraft) {
        queue.sync {
            guard let database else { return }
            insertSample(draft.sample, database: database)
            insertTop(draft.top, at: draft.sample.at, database: database)
            insertEvents(draft.events, at: draft.sample.at, database: database)
            deleteSamples(before: draft.dropRawBefore, database: database)
        }
    }

    private func open() {
        let directory = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("com.qqzhangyanhua.pulse", isDirectory: true)
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
            guard let self, let database = self.database else { return }
            self.insertEvents(events, at: Date(), database: database)
        }
    }

    private func insertSample(_ sample: HistorySample, database: OpaquePointer) {
        let sql = """
        INSERT OR REPLACE INTO sample
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

    private func readSamples(
        table: String,
        from start: Date,
        to end: Date,
        database: OpaquePointer
    ) -> [HistorySample] {
        guard table == "sample" || table == "minute" else { return [] }
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
            rows.append(HistorySample(
                at: Date(timeIntervalSince1970: sqlite3_column_double(statement, 0)),
                usedBytes: optionalUInt(statement, 1),
                pressure: optionalPressure(statement, 2),
                swapUsedBytes: optionalUInt(statement, 3),
                cpuPercent: optionalDouble(statement, 4),
                networkInBytesPerSecond: optionalDouble(statement, 5),
                networkOutBytesPerSecond: optionalDouble(statement, 6),
                diskReadBytesPerSecond: optionalDouble(statement, 7),
                diskWriteBytesPerSecond: optionalDouble(statement, 8),
                gpuPercent: optionalDouble(statement, 9)
            ))
        }
        return rows
    }

    private func readEvents(from start: Date, to end: Date, database: OpaquePointer) -> [HistoryEvent] {
        let sql = "SELECT kind, detail FROM event WHERE at >= ? AND at <= ? ORDER BY id"
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            return []
        }
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_double(statement, 1, start.timeIntervalSince1970)
        sqlite3_bind_double(statement, 2, end.timeIntervalSince1970)
        var events: [HistoryEvent] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            guard let kind = optionalText(statement, 0) else { continue }
            let detail = optionalText(statement, 1)
            switch kind {
            case "pressure":
                if let detail { events.append(.pressure(detail)) }
            case "thermal":
                if let detail { events.append(.thermal(detail)) }
            case "sleep":
                events.append(.sleep)
            case "wake":
                events.append(.wake)
            default:
                break
            }
        }
        return events
    }

    private func optionalUInt(_ statement: OpaquePointer, _ index: Int32) -> UInt64? {
        guard sqlite3_column_type(statement, index) != SQLITE_NULL else { return nil }
        return UInt64(bitPattern: sqlite3_column_int64(statement, index))
    }

    private func optionalDouble(_ statement: OpaquePointer, _ index: Int32) -> Double? {
        guard sqlite3_column_type(statement, index) != SQLITE_NULL else { return nil }
        return sqlite3_column_double(statement, index)
    }

    private func optionalText(_ statement: OpaquePointer, _ index: Int32) -> String? {
        guard sqlite3_column_type(statement, index) != SQLITE_NULL else { return nil }
        guard let raw = sqlite3_column_text(statement, index) else { return nil }
        return String(cString: UnsafeRawPointer(raw).assumingMemoryBound(to: CChar.self))
    }

    private func optionalPressure(_ statement: OpaquePointer, _ index: Int32) -> PressureLevel? {
        guard let raw = optionalText(statement, index) else { return nil }
        return PressureLevel(rawValue: raw)
    }

    private func deleteSamples(before date: Date, database: OpaquePointer) {
        let sql = "DELETE FROM sample WHERE at < ?"
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK, let statement else { return }
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_double(statement, 1, date.timeIntervalSince1970)
        sqlite3_step(statement)
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
