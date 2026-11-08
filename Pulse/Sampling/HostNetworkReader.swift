import Darwin
import Foundation

/// One `sysctl(NET_RT_IFLIST2)` read of 64-bit `if_data64` byte counters.
/// Only `MemorySampler.sample()` calls this. No entitlement, no extra timer.
enum HostNetworkReader {
    static func read(at date: Date) -> HostNetworkSnapshot? {
        guard let bytes = interfaceListBytes() else { return nil }
        let parsed = bytes.withUnsafeBytes { raw in
            interfaceCounters(in: raw)
        }
        guard let parsed else { return nil }
        return HostNetworkSnapshot(interfaces: parsed, capturedAt: date)
    }

    /// Size, then read. A failed read gets one more size+read, then nil so the baseline stays.
    private static func interfaceListBytes() -> [UInt8]? {
        var name: [Int32] = [CTL_NET, PF_ROUTE, 0, 0, NET_RT_IFLIST2, 0]
        for _ in 0..<2 {
            var length = 0
            guard routeMIBSysctl(&name, into: nil, length: &length) == 0 else { return nil }
            guard length > 0 else { return [] }
            var buffer = [UInt8](repeating: 0, count: length)
            let status = buffer.withUnsafeMutableBytes { raw in
                routeMIBSysctl(&name, into: raw.baseAddress, length: &length)
            }
            guard status == 0, length <= buffer.count else { continue }
            return Array(buffer.prefix(length))
        }
        return nil
    }

    private static func routeMIBSysctl(
        _ name: inout [Int32],
        into destination: UnsafeMutableRawPointer?,
        length: inout Int
    ) -> Int32 {
        name.withUnsafeMutableBufferPointer { names in
            sysctl(names.baseAddress, u_int(names.count), destination, &length, nil, 0)
        }
    }

    private static func interfaceCounters(
        in buffer: UnsafeRawBufferPointer
    ) -> [String: HostNetworkInterfaceCounters]? {
        var interfaces: [String: HostNetworkInterfaceCounters] = [:]
        var offset = 0
        while offset < buffer.count {
            let remaining = buffer.count - offset
            guard remaining >= MemoryLayout<UInt16>.size else { return nil }
            let messageLength = Int(buffer.loadUnaligned(fromByteOffset: offset, as: UInt16.self))
            guard messageLength > 0, messageLength <= remaining else { return nil }
            if let counters = counters(in: buffer, messageAt: offset, length: messageLength) {
                interfaces[counters.name] = counters
            }
            offset += messageLength
        }
        return interfaces
    }

    /// `if_data64` is `#pragma pack(4)`. Use the Darwin type; a Swift `UInt64` struct aligns to 8.
    private static func counters(
        in buffer: UnsafeRawBufferPointer,
        messageAt offset: Int,
        length: Int
    ) -> HostNetworkInterfaceCounters? {
        guard length >= MemoryLayout<if_msghdr2>.size else { return nil }
        let header = buffer.loadUnaligned(fromByteOffset: offset, as: if_msghdr2.self)
        guard header.ifm_type == UInt8(RTM_IFINFO2) else { return nil }
        return counters(from: header)
    }

    private static func counters(from header: if_msghdr2) -> HostNetworkInterfaceCounters? {
        var nameBytes = [CChar](repeating: 0, count: Int(IF_NAMESIZE))
        guard if_indextoname(UInt32(header.ifm_index), &nameBytes) != nil else { return nil }
        let name = String(cString: nameBytes)
        guard !name.isEmpty else { return nil }
        let flags = header.ifm_flags
        return HostNetworkInterfaceCounters(
            name: name,
            inboundBytes: header.ifm_data.ifi_ibytes,
            outboundBytes: header.ifm_data.ifi_obytes,
            isUp: (flags & IFF_UP) != 0,
            isLoopback: (flags & IFF_LOOPBACK) != 0
        )
    }
}
