import Darwin

/// Nice of another process. `PRIO_DARWIN_PROCESS` only accepts `who` 0, so it cannot lower a pid.
/// The saved nice is in memory only. It dies with the process, and a crash does not repair it.
enum ProcessPriority {
    private static var savedNice: [Int32: Int32] = [:]

    /// 10 when the current nice is below 10. Already ≥ 10 still calls `setpriority` with that nice.
    /// Success is only a 0 return. A failed read or set does not save the pid.
    static func lower(_ pid: Int32) -> Bool {
        errno = 0
        let current = getpriority(PRIO_PROCESS, id_t(pid))
        if current == -1 && errno != 0 { return false }
        let nice: Int32 = current < 10 ? 10 : current
        guard setpriority(PRIO_PROCESS, id_t(pid), nice) == 0 else { return false }
        savedNice[pid] = current
        return true
    }

    /// Puts back the nice saved by a successful lower. No saved nice is a no-op.
    static func restore(_ pid: Int32) {
        guard let nice = savedNice.removeValue(forKey: pid) else { return }
        _ = setpriority(PRIO_PROCESS, id_t(pid), nice)
    }
}
