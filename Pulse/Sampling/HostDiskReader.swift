import Darwin
import Foundation
import IOKit

/// One cheap IOKit `IOBlockStorageDriver` Statistics read.
/// Only `MemorySampler.sample()` calls this. No entitlement, no user client, no `IOServiceOpen`.
enum HostDiskReader {
    private static let driverClass = "IOBlockStorageDriver"
    private static let statisticsKey = "Statistics"
    private static let bytesReadKey = "Bytes (Read)"
    private static let bytesWrittenKey = "Bytes (Write)"

    static func read(at date: Date) -> HostDiskSnapshot? {
        guard let matching = IOServiceMatching(driverClass) else { return nil }
        var iterator: io_iterator_t = 0
        let status = IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator)
        guard status == KERN_SUCCESS else { return nil }
        defer { IOObjectRelease(iterator) }

        var drivers: [String: HostDiskDriverCounters] = [:]
        while true {
            let service = IOIteratorNext(iterator)
            if service == 0 { break }
            defer { IOObjectRelease(service) }
            guard let driver = counters(for: service) else { continue }
            drivers[driver.id] = driver
        }
        return HostDiskSnapshot(drivers: drivers, capturedAt: date)
    }

    private static func counters(for service: io_registry_entry_t) -> HostDiskDriverCounters? {
        var unmanaged: Unmanaged<CFMutableDictionary>?
        let status = IORegistryEntryCreateCFProperties(service, &unmanaged, kCFAllocatorDefault, 0)
        guard status == KERN_SUCCESS, let properties = unmanaged?.takeRetainedValue() as NSDictionary? else {
            return nil
        }
        guard let stats = properties[statisticsKey] as? NSDictionary else { return nil }
        guard let bytesRead = stats[bytesReadKey] as? NSNumber,
              let bytesWritten = stats[bytesWrittenKey] as? NSNumber
        else {
            return nil
        }
        guard let id = driverID(service: service) else { return nil }
        return HostDiskDriverCounters(
            id: id,
            bytesRead: bytesRead.uint64Value,
            bytesWritten: bytesWritten.uint64Value
        )
    }

    private static func driverID(service: io_registry_entry_t) -> String? {
        var entryID: UInt64 = 0
        guard IORegistryEntryGetRegistryEntryID(service, &entryID) == KERN_SUCCESS else { return nil }
        return String(entryID)
    }
}
