import Darwin

/// Task policy on the live process. The kernel drops it when that process exits.
/// `which` is `PRIO_DARWIN_PROCESS`. `PRIO_DARWIN_BG` as `which` returns EINVAL.
enum ProcessPriority {
    static func lower(_ pid: Int32) {
        _ = setpriority(PRIO_DARWIN_PROCESS, id_t(pid), PRIO_DARWIN_BG)
    }

    static func restore(_ pid: Int32) {
        _ = setpriority(PRIO_DARWIN_PROCESS, id_t(pid), 0)
    }
}
