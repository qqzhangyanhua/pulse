import Foundation
import IOKit
import IOKit.ps

/// One host read for the machine page. Not called from `MemorySampler`.
enum HostMachineReader {
    static func read() -> MachineFacts {
        let info = ProcessInfo.processInfo
        let version = info.operatingSystemVersion
        let uptime = info.systemUptime
        let elapsed = uptime >= 0 ? uptime : 0
        let memory = info.physicalMemory
        return MachineFacts(
            chipName: MachineInfo.chipName(),
            modelName: MachineInfo.hardwareModel(),
            coreCount: MachineInfo.processorCount,
            physicalMemoryBytes: memory > 0 ? memory : nil,
            os: MachineOSVersion(
                major: version.majorVersion,
                minor: version.minorVersion,
                patch: version.patchVersion
            ),
            uptime: uptime,
            bootedAt: Date().addingTimeInterval(-elapsed),
            power: power(lowPowerMode: info.isLowPowerModeEnabled),
            battery: internalBatteryDetails(),
            volume: volume()
        )
    }

    private static func power(lowPowerMode: Bool) -> MachinePower {
        guard let snapshot = IOPSCopyPowerSourcesInfo()?.takeRetainedValue() else {
            return MachinePower(source: .unknown, batteryPercent: nil, lowPowerMode: lowPowerMode)
        }
        let battery = internalBattery(in: snapshot)
        let source = source(providing: providingType(snapshot), batteryState: battery?.state)
        let percent = source == .unknown ? nil : battery?.percent
        return MachinePower(source: source, batteryPercent: percent, lowPowerMode: lowPowerMode)
    }

    private static func providingType(_ snapshot: CFTypeRef) -> String? {
        guard let unmanaged = IOPSGetProvidingPowerSourceType(snapshot) else { return nil }
        return unmanaged.takeUnretainedValue() as String
    }

    private static func internalBattery(in snapshot: CFTypeRef) -> BatteryReading? {
        guard let list = IOPSCopyPowerSourcesList(snapshot)?.takeRetainedValue() as? [CFTypeRef] else {
            return nil
        }
        for item in list {
            guard let description = IOPSGetPowerSourceDescription(snapshot, item)?.takeUnretainedValue() as NSDictionary? else {
                continue
            }
            let type = description[kIOPSTypeKey] as? String
            guard type == (kIOPSInternalBatteryType as String) else { continue }
            let state = description[kIOPSPowerSourceStateKey] as? String
            let current = (description[kIOPSCurrentCapacityKey] as? NSNumber)?.intValue
            let max = (description[kIOPSMaxCapacityKey] as? NSNumber)?.intValue
            return BatteryReading(state: state, percent: percent(current: current, maximum: max))
        }
        return nil
    }

    private static func source(providing: String?, batteryState: String?) -> MachinePowerSource {
        let battery = kIOPSBatteryPowerValue as String
        let adapter = kIOPSACPowerValue as String
        let ups = kIOPMUPSPowerKey as String
        if providing == battery { return .battery }
        if providing == adapter || providing == ups { return .adapter }
        if batteryState == battery { return .battery }
        if batteryState == adapter { return .adapter }
        return .unknown
    }

    /// Nil when this Mac has no `AppleSmartBattery`. Missing keys stay nil on a present battery.
    private static func internalBatteryDetails() -> MachineBattery? {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"))
        guard service != 0 else { return nil }
        defer { IOObjectRelease(service) }
        guard let properties = copyProperties(service) else { return blankBattery }
        let data = properties["BatteryData"] as? NSDictionary
        return MachineBattery(
            cycleCount: integer(properties["CycleCount"]),
            fullChargeCapacity: fullChargeCapacity(properties, data),
            designCapacity: integer(properties["DesignCapacity"]) ?? integer(data?["DesignCapacity"]),
            millivolts: integer(properties["Voltage"]),
            milliamps: milliamps(properties["InstantAmperage"]) ?? milliamps(properties["Amperage"])
        )
    }

    /// `AppleRawMaxCapacity` is mAh. Top-level MaxCapacity is a percent on Apple Silicon, so it is not read.
    private static func fullChargeCapacity(_ properties: NSDictionary, _ data: NSDictionary?) -> Int? {
        integer(properties["AppleRawMaxCapacity"])
            ?? integer(data?["AppleRawMaxCapacity"])
            ?? integer(data?["FullChargeCapacity"])
    }

    private static func copyProperties(_ service: io_registry_entry_t) -> NSDictionary? {
        var properties: Unmanaged<CFMutableDictionary>?
        let status = IORegistryEntryCreateCFProperties(service, &properties, kCFAllocatorDefault, 0)
        guard status == KERN_SUCCESS, let raw = properties?.takeRetainedValue() else { return nil }
        return raw
    }

    /// Positive keys. A current that may be a two's-complement bit pattern uses `milliamps`.
    private static func integer(_ value: Any?) -> Int? {
        guard let number = value as? NSNumber else { return nil }
        return BatteryMath.plainInteger(uint64: number.uint64Value)
    }

    /// `InstantAmperage` may be a 64-bit two's-complement bit pattern. A real 0 stays 0.
    private static func milliamps(_ value: Any?) -> Int? {
        guard let number = value as? NSNumber else { return nil }
        return BatteryMath.signedMilliamps(number.uint64Value)
    }

    private static let blankBattery = MachineBattery(
        cycleCount: nil,
        fullChargeCapacity: nil,
        designCapacity: nil,
        millivolts: nil,
        milliamps: nil
    )

    /// `maximum == 0` is unread. A real empty battery is `current == 0` with `maximum > 0`.
    private static func percent(current: Int?, maximum: Int?) -> Int? {
        guard let current, let maximum, maximum > 0, current >= 0 else { return nil }
        let value = Int((Double(current) / Double(maximum) * 100).rounded())
        return min(max(value, 0), 100)
    }

    private static func volume() -> MachineVolume {
        let url = URL(fileURLWithPath: "/")
        guard let values = try? url.resourceValues(forKeys: [
            .volumeTotalCapacityKey,
            .volumeAvailableCapacityForImportantUsageKey,
        ]) else {
            return MachineVolume(availableBytes: nil, totalBytes: nil)
        }
        return MachineVolume(
            availableBytes: nonNegative(values.volumeAvailableCapacityForImportantUsage),
            totalBytes: positive(values.volumeTotalCapacity)
        )
    }

    private static func nonNegative(_ value: Int64?) -> UInt64? {
        guard let value, value >= 0 else { return nil }
        return UInt64(value)
    }

    private static func positive(_ value: Int?) -> UInt64? {
        guard let value, value > 0 else { return nil }
        return UInt64(value)
    }
}

private struct BatteryReading {
    var state: String?
    var percent: Int?
}
