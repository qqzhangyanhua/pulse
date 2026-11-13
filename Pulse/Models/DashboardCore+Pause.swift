import Foundation

/// 「更多」 menu beside quit. Grouped rows and ineligible processes stay hidden.
enum PauseMenuOffer: Equatable, Sendable {
    case pause
    case resume

    var title: String {
        switch self {
        case .pause:
            return "暂停"
        case .resume:
            return "继续"
        }
    }
}

extension DashboardCore {
    mutating func installPausedLedger(_ ledger: PausedProcessLedger) {
        pausedLedger = ledger
    }

    /// Visible row, not `detail.row`. A grouped row has no pause item.
    func pauseMenuOffer(selfUid: UInt32) -> PauseMenuOffer? {
        guard let row = selectedRow, row.groupedMemberCount == nil else { return nil }
        if isPaused(pid: row.pid) { return .resume }
        guard canPause(row, selfUid: selfUid) else { return nil }
        return .pause
    }

    /// True only when this pid's current start time is the recorded one.
    /// A missing start time on a still-listed pid keeps the mark. A reused pid does not.
    func isPaused(pid: Int32) -> Bool {
        guard let record = pausedLedger.records.first(where: { $0.pid == pid }) else { return false }
        guard let row = rows.first(where: { $0.pid == pid }) else { return false }
        guard let start = row.startTimeSeconds else { return true }
        return start == record.startTimeSeconds
    }

    mutating func pauseSelected(selfUid: UInt32) -> [DashboardEffect] {
        guard pauseMenuOffer(selfUid: selfUid) == .pause,
              let row = selectedRow,
              let start = row.startTimeSeconds
        else { return [] }
        pausedLedger.record(pid: row.pid, startTimeSeconds: start)
        return [.pauseProcess(pid: row.pid)]
    }

    mutating func resumePaused(pid: Int32) -> [DashboardEffect] {
        guard pausedLedger.contains(pid: pid) else { return [] }
        pausedLedger.resume(pid: pid)
        return [.resumeProcess(pid: pid)]
    }

    func resumeBeforeQuitPrompt() -> DashboardEffect? {
        guard let row = selectedRow, isPaused(pid: row.pid) else { return nil }
        return .confirmResumeBeforeQuit(pid: row.pid, displayName: row.name)
    }

    /// Cancel leaves the process paused. Confirm continues it, then issues the ordinary quit.
    mutating func resolveResumeBeforeQuit(pid: Int32, confirmed: Bool) -> [DashboardEffect] {
        guard confirmed, selectedPid == pid, pausedLedger.contains(pid: pid) else { return [] }
        pausedLedger.resume(pid: pid)
        return [.resumeProcess(pid: pid)] + quitSelected()
    }

    /// `hasApplication` stays false so a system path is not offered just because it is an app.
    private func canPause(_ row: ProcessRow, selfUid: UInt32) -> Bool {
        guard row.groupedMemberCount == nil else { return false }
        guard isOwnUser(rowUid: row.userID, selfUid: selfUid) else { return false }
        guard row.startTimeSeconds != nil else { return false }
        guard case .signal = ProcessQuitRoute.decide(
            hasApplication: false,
            executablePath: row.executablePath,
            force: false
        ) else { return false }
        return true
    }
}
