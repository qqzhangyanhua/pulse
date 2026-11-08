import Foundation

/// This frame's note for task-info reads the user cannot see. Not a process row.
enum ProcessPermissionFootnote {
    /// POSIX EPERM. ESRCH is 3 and does not count. No Darwin import.
    static func countsTaskInfoFailure(errno: Int32) -> Bool {
        errno == 1
    }

    /// One walk. Callers pass that frame's task-info errnos, not a running total.
    static func deniedCount(taskInfoErrnos: [Int32]) -> Int {
        var count = 0
        for errno in taskInfoErrnos where countsTaskInfoFailure(errno: errno) {
            count += 1
        }
        return count
    }

    /// N > 0 only. Zero and negative counts say nothing, including not 「0」.
    static func sentence(deniedCount: Int) -> String? {
        guard deniedCount > 0 else { return nil }
        return "另有 \(deniedCount) 个系统进程没有读取权限"
    }

    /// Empty when this frame's process list failed. Does not publish 0.
    static func published(deniedCount: Int, processListFailed: Bool) -> String? {
        guard !processListFailed else { return nil }
        return sentence(deniedCount: deniedCount)
    }

    /// The table draws this only while the list is showing and the frame did not fail.
    static func visibleSentence(
        _ sentence: String?,
        processListFailed: Bool,
        showsProcessTable: Bool
    ) -> String? {
        guard showsProcessTable, !processListFailed else { return nil }
        guard let sentence, !sentence.isEmpty, sentence != "0" else { return nil }
        return sentence
    }
}
