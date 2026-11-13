import Foundation

/// Lifetime max footprint for the memory detail. Same byte text as 内存占用.
enum MemoryPeakText {
    static let title = "内存占用峰值"

    /// Own-user reading, including a real 0. Anyone else, or a failed read, is 「—」.
    static func string(bytes: UInt64?, rowUid: UInt32?, selfUid: UInt32) -> String {
        guard isOwnUser(rowUid: rowUid, selfUid: selfUid), let bytes else { return "—" }
        return ByteFormat.memory(bytes)
    }
}
