import Foundation

/// One `kern.memorystatus_vm_pressure_level` read. Status is checked before `value` is mapped.
struct KernelPressureSample: Equatable, Sendable {
    var status: Int32
    var value: Int32
}

/// Kernel pressure values, then the existing ratio fallback. UI still binds only `normal | elevated`.
enum KernelPressure {
    /// 1 is normal. 2 (warning) and 4 (critical) are elevated. Anything else is unknown.
    static func level(from kernelValue: Int32) -> PressureLevel? {
        switch kernelValue {
        case 1:
            return .normal
        case 2, 4:
            return .elevated
        default:
            return nil
        }
    }

    /// Mapped level wins. A failed read or an unknown value keeps the previous ratio thresholds.
    static func resolve(
        reading: KernelPressureSample?,
        usedRatio: Double,
        compressedRatio: Double
    ) -> PressureLevel {
        if let reading, reading.status == 0, let level = level(from: reading.value) {
            return level
        }
        if usedRatio >= 0.88 || compressedRatio >= 0.18 {
            return .elevated
        }
        return .normal
    }
}
