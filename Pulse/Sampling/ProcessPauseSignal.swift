import Darwin
import Foundation

/// SIGSTOP / SIGCONT for one process, plus the launch and terminate ledger.
enum ProcessPause {
    static var uid: UInt32 { UInt32(getuid()) }

    static func stop(_ pid: Int32) {
        _ = kill(pid, SIGSTOP)
    }

    static func resume(_ pid: Int32) {
        _ = kill(pid, SIGCONT)
    }

    static func store(_ ledger: PausedProcessLedger) {
        PausedProcessStore.save(ledger)
    }

    /// Continue records whose start time still matches. Drop the rest, including a reused pid.
    static func reconcileStored() -> PausedProcessLedger {
        var ledger = PausedProcessStore.load()
        let live = liveIdentities(for: ledger.records)
        let outcome = ledger.reconcile(live: live)
        for record in outcome.resume {
            resume(record.pid)
        }
        PausedProcessStore.save(ledger)
        return ledger
    }

    /// Continue every recorded process, then clear the stored key.
    static func resumeAll(_ ledger: PausedProcessLedger) {
        for record in ledger.records {
            resume(record.pid)
        }
        var finished = ledger
        finished.clear()
        PausedProcessStore.save(finished)
    }

    private static func liveIdentities(for records: [PausedProcessRecord]) -> [PausedProcessRecord] {
        records.compactMap { record in
            guard let start = ProcessEnumerator.startTimeSeconds(pid: record.pid) else { return nil }
            return PausedProcessRecord(pid: record.pid, startTimeSeconds: start)
        }
    }
}
