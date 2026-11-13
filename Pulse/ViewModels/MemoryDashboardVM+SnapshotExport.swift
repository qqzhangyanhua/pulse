import Foundation

extension MemoryDashboardVM {
    /// Copies the published frame, then freezes it. No await and no new sample.
    /// Returns the refusal sentence when there is no published host snapshot.
    func requestSaveCurrentSnapshot(
        savedAt: Date,
        calendar: Calendar,
        timeZone: TimeZone
    ) -> String? {
        if snapshotExportStore.session != nil {
            return nil
        }
        guard let frozen = core.frozenSnapshot(savedAt: savedAt) else {
            return SnapshotExportCopy.noSampleMessage
        }
        snapshotExportStore.present(
            SnapshotExportSession(
                frozen: frozen,
                calendar: calendar,
                timeZone: timeZone
            )
        )
        return nil
    }

    func cancelSnapshotExportPreview() {
        snapshotExportStore.dismiss()
    }

    func setSnapshotExportHidesNames(_ hide: Bool) {
        snapshotExportStore.setHideNames(hide)
    }

    func noteSnapshotExportCancelledPanel() {
        snapshotExportStore.cancelSavePanel()
    }

    func noteSnapshotExportWriteFailed() {
        snapshotExportStore.noteWriteFailed()
    }

    func noteSnapshotExportWriteSucceeded() {
        snapshotExportStore.noteWriteSucceeded()
    }
}
