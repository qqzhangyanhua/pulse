import Foundation
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
