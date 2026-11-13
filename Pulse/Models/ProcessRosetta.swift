import Foundation

enum ProcessRosettaDecoder {
    /// `P_TRANSLATED` in `<sys/proc.h>`.
    private static let translatedBit: UInt32 = 0x00020000

    /// Nil when the process is native, or when the flag was not read.
    static func line(processFlags: UInt32?) -> String? {
        guard let processFlags, processFlags & translatedBit != 0 else { return nil }
        return "通过 Rosetta 运行"
    }
}
