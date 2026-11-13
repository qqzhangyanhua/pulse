import Foundation

/// One socket copied out of libproc. No Darwin types.
/// Ports are host order. A nil remote address means there is no peer.
struct ProcessSocketFact: Equatable, Sendable {
    /// `soi_family`. 2 is IPv4, 30 is IPv6.
    var family: Int32
    /// `soi_type`. 1 is a stream, 2 is a datagram.
    var socketType: Int32
    /// `soi_protocol`. 6 is TCP, 17 is UDP. 0 still counts as TCP when `kind` is TCP.
    var ipProtocol: Int32
    /// `soi_kind`. 2 is TCP, 1 is a generic IP socket.
    var kind: Int32
    /// `tcpsi_state` for a TCP socket. 1 is listen. Nil when this is not TCP.
    var tcpState: Int32?
    var localPort: Int?
    var remotePort: Int?
    var remoteAddress: String?
    /// False when `PROC_PIDFDSOCKETINFO` failed for this descriptor.
    var readable: Bool

    static let unreadable = ProcessSocketFact(
        family: 0,
        socketType: 0,
        ipProtocol: 0,
        kind: 0,
        tcpState: nil,
        localPort: nil,
        remotePort: nil,
        remoteAddress: nil,
        readable: false
    )
}

struct ProcessSocketLines: Equatable, Sendable {
    var listening: [String]
    var connections: [String]
    /// True when at least one socket descriptor could not be read.
    var unreadable: Bool
}

enum ProcessSocketDecoder {
    private static let ipv4: Int32 = 2
    private static let ipv6: Int32 = 30
    private static let stream: Int32 = 1
    private static let datagram: Int32 = 2
    private static let tcpProtocol: Int32 = 6
    private static let udpProtocol: Int32 = 17
    private static let kindTCP: Int32 = 2
    private static let tcpListenState: Int32 = 1

    static func lines(from facts: [ProcessSocketFact]) -> ProcessSocketLines {
        var listening: [String] = []
        var connections: [String] = []
        var unreadable = false
        for fact in facts {
            guard fact.readable else {
                unreadable = true
                continue
            }
            switch classify(fact) {
            case let .listen(text):
                listening.append(text)
            case let .connection(text):
                connections.append(text)
            case .skip:
                break
            }
        }
        return ProcessSocketLines(
            listening: listening,
            connections: connections,
            unreadable: unreadable
        )
    }

    private enum Classified {
        case listen(String)
        case connection(String)
        case skip
    }

    private static func classify(_ fact: ProcessSocketFact) -> Classified {
        guard fact.family == ipv4 || fact.family == ipv6 else { return .skip }
        let name = isTCP(fact) ? "TCP" : (isUDP(fact) ? "UDP" : nil)
        guard let name else { return .skip }
        if isTCP(fact), fact.tcpState == tcpListenState, let port = shownPort(fact.localPort) {
            return .listen("\(name) \(port)")
        }
        if let endpoint = remoteEndpoint(fact) {
            return .connection("\(name) \(endpoint)")
        }
        if isUDP(fact), let port = shownPort(fact.localPort) {
            return .listen("\(name) \(port)")
        }
        return .skip
    }

    private static func isTCP(_ fact: ProcessSocketFact) -> Bool {
        if fact.kind == kindTCP { return true }
        return fact.socketType == stream && (fact.ipProtocol == tcpProtocol || fact.ipProtocol == 0)
    }

    private static func isUDP(_ fact: ProcessSocketFact) -> Bool {
        if isTCP(fact) { return false }
        return fact.ipProtocol == udpProtocol || fact.socketType == datagram
    }

    private static func shownPort(_ port: Int?) -> Int? {
        guard let port, (0...65535).contains(port) else { return nil }
        return port
    }

    /// Nil for a missing, unspecified, or zero peer. IPv6 addresses are bracketed.
    private static func remoteEndpoint(_ fact: ProcessSocketFact) -> String? {
        guard let port = fact.remotePort, (1...65535).contains(port) else { return nil }
        guard let address = fact.remoteAddress?.trimmingCharacters(in: .whitespacesAndNewlines),
              !address.isEmpty,
              address != "0.0.0.0",
              address != "::"
        else { return nil }
        if address.contains(":") {
            return "[\(address)]:\(port)"
        }
        return "\(address):\(port)"
    }
}

struct ProcessSocketSectionText: Equatable, Sendable {
    var listening: String
    var connections: String
    /// Set only when the row is not this user. Absent for an empty or unreadable list.
    var permissionNote: String?
}

enum ProcessSocketPresentation {
    static let missing = "—"
    static let denied = "没有读取权限"
    static let none = "没有"

    /// `facts == nil` means the descriptor list was not read.
    /// A row that is not this user ignores `facts` and is not an empty list.
    static func text(
        rowUid: UInt32?,
        selfUid: UInt32,
        facts: [ProcessSocketFact]?
    ) -> ProcessSocketSectionText {
        guard isOwnUser(rowUid: rowUid, selfUid: selfUid) else {
            return ProcessSocketSectionText(
                listening: missing,
                connections: missing,
                permissionNote: denied
            )
        }
        guard let facts else {
            return ProcessSocketSectionText(
                listening: missing,
                connections: missing,
                permissionNote: nil
            )
        }
        let lines = ProcessSocketDecoder.lines(from: facts)
        if lines.unreadable, lines.listening.isEmpty, lines.connections.isEmpty {
            return ProcessSocketSectionText(
                listening: missing,
                connections: missing,
                permissionNote: nil
            )
        }
        return ProcessSocketSectionText(
            listening: joined(lines.listening),
            connections: joined(lines.connections),
            permissionNote: nil
        )
    }

    private static func joined(_ lines: [String]) -> String {
        lines.isEmpty ? none : lines.joined(separator: "\n")
    }
}
