import Foundation

/// One pmgr `voltage-states9` pair. Index 0 is OFF, not a working frequency.
struct VoltageState9: Equatable {
    var hertz: UInt32
    var millivolts: UInt32
}

enum VoltageStates9 {
    /// Little-endian Hz then mV, each a uint32. Empty or a truncated pair is nil.
    static func parse(_ bytes: Data) -> [VoltageState9]? {
        let pairBytes = 8
        guard !bytes.isEmpty, bytes.count.isMultiple(of: pairBytes) else { return nil }
        var entries: [VoltageState9] = []
        entries.reserveCapacity(bytes.count / pairBytes)
        var offset = 0
        while offset < bytes.count {
            entries.append(VoltageState9(
                hertz: uint32(bytes, offset),
                millivolts: uint32(bytes, offset + 4)
            ))
            offset += pairBytes
        }
        return entries
    }

    private static func uint32(_ bytes: Data, _ offset: Int) -> UInt32 {
        let b0 = UInt32(bytes[offset])
        let b1 = UInt32(bytes[offset + 1])
        let b2 = UInt32(bytes[offset + 2])
        let b3 = UInt32(bytes[offset + 3])
        return b0 | (b1 << 8) | (b2 << 16) | (b3 << 24)
    }
}
