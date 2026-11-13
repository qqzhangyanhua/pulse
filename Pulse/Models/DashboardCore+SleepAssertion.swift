import Foundation

extension DashboardCore {
    /// Replaces the card rows. A failed read never calls this, so the previous rows stay.
    mutating func apply(sleepAssertions rows: [SleepAssertionRow]) -> [DashboardEffect] {
        sleepAssertions = rows
        return []
    }

    /// A pid in the process table selects that row.
    /// A pid that is not in the table clears the selection.
    mutating func selectSleepAssertion(pid: Int32) -> [DashboardEffect] {
        if let accepted = ProcessSelection.acceptedPid(pid, in: rows) {
            return select(pid: accepted)
        }
        return select(pid: nil)
    }
}
