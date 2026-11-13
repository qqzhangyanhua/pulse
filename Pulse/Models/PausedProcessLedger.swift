import Foundation

/// One paused process. Pid alone is not identity: start time catches reuse.
struct PausedProcessRecord: Equatable, Sendable {
    var pid: Int32
    var startTimeSeconds: UInt64
}

/// Launch check. `resume` is safe to continue. `discarded` must not be signaled.
struct PausedProcessReconciliation: Equatable, Sendable {
    var resume: [PausedProcessRecord]
    var discarded: [PausedProcessRecord]
}

/// In-memory pause records. Persistence is a separate adapter.
struct PausedProcessLedger: Equatable, Sendable {
    private(set) var records: [PausedProcessRecord] = []

    mutating func record(pid: Int32, startTimeSeconds: UInt64) {
        let next = PausedProcessRecord(pid: pid, startTimeSeconds: startTimeSeconds)
        if let index = records.firstIndex(where: { $0.pid == pid }) {
            records[index] = next
        } else {
            records.append(next)
        }
    }

    /// Manual 继续. Drops that pid and leaves every other record.
    mutating func resume(pid: Int32) {
        records.removeAll { $0.pid == pid }
    }

    mutating func clear() {
        records.removeAll()
    }

    func contains(pid: Int32, startTimeSeconds: UInt64) -> Bool {
        records.contains { $0.pid == pid && $0.startTimeSeconds == startTimeSeconds }
    }

    func contains(pid: Int32) -> Bool {
        records.contains { $0.pid == pid }
    }

    /// Same start time resumes. A different start time, or a pid that is not in `live`, is discarded.
    mutating func reconcile(live: [PausedProcessRecord]) -> PausedProcessReconciliation {
        var resume: [PausedProcessRecord] = []
        var discarded: [PausedProcessRecord] = []
        for record in records {
            guard let observed = live.first(where: { $0.pid == record.pid }) else {
                discarded.append(record)
                continue
            }
            if observed.startTimeSeconds == record.startTimeSeconds {
                resume.append(record)
            } else {
                discarded.append(record)
            }
        }
        records.removeAll()
        return PausedProcessReconciliation(resume: resume, discarded: discarded)
    }
}
