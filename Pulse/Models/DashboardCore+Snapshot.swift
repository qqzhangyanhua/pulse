import Foundation

extension DashboardCore {
    /// The published host frame, frozen at `savedAt`. Nil when that snapshot is missing.
    /// Does not read a clock, sample, or open a file.
    func frozenSnapshot(savedAt: Date) -> SnapshotExport? {
        SnapshotExport.freeze(
            snapshot: snapshot,
            rows: rows,
            systemCpuPercent: systemCpuPercent,
            busiestCorePercent: busiestCorePercent,
            hostNetworkRates: hostNetworkRates,
            hostDiskRates: hostDiskRates,
            samplingFailed: samplingFailed,
            processListFailed: processListFailed,
            savedAt: savedAt
        )
    }
}
