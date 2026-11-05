import Foundation

/// One `AF_LINK` interface snapshot. Eligibility (UP, non-loopback) is decided by `HostNetworkLoad`.
struct HostNetworkInterfaceCounters: Sendable, Equatable {
    let name: String
    let inboundBytes: UInt64
    let outboundBytes: UInt64
    let isUp: Bool
    let isLoopback: Bool
}

/// Host interface byte counters after the same eligibility filter the rate math uses.
struct HostNetworkCounters: Sendable, Equatable {
    let inboundBytes: UInt64
    let outboundBytes: UInt64
}

/// Two-frame host rates. Nil means first frame, a failed read, a wrap, or no comparable iface.
struct HostNetworkRates: Sendable, Equatable {
    let inboundBytesPerSecond: Double?
    let outboundBytesPerSecond: Double?

    static let missing = HostNetworkRates(inboundBytesPerSecond: nil, outboundBytesPerSecond: nil)
}

struct HostNetworkSnapshot: Sendable, Equatable {
    let interfaces: [String: HostNetworkInterfaceCounters]
    let capturedAt: Date

    init(interfaces: [HostNetworkInterfaceCounters], capturedAt: Date) {
        var map: [String: HostNetworkInterfaceCounters] = [:]
        map.reserveCapacity(interfaces.count)
        for iface in interfaces {
            map[iface.name] = iface
        }
        self.interfaces = map
        self.capturedAt = capturedAt
    }

    init(interfaces: [String: HostNetworkInterfaceCounters], capturedAt: Date) {
        self.interfaces = interfaces
        self.capturedAt = capturedAt
    }
}

struct HostNetworkSample: Sendable, Equatable {
    let rates: HostNetworkRates
    let baseline: HostNetworkSnapshot?
}

/// Two-frame wall-clock host network: Δbytes / Δseconds on UP, non-loopback ifaces.
/// Per-iface deltas are summed so a new iface cannot emit an astronomical spike.
enum HostNetworkLoad {
    static func isEligible(_ iface: HostNetworkInterfaceCounters) -> Bool {
        iface.isUp && !iface.isLoopback
    }

    static func totals(of snapshot: HostNetworkSnapshot) -> HostNetworkCounters {
        var inbound: UInt64 = 0
        var outbound: UInt64 = 0
        for iface in snapshot.interfaces.values where isEligible(iface) {
            inbound += iface.inboundBytes
            outbound += iface.outboundBytes
        }
        return HostNetworkCounters(inboundBytes: inbound, outboundBytes: outbound)
    }

    static func rates(previous: HostNetworkSnapshot?, current: HostNetworkSnapshot) -> HostNetworkRates {
        guard let previous else { return .missing }
        let seconds = current.capturedAt.timeIntervalSince(previous.capturedAt)
        guard seconds > 0 else { return .missing }

        var inboundDelta: UInt64 = 0
        var outboundDelta: UInt64 = 0
        var compared = 0

        for (name, currentIface) in current.interfaces {
            guard isEligible(currentIface),
                  let previousIface = previous.interfaces[name],
                  isEligible(previousIface)
            else {
                continue
            }
            guard currentIface.inboundBytes >= previousIface.inboundBytes,
                  currentIface.outboundBytes >= previousIface.outboundBytes
            else {
                return .missing
            }
            inboundDelta += currentIface.inboundBytes - previousIface.inboundBytes
            outboundDelta += currentIface.outboundBytes - previousIface.outboundBytes
            compared += 1
        }

        guard compared > 0 else { return .missing }
        return HostNetworkRates(
            inboundBytesPerSecond: Double(inboundDelta) / seconds,
            outboundBytesPerSecond: Double(outboundDelta) / seconds
        )
    }

    /// Failed reads stay `nil` and keep the last baseline. A successful read always becomes the next baseline.
    static func advance(previous: HostNetworkSnapshot?, reading: HostNetworkSnapshot?) -> HostNetworkSample {
        guard let reading else {
            return HostNetworkSample(rates: .missing, baseline: previous)
        }
        return HostNetworkSample(
            rates: rates(previous: previous, current: reading),
            baseline: reading
        )
    }
}
