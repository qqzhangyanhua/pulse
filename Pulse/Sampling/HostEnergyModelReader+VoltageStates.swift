import Foundation
import IOKit

extension HostEnergyModelReader {
    /// pmgr `voltage-states9` bytes. A registry property, not a user client.
    static func voltageStates9Bytes() -> Data? {
        guard let matching = IOServiceNameMatching("pmgr") else { return nil }
        let service = IOServiceGetMatchingService(kIOMainPortDefault, matching)
        guard service != 0 else { return nil }
        defer { IOObjectRelease(service) }
        var unmanaged: Unmanaged<CFMutableDictionary>?
        let status = IORegistryEntryCreateCFProperties(service, &unmanaged, kCFAllocatorDefault, 0)
        guard status == KERN_SUCCESS, let properties = unmanaged?.takeRetainedValue() as NSDictionary? else {
            return nil
        }
        guard let data = properties["voltage-states9"] as? Data, !data.isEmpty else { return nil }
        return data
    }
}
