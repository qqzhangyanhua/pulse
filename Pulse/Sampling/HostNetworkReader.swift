import Darwin
import Foundation

/// One cheap `getifaddrs()` + `AF_LINK` `ifi_ibytes` / `ifi_obytes` read.
/// Only `MemorySampler.sample()` calls this. No entitlement, no Network.framework session.
enum HostNetworkReader {
    static func read(at date: Date) -> HostNetworkSnapshot? {
        var ifaddrPointer: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddrPointer) == 0, let first = ifaddrPointer else { return nil }
        defer { freeifaddrs(first) }

        var interfaces: [String: HostNetworkInterfaceCounters] = [:]
        var cursor: UnsafeMutablePointer<ifaddrs>? = first
        while let ifaPointer = cursor {
            let ifa = ifaPointer.pointee
            cursor = ifa.ifa_next
            guard let addr = ifa.ifa_addr, addr.pointee.sa_family == sa_family_t(AF_LINK) else {
                continue
            }
            guard let nameC = ifa.ifa_name else { continue }
            let name = String(cString: nameC)
            guard !name.isEmpty, let data = ifa.ifa_data else { continue }

            let ifData = data.assumingMemoryBound(to: PulseIFData.self).pointee
            let flags = UInt32(ifa.ifa_flags)
            interfaces[name] = HostNetworkInterfaceCounters(
                name: name,
                inboundBytes: UInt64(ifData.ifi_ibytes),
                outboundBytes: UInt64(ifData.ifi_obytes),
                isUp: (flags & PulseIFFlags.up) != 0,
                isLoopback: (flags & PulseIFFlags.loopback) != 0
            )
        }
        return HostNetworkSnapshot(interfaces: interfaces, capturedAt: date)
    }
}

/// Darwin `net/if.h` flag bits used by `getifaddrs`. Numeric to avoid overlay drift.
private enum PulseIFFlags {
    static let up: UInt32 = 0x1
    static let loopback: UInt32 = 0x8
}

/// Prefix of Darwin `struct if_data` (net/if.h). Only the byte counters are consumed.
private struct PulseIFData {
    var ifi_type: UInt8 = 0
    var ifi_typelen: UInt8 = 0
    var ifi_physical: UInt8 = 0
    var ifi_addrlen: UInt8 = 0
    var ifi_hdrlen: UInt8 = 0
    var ifi_recvquota: UInt8 = 0
    var ifi_xmitquota: UInt8 = 0
    var ifi_unused1: UInt8 = 0
    var ifi_mtu: UInt32 = 0
    var ifi_metric: UInt32 = 0
    var ifi_baudrate: UInt32 = 0
    var ifi_ipackets: UInt32 = 0
    var ifi_ierrors: UInt32 = 0
    var ifi_opackets: UInt32 = 0
    var ifi_oerrors: UInt32 = 0
    var ifi_collisions: UInt32 = 0
    var ifi_ibytes: UInt32 = 0
    var ifi_obytes: UInt32 = 0
}
