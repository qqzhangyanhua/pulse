import Foundation

extension DashboardCore {
    /// Replaces the machine-page list. An unreadable directory is already a 「—」 row.
    mutating func apply(launchItems rows: [LaunchItemRow]) -> [DashboardEffect] {
        launchItems = rows
        return []
    }
}
