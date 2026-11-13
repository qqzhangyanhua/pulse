import Foundation

/// Identity fields from one `proc_bsdinfo` buffer. Little-endian, 136 bytes.
struct ProcessBSDIdentity: Equatable, Sendable {
    var parentPid: Int32
    var userID: UInt32
    var startTimeSeconds: UInt64
}

enum ProcessBSDInfo {
    static let byteCount = 136
    /// Byte offset of the parent pid (`UInt32`).
    static let parentPidOffset = 16
    /// Byte offset of the uid (`UInt32`).
    static let userIDOffset = 20
    /// Byte offset of the start time in seconds since 1970 (`UInt64`).
    static let startTimeOffset = 120

    static func identity(from bytes: [UInt8]) -> ProcessBSDIdentity? {
        guard bytes.count == byteCount else { return nil }
        let parent = bytes.withUnsafeBytes { raw in
            raw.loadUnaligned(fromByteOffset: parentPidOffset, as: UInt32.self)
        }
        let userID = bytes.withUnsafeBytes { raw in
            raw.loadUnaligned(fromByteOffset: userIDOffset, as: UInt32.self)
        }
        let start = bytes.withUnsafeBytes { raw in
            raw.loadUnaligned(fromByteOffset: startTimeOffset, as: UInt64.self)
        }
        return ProcessBSDIdentity(
            parentPid: Int32(bitPattern: parent),
            userID: userID,
            startTimeSeconds: start
        )
    }
}
