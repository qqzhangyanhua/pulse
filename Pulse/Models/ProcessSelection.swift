import Foundation

/// Select-if-present against the live process table.
///
/// `focusMemoryPage()` stays a separate, selection-free path. Callers write
/// `selectedPid` only through `acceptedPid` / `applying` so a vanished pid
/// never becomes a ghost selection. The scroll target is the same present-pid
/// identity; list UI wiring is a later step.
enum ProcessSelection {
    /// `pid` only when it still appears in `rows`. Missing / vanished pids
    /// return nil so callers do not write that pid.
    static func acceptedPid(_ pid: Int32, in rows: [ProcessRow]) -> Int32? {
        rows.contains(where: { $0.pid == pid }) ? pid : nil
    }

    /// Next `selectedPid` after a select-if-present request.
    /// Present → that pid. Missing → keep `current` (do not write the missing pid).
    static func applying(pid: Int32, to current: Int32?, in rows: [ProcessRow]) -> Int32? {
        acceptedPid(pid, in: rows) ?? current
    }

    /// Process-list identity to reveal. A vanished or empty selection is not a target.
    static func scrollTarget(selectedPid: Int32?, rows: [ProcessRow]) -> Int32? {
        guard let selectedPid else { return nil }
        return acceptedPid(selectedPid, in: rows)
    }
}
