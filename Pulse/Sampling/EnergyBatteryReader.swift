import Foundation
import IOKit
import IOKit.ps

/// One battery read for the energy page. Not called from `MemorySampler` or the machine page.
enum EnergyBatteryReader {
    static func read() -> EnergyBatteryReading {
        guard let snapshot = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let battery = internalBattery(in: snapshot) else {
            return .absent
        }
        return EnergyBatteryReading(
            hasInternalBattery: true,
            percent: percent(current: battery.current, maximum: battery.maximum),
            supply: supply(providing: providingType(snapshot), batteryState: battery.state),
            charging: battery.charging,
            lowPowerMode: ProcessInfo.processInfo.isLowPowerModeEnabled,
            remainingSeconds: remainingSeconds(),
            minutesToFull: battery.minutesToFull
        )
    }

    private static func providingType(_ snapshot: CFTypeRef) -> String? {
        guard let unmanaged = IOPSGetProvidingPowerSourceType(snapshot) else { return nil }
        return unmanaged.takeUnretainedValue() as String
    }

    /// The first internal battery. A UPS entry is not one, so a desktop stays absent.
    private static func internalBattery(in snapshot: CFTypeRef) -> EnergyBatterySourceReading? {
        guard let list = IOPSCopyPowerSourcesList(snapshot)?.takeRetainedValue() as? [CFTypeRef] else {
            return nil
        }
        for item in list {
            guard let description = IOPSGetPowerSourceDescription(snapshot, item)?.takeUnretainedValue() as NSDictionary? else {
                continue
            }
            let type = description[kIOPSTypeKey] as? String
            guard type == (kIOPSInternalBatteryType as String) else { continue }
            return EnergyBatterySourceReading(
                state: description[kIOPSPowerSourceStateKey] as? String,
                current: (description[kIOPSCurrentCapacityKey] as? NSNumber)?.intValue,
                maximum: (description[kIOPSMaxCapacityKey] as? NSNumber)?.intValue,
                charging: flag(description[kIOPSIsChargingKey]),
                minutesToFull: (description[kIOPSTimeToFullChargeKey] as? NSNumber)?.intValue
            )
        }
        return nil
    }

    /// Battery, or external power. UPS power while an internal battery exists is external, not a third label.
    private static func supply(providing: String?, batteryState: String?) -> EnergyBatterySupply? {
        let battery = kIOPSBatteryPowerValue as String
        let adapter = kIOPSACPowerValue as String
        let ups = kIOPMUPSPowerKey as String
        if providing == battery { return .battery }
        if providing == adapter || providing == ups { return .adapter }
        if batteryState == battery { return .battery }
        if batteryState == adapter { return .adapter }
        return nil
    }

    /// Header result is seconds. -1 is unknown and -2 is unlimited.
    private static func remainingSeconds() -> Int? {
        let estimate = IOPSGetTimeRemainingEstimate()
        if estimate == kIOPSTimeRemainingUnknown { return -1 }
        if estimate == kIOPSTimeRemainingUnlimited { return -2 }
        guard estimate.isFinite, estimate >= 0, estimate <= Double(Int.max) else { return nil }
        return Int(estimate)
    }

    private static func flag(_ value: Any?) -> Bool {
        if let number = value as? NSNumber { return number.boolValue }
        if let flag = value as? Bool { return flag }
        return false
    }

    /// `maximum == 0` is unread. A real empty battery is `current == 0` with `maximum > 0`.
    private static func percent(current: Int?, maximum: Int?) -> Int? {
        guard let current, let maximum, maximum > 0, current >= 0 else { return nil }
        let value = Int((Double(current) / Double(maximum) * 100).rounded())
        return min(max(value, 0), 100)
    }
}

private struct EnergyBatterySourceReading {
    var state: String?
    var current: Int?
    var maximum: Int?
    var charging: Bool
    var minutesToFull: Int?
}
