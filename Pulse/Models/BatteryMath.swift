import Foundation

/// Battery health and power. Inputs are already read; this type does not sample.
enum BatteryMath {
    /// Full-charge capacity / design capacity. Nil when either input is missing or design is not positive.
    /// A design of 0 is unread, not an empty battery. A full-charge of 0 is a real ratio of 0.
    static func healthPercent(fullChargeCapacity: Int?, designCapacity: Int?) -> Double? {
        guard let fullChargeCapacity, let designCapacity, designCapacity > 0 else { return nil }
        return Double(fullChargeCapacity) / Double(designCapacity)
    }

    /// Millivolts × milliamps / 1e6. The sign of the current is kept, so discharge stays negative.
    static func powerWatts(millivolts: Int?, milliamps: Int?) -> Double? {
        guard let millivolts, let milliamps else { return nil }
        return Double(millivolts) * Double(milliamps) / 1_000_000
    }

    /// AppleSmartBattery stores a negative current as a 64-bit two's-complement bit pattern.
    static func signedMilliamps(_ raw: UInt64) -> Int {
        Int(Int64(bitPattern: raw))
    }

    /// Positive registry keys. A high bit is missing, not a negative current.
    static func plainInteger(uint64 raw: UInt64) -> Int? {
        guard raw <= UInt64(Int.max) else { return nil }
        return Int(raw)
    }
}
