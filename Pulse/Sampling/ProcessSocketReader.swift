import Darwin
import Foundation

/// Socket facts for one pid. `getuid` stays here, not in the portable model.
/// Called when the selected pid changes, and only for this user's row.
enum ProcessSocketReader {
    static func currentUserID() -> UInt32 {
        UInt32(getuid())
    }

    /// Nil when `PROC_PIDLISTFDS` fails. Empty when the process has no socket descriptors.
    /// A failed `PROC_PIDFDSOCKETINFO` is an unreadable fact. File descriptors are not returned.
    static func read(pid: Int32) -> [ProcessSocketFact]? {
        guard let descriptors = socketDescriptors(pid: pid) else { return nil }
        var facts: [ProcessSocketFact] = []
        facts.reserveCapacity(descriptors.count)
        for fd in descriptors {
            if let fact = socketFact(pid: pid, fd: fd) {
                facts.append(fact)
            }
        }
        return facts
    }

    private static let listFDsFlavor: Int32 = 1
    private static let socketInfoFlavor: Int32 = 3
    private static let socketFDType: UInt32 = 2
    private static let fdRecordSize = 8
    private static let maxListBytes = 1_048_576
    /// Larger than `socket_fdinfo`. The kernel writes the struct at the front.
    private static let socketBufferBytes = 4096

    /// Offsets in `socket_fdinfo` (`sys/proc_info.h`, little-endian).
    /// `proc_fileinfo` is 24 bytes. `in_sockinfo` starts at `soi_proto`.
    private enum Layout {
        static let type = 24 + 152
        static let ipProtocol = 24 + 156
        static let family = 24 + 160
        static let kind = 24 + 232
        static let proto = 24 + 240
        static let foreignPort = proto
        static let localPort = proto + 4
        static let foreignAddress = proto + 32
        static let tcpState = proto + 80
        static let minimum = kind + 4
        static let addressEnd = foreignAddress + 16
        static let tcpEnd = tcpState + 4
    }

    private static let ipv4: Int32 = 2
    private static let ipv6: Int32 = 30
    private static let kindTCP: Int32 = 2

    private static func socketDescriptors(pid: Int32) -> [Int32]? {
        errno = 0
        let needed = pulse_proc_pidinfo(pid, listFDsFlavor, 0, nil, 0)
        if needed < 0 { return nil }
        if needed == 0 { return errno == 0 ? [] : nil }
        guard needed <= maxListBytes else { return nil }

        var bytes = [UInt8](repeating: 0, count: Int(needed))
        let written = bytes.withUnsafeMutableBytes { raw -> Int32 in
            guard let base = raw.baseAddress else { return 0 }
            return pulse_proc_pidinfo(pid, listFDsFlavor, 0, base, needed)
        }
        guard written > 0 else { return nil }

        let count = min(Int(written), bytes.count) / fdRecordSize
        var fds: [Int32] = []
        for index in 0..<count {
            let offset = index * fdRecordSize
            guard let fd = int32(bytes, at: offset),
                  let fdType = uint32(bytes, at: offset + 4)
            else { continue }
            if fdType == socketFDType {
                fds.append(fd)
            }
        }
        return fds
    }

    /// Nil drops a descriptor that closed between the list and the read (`EBADF`).
    private static func socketFact(pid: Int32, fd: Int32) -> ProcessSocketFact? {
        var bytes = [UInt8](repeating: 0, count: socketBufferBytes)
        errno = 0
        let written = bytes.withUnsafeMutableBytes { raw -> Int32 in
            guard let base = raw.baseAddress else { return 0 }
            return pulse_proc_pidfdinfo(
                pid,
                fd,
                socketInfoFlavor,
                base,
                Int32(raw.count)
            )
        }
        if written <= 0 {
            if errno == EBADF { return nil }
            return ProcessSocketFact.unreadable
        }
        let limit = min(Int(written), bytes.count)
        guard limit >= Layout.minimum,
              let socketType = int32(bytes, at: Layout.type),
              let ipProtocol = int32(bytes, at: Layout.ipProtocol),
              let family = int32(bytes, at: Layout.family),
              let kind = int32(bytes, at: Layout.kind)
        else { return ProcessSocketFact.unreadable }

        let internet = family == ipv4 || family == ipv6
        let needsTCP = kind == kindTCP
        if internet, limit < Layout.addressEnd { return ProcessSocketFact.unreadable }
        if needsTCP, limit < Layout.tcpEnd { return ProcessSocketFact.unreadable }

        let remote = internet ? endpoint(bytes, family: family) : nil
        return ProcessSocketFact(
            family: family,
            socketType: socketType,
            ipProtocol: ipProtocol,
            kind: kind,
            tcpState: needsTCP ? int32(bytes, at: Layout.tcpState) : nil,
            localPort: internet ? hostPort(int32(bytes, at: Layout.localPort)) : nil,
            remotePort: remote?.port,
            remoteAddress: remote?.address,
            readable: true
        )
    }

    /// `insi_fport` is a network-order port in the low 16 bits. Nil address when unspecified.
    private static func endpoint(_ bytes: [UInt8], family: Int32) -> (address: String, port: Int)? {
        guard let rawPort = int32(bytes, at: Layout.foreignPort) else { return nil }
        guard let port = hostPort(rawPort) else { return nil }
        guard let address = presentation(family: family, bytes: bytes) else { return nil }
        return (address, port)
    }

    private static func presentation(family: Int32, bytes: [UInt8]) -> String? {
        let start = Layout.foreignAddress
        guard start + 16 <= bytes.count else { return nil }
        let raw = Array(bytes[start..<(start + 16)])
        var buffer = [CChar](repeating: 0, count: Int(INET6_ADDRSTRLEN))
        let formatted: Bool = raw.withUnsafeBytes { view in
            guard let base = view.baseAddress else { return false }
            let source = family == ipv4 ? base.advanced(by: 12) : base
            let af = family == ipv4 ? AF_INET : AF_INET6
            return inet_ntop(af, source, &buffer, socklen_t(buffer.count)) != nil
        }
        guard formatted else { return nil }
        let text = String(cString: buffer)
        return text.isEmpty ? nil : text
    }

    private static func hostPort(_ raw: Int32?) -> Int? {
        guard let raw else { return nil }
        return Int(UInt16(bigEndian: UInt16(truncatingIfNeeded: raw)))
    }

    private static func int32(_ bytes: [UInt8], at offset: Int) -> Int32? {
        guard let raw = uint32(bytes, at: offset) else { return nil }
        return Int32(bitPattern: raw)
    }

    private static func uint32(_ bytes: [UInt8], at offset: Int) -> UInt32? {
        guard offset >= 0, offset + 4 <= bytes.count else { return nil }
        return UInt32(bytes[offset])
            | UInt32(bytes[offset + 1]) << 8
            | UInt32(bytes[offset + 2]) << 16
            | UInt32(bytes[offset + 3]) << 24
    }
}

@_silgen_name("proc_pidinfo")
private func pulse_proc_pidinfo(
    _ pid: Int32,
    _ flavor: Int32,
    _ arg: UInt64,
    _ buffer: UnsafeMutableRawPointer?,
    _ buffersize: Int32
) -> Int32

@_silgen_name("proc_pidfdinfo")
private func pulse_proc_pidfdinfo(
    _ pid: Int32,
    _ fd: Int32,
    _ flavor: Int32,
    _ buffer: UnsafeMutableRawPointer?,
    _ buffersize: Int32
) -> Int32
