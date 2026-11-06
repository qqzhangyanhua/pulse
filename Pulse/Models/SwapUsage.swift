import Foundation

/// One `vm.swapusage` result. Status and size are checked before `usedBytes` is trusted.
struct SwapUsageSample: Equatable, Sendable {
    var status: Int32
    var returnedSize: Int
    var expectedSize: Int
    var usedBytes: UInt64
}

/// Swap display and the rule that a failed read stays nil. Zero is a real sample.
enum SwapUsage {
    static let missingValue = "—"
    static let missingCaption = "未采样"
    static let usedCaption = "已用"

    struct Display: Equatable, Sendable {
        var value: String
        var caption: String
    }

    /// Nil unless the call succeeded and the returned struct is the size we asked for.
    static func usedBytes(from sample: SwapUsageSample) -> UInt64? {
        guard sample.status == 0, sample.expectedSize > 0, sample.returnedSize == sample.expectedSize else {
            return nil
        }
        return sample.usedBytes
    }

    static func display(usedBytes: UInt64?) -> Display {
        guard let usedBytes else {
            return Display(value: missingValue, caption: missingCaption)
        }
        return Display(value: ByteFormat.memory(usedBytes), caption: usedCaption)
    }
}
