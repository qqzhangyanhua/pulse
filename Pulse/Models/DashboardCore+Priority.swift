import Foundation

/// 「更多」 item beside pause. Same visible row, or the menu stays hidden.
enum PriorityMenuOffer: Equatable, Sendable {
    case lower
    case restore

    var title: String {
        switch self {
        case .lower:
            return "降低优先级"
        case .restore:
            return "恢复优先级"
        }
    }
}

extension DashboardCore {
    /// Same path, user, and group check as pause. A missing start time can still lower.
    func priorityMenuOffer(selfUid: UInt32) -> PriorityMenuOffer? {
        guard let row = selectedRow, canControlProcess(row, selfUid: selfUid) else { return nil }
        return loweredPriorityPids.contains(row.pid) ? .restore : .lower
    }

    func isLoweredPriority(pid: Int32) -> Bool {
        loweredPriorityPids.contains(pid)
    }

    /// Does not mark. The mark is `finishLowerPriority` after `setpriority` returns 0.
    mutating func lowerSelectedPriority(selfUid: UInt32) -> [DashboardEffect] {
        guard priorityMenuOffer(selfUid: selfUid) == .lower, let row = selectedRow else { return [] }
        return [.lowerPriority(pid: row.pid)]
    }

    /// A failed lower does not mark. A successful lower does.
    mutating func finishLowerPriority(pid: Int32, succeeded: Bool) {
        guard succeeded else { return }
        loweredPriorityPids.insert(pid)
    }

    mutating func restoreLoweredPriority(pid: Int32) -> [DashboardEffect] {
        guard loweredPriorityPids.contains(pid) else { return [] }
        loweredPriorityPids.remove(pid)
        return [.restorePriority(pid: pid)]
    }

    /// Normal quit restores every pid this session lowered, then forgets them.
    mutating func restoreLoweredPrioritiesForQuit() -> [DashboardEffect] {
        let pids = loweredPriorityPids.sorted()
        loweredPriorityPids.removeAll()
        return pids.map { .restorePriority(pid: $0) }
    }
}
