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
    /// Reuses `pauseMenuOffer`, so system paths stay on `ProcessQuitRoute` with `hasApplication: false`.
    func priorityMenuOffer(selfUid: UInt32) -> PriorityMenuOffer? {
        guard pauseMenuOffer(selfUid: selfUid) != nil, let row = selectedRow else { return nil }
        return loweredPriorityPids.contains(row.pid) ? .restore : .lower
    }

    func isLoweredPriority(pid: Int32) -> Bool {
        loweredPriorityPids.contains(pid)
    }

    mutating func lowerSelectedPriority(selfUid: UInt32) -> [DashboardEffect] {
        guard priorityMenuOffer(selfUid: selfUid) == .lower, let row = selectedRow else { return [] }
        loweredPriorityPids.insert(row.pid)
        return [.lowerPriority(pid: row.pid)]
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
