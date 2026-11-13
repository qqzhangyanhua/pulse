import Darwin
import Foundation
import IOKit

/// Read-only `AGXDeviceUserClient` properties for per-process GPU time.
/// Children of `IOAccelerator`, not a separate user client. No `IOServiceOpen`.
/// Only `MemorySampler.sample()` calls `read()`.
enum HostGPUShareReader {
    private static let acceleratorClass = "IOAccelerator"
    private static let clientClass = "AGXDeviceUserClient"

    /// Empty is a successful read with no AGX client, including an Intel Mac.
    static func read() -> [GPUShareClientSample] {
        guard let matching = IOServiceMatching(acceleratorClass) else { return [] }
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator) == KERN_SUCCESS else {
            return []
        }
        defer { IOObjectRelease(iterator) }

        var samples: [GPUShareClientSample] = []
        while true {
            let service = IOIteratorNext(iterator)
            if service == 0 { break }
            collect(from: service, into: &samples, depth: 0)
            IOObjectRelease(service)
        }
        return samples
    }

    /// User clients hang off the accelerator. One extra level covers a wrapper node.
    private static func collect(
        from entry: io_registry_entry_t,
        into samples: inout [GPUShareClientSample],
        depth: Int
    ) {
        if isAGXClient(entry), let sample = sample(for: entry) {
            samples.append(sample)
            return
        }
        guard depth < 2 else { return }
        var iterator: io_iterator_t = 0
        guard IORegistryEntryGetChildIterator(entry, kIOServicePlane, &iterator) == KERN_SUCCESS else { return }
        defer { IOObjectRelease(iterator) }
        while true {
            let child = IOIteratorNext(iterator)
            if child == 0 { break }
            collect(from: child, into: &samples, depth: depth + 1)
            IOObjectRelease(child)
        }
    }

    private static func isAGXClient(_ entry: io_object_t) -> Bool {
        var name = [CChar](repeating: 0, count: 128)
        let status = name.withUnsafeMutableBufferPointer { buffer -> kern_return_t in
            guard let base = buffer.baseAddress else { return KERN_FAILURE }
            return IOObjectGetClass(entry, base)
        }
        guard status == KERN_SUCCESS else { return false }
        return String(cString: name) == clientClass
    }

    private static func sample(for entry: io_registry_entry_t) -> GPUShareClientSample? {
        var entryID: UInt64 = 0
        guard IORegistryEntryGetRegistryEntryID(entry, &entryID) == KERN_SUCCESS else { return nil }
        var unmanaged: Unmanaged<CFMutableDictionary>?
        let status = IORegistryEntryCreateCFProperties(entry, &unmanaged, kCFAllocatorDefault, 0)
        guard status == KERN_SUCCESS, let properties = unmanaged?.takeRetainedValue() as NSDictionary? else {
            return nil
        }
        return GPUShareDecoder.parse(id: entryID, properties: swiftProperties(properties))
    }

    private static func swiftProperties(_ properties: NSDictionary) -> [String: Any] {
        var fields: [String: Any] = [:]
        for (key, value) in properties {
            guard let name = key as? String else { continue }
            if name == GPUShareDecoder.creatorKey {
                fields[name] = value
            } else if name == GPUShareDecoder.usageKey {
                fields[name] = swiftUsage(value)
            }
        }
        return fields
    }

    /// A bad entry makes the whole array unreadable instead of dropping that time as zero.
    private static func swiftUsage(_ value: Any) -> Any {
        guard let list = value as? NSArray else { return "unreadable" }
        var entries: [[String: Any]] = []
        for item in list {
            guard let entry = item as? NSDictionary else { return "unreadable" }
            guard let time = entry[GPUShareDecoder.timeKey] else { return "unreadable" }
            entries.append([GPUShareDecoder.timeKey: swiftTime(time)])
        }
        return entries
    }

    private static func swiftTime(_ value: Any) -> Any {
        guard let number = value as? NSNumber else { return value }
        if CFGetTypeID(number) == CFBooleanGetTypeID() { return number.boolValue }
        return number
    }
}
