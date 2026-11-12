import Darwin
import Foundation
import IOKit

/// Registry properties for published accelerator performance statistics.
/// Only `MemorySampler.sample()` calls this. No user client and no Metal counters.
enum HostGPUReader {
    private static let acceleratorClass = "IOAccelerator"
    private static let statisticsKey = "PerformanceStatistics"

    static func read() -> [GPUAcceleratorNode] {
        guard let matching = IOServiceMatching(acceleratorClass) else { return [] }
        var iterator: io_iterator_t = 0
        let status = IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator)
        guard status == KERN_SUCCESS else { return [] }
        defer { IOObjectRelease(iterator) }

        var nodes: [GPUAcceleratorNode] = []
        while true {
            let service = IOIteratorNext(iterator)
            if service == 0 { break }
            defer { IOObjectRelease(service) }
            if let node = node(for: service) {
                nodes.append(node)
            }
        }
        return nodes
    }

    private static func node(for service: io_registry_entry_t) -> GPUAcceleratorNode? {
        var unmanaged: Unmanaged<CFMutableDictionary>?
        let status = IORegistryEntryCreateCFProperties(service, &unmanaged, kCFAllocatorDefault, 0)
        guard status == KERN_SUCCESS, let properties = unmanaged?.takeRetainedValue() as NSDictionary? else {
            return nil
        }
        guard let stats = properties[statisticsKey] as? NSDictionary else { return nil }
        var statistics: [String: GPUStatistic] = [:]
        for key in stats.allKeys {
            guard let name = key as? String else { continue }
            statistics[name] = statistic(name: name, value: stats[key] as Any)
        }
        return GPUAcceleratorNode(statistics: statistics)
    }

    private static func statistic(name: String, value: Any) -> GPUStatistic {
        guard let number = value as? NSNumber, !isBoolean(number) else { return .unreadable }
        if name == GPUPageProjection.inUseSystemMemoryKey {
            return memoryBytes(number)
        }
        return .number(number.doubleValue)
    }

    private static func isBoolean(_ number: NSNumber) -> Bool {
        CFGetTypeID(number) == CFBooleanGetTypeID()
    }

    /// Fractional or negative values are present, but they are not a byte count.
    private static func memoryBytes(_ number: NSNumber) -> GPUStatistic {
        let value = number.doubleValue
        guard value.isFinite, value >= 0, value <= Double(UInt64.max), value == value.rounded() else {
            return .unreadable
        }
        return .bytes(UInt64(value))
    }
}
