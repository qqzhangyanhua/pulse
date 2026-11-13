import Darwin
import Foundation
import IOKit

/// Registry properties for published accelerator performance statistics.
/// A machine-scoped device percent is copied onto every node missing the
/// device-utilization key. Only `MemorySampler.sample()` calls this.
/// No user client and no Metal counters.
enum HostGPUReader {
    private static let acceleratorClass = "IOAccelerator"
    private static let statisticsKey = "PerformanceStatistics"

    static func read() -> [GPUAcceleratorNode] {
        attachDevicePercent(to: acceleratorNodes())
    }

    /// The device channel is not a property of each registry entry.
    /// A present key is left alone. A nil channel stays nil and is not called
    /// when every node already has the key.
    private static func attachDevicePercent(to nodes: [GPUAcceleratorNode]) -> [GPUAcceleratorNode] {
        let missing = nodes.indices.filter {
            nodes[$0].statistics[GPUPageProjection.deviceUtilizationKey] == nil
        }
        guard !missing.isEmpty else { return nodes }
        guard let percent = IOReportDeviceChannel.percent() else { return nodes }
        var copy = nodes
        for index in missing {
            copy[index].ioReportDevicePercent = percent
        }
        return copy
    }

    private static func acceleratorNodes() -> [GPUAcceleratorNode] {
        guard let matching = IOServiceMatching(acceleratorClass) else { return [] }
        var iterator: io_iterator_t = 0
        let status = IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator)
        guard status == KERN_SUCCESS else { return [] }
        defer { IOObjectRelease(iterator) }

        var nodes: [GPUAcceleratorNode] = []
        var sawAccelerator = false
        while true {
            let service = IOIteratorNext(iterator)
            if service == 0 { break }
            defer { IOObjectRelease(service) }
            sawAccelerator = true
            if let node = node(for: service) {
                nodes.append(node)
            }
        }
        if nodes.isEmpty, sawAccelerator {
            nodes.append(GPUAcceleratorNode())
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

/// Device residency for the whole machine. Opened with `dlopen`, not linked.
/// The first sample has no delta, so it stays nil instead of storing 0.
private enum IOReportDeviceChannel {
    private static let frameworkPath = "/System/Library/PrivateFrameworks/IOReport.framework/IOReport"
    private static let groupName = "GPU Stats"
    private static let subgroupName = "GPU Performance States"
    private static let offState = "OFF"
    private static let channelsKey = "IOReportChannels"
    private static let maxStates = 64

    private typealias CopyChannels = @convention(c) (
        OpaquePointer?, OpaquePointer?, UInt64, UInt64, UInt64
    ) -> OpaquePointer?
    private typealias CreateSubscription = @convention(c) (
        UnsafeMutableRawPointer?,
        OpaquePointer?,
        UnsafeMutablePointer<OpaquePointer?>?,
        UInt64,
        UnsafeMutableRawPointer?
    ) -> OpaquePointer?
    private typealias CreateSamples = @convention(c) (
        OpaquePointer?, OpaquePointer?, UnsafeMutableRawPointer?
    ) -> OpaquePointer?
    private typealias ChannelString = @convention(c) (OpaquePointer?) -> OpaquePointer?
    private typealias StateCount = @convention(c) (OpaquePointer?) -> Int32
    private typealias StateName = @convention(c) (OpaquePointer?, Int32) -> OpaquePointer?
    private typealias StateResidency = @convention(c) (OpaquePointer?, Int32) -> Int64

    private struct Symbols {
        var copyChannels: CopyChannels
        var createSubscription: CreateSubscription
        var createSamples: CreateSamples
        var createSamplesDelta: CreateSamples
        var channelGroup: ChannelString
        var channelSubgroup: ChannelString
        var stateCount: StateCount
        var stateName: StateName
        var stateResidency: StateResidency
    }

    private static var library: UnsafeMutableRawPointer?
    private static var symbols: Symbols?
    private static var unavailable = false
    private static var subscription: OpaquePointer?
    private static var subscribedChannels: OpaquePointer?
    private static var previousSample: OpaquePointer?

    static func percent() -> Double? {
        guard let symbols = loadedSymbols() else { return nil }
        guard let subscription = ensureSubscription(symbols), let channels = subscribedChannels else {
            return nil
        }
        guard let sample = symbols.createSamples(subscription, channels, nil) else { return nil }
        guard let previous = previousSample else {
            previousSample = sample
            return nil
        }
        let delta = symbols.createSamplesDelta(previous, sample, nil)
        release(previous)
        previousSample = sample
        guard let delta else { return nil }
        defer { release(delta) }
        return percent(in: delta, symbols: symbols)
    }

    private static func loadedSymbols() -> Symbols? {
        if let symbols { return symbols }
        if unavailable { return nil }
        guard let opened = dlopen(frameworkPath, RTLD_LAZY | RTLD_LOCAL) else {
            unavailable = true
            return nil
        }
        guard
            let copyChannels: CopyChannels = symbol("IOReportCopyChannelsInGroup", in: opened),
            let createSubscription: CreateSubscription = symbol("IOReportCreateSubscription", in: opened),
            let createSamples: CreateSamples = symbol("IOReportCreateSamples", in: opened),
            let createSamplesDelta: CreateSamples = symbol("IOReportCreateSamplesDelta", in: opened),
            let channelGroup: ChannelString = symbol("IOReportChannelGetGroup", in: opened),
            let channelSubgroup: ChannelString = symbol("IOReportChannelGetSubGroup", in: opened),
            let stateCount: StateCount = symbol("IOReportStateGetCount", in: opened),
            let stateName: StateName = symbol("IOReportStateGetNameForIndex", in: opened),
            let stateResidency: StateResidency = symbol("IOReportStateGetResidency", in: opened)
        else {
            dlclose(opened)
            unavailable = true
            return nil
        }
        library = opened
        let loaded = Symbols(
            copyChannels: copyChannels,
            createSubscription: createSubscription,
            createSamples: createSamples,
            createSamplesDelta: createSamplesDelta,
            channelGroup: channelGroup,
            channelSubgroup: channelSubgroup,
            stateCount: stateCount,
            stateName: stateName,
            stateResidency: stateResidency
        )
        symbols = loaded
        return loaded
    }

    private static func symbol<T>(_ name: String, in library: UnsafeMutableRawPointer) -> T? {
        guard let raw = dlsym(library, name) else { return nil }
        return unsafeBitCast(raw, to: T.self)
    }

    private static func ensureSubscription(_ symbols: Symbols) -> OpaquePointer? {
        if let subscription { return subscription }
        guard let group = retained(groupName) else { return nil }
        defer { release(group) }
        guard let subgroup = retained(subgroupName) else { return nil }
        defer { release(subgroup) }
        guard let requested = symbols.copyChannels(group, subgroup, 0, 0, 0) else { return nil }
        defer { release(requested) }

        let out = UnsafeMutablePointer<OpaquePointer?>.allocate(capacity: 1)
        out.initialize(to: nil)
        defer {
            out.deinitialize(count: 1)
            out.deallocate()
        }
        guard let created = symbols.createSubscription(nil, requested, out, 0, nil) else {
            release(out.pointee)
            return nil
        }
        guard let subscribed = out.pointee else {
            release(created)
            return nil
        }
        subscription = created
        subscribedChannels = subscribed
        return created
    }

    /// 100 * (sum of state residency − OFF) / sum. A missing subgroup, an empty
    /// total, or an unreadable state stays nil.
    private static func percent(in sample: OpaquePointer, symbols: Symbols) -> Double? {
        let channels = channelPointers(in: sample)
        guard !channels.isEmpty else { return nil }
        var total: Int64 = 0
        var off: Int64 = 0
        var sawState = false
        for channel in channels {
            guard string(symbols.channelGroup(channel)) == groupName,
                  string(symbols.channelSubgroup(channel)) == subgroupName
            else { continue }
            let count = symbols.stateCount(channel)
            if count == 0 { continue }
            guard count > 0, count <= Int32(maxStates) else { return nil }
            for index in 0..<count {
                guard let name = string(symbols.stateName(channel, index)) else { return nil }
                let residency = symbols.stateResidency(channel, index)
                guard residency >= 0 else { return nil }
                let (nextTotal, totalOverflow) = total.addingReportingOverflow(residency)
                let (nextOff, offOverflow) = name == offState
                    ? off.addingReportingOverflow(residency)
                    : (off, false)
                guard !totalOverflow, !offOverflow else { return nil }
                total = nextTotal
                off = nextOff
                sawState = true
            }
        }
        guard sawState, total > 0, off <= total else { return nil }
        return 100 * Double(total - off) / Double(total)
    }

    private static func channelPointers(in sample: OpaquePointer) -> [OpaquePointer] {
        guard let key = retained(channelsKey) else { return [] }
        defer { release(key) }
        let dictionary = Unmanaged<CFDictionary>.fromOpaque(UnsafeRawPointer(sample)).takeUnretainedValue()
        let rawValue = CFDictionaryGetValue(dictionary, UnsafeRawPointer(key))
        guard let raw = rawValue else { return [] }
        let object = Unmanaged<CFTypeRef>.fromOpaque(raw).takeUnretainedValue()
        guard CFGetTypeID(object) == CFArrayGetTypeID() else { return [] }
        let array = Unmanaged<CFArray>.fromOpaque(raw).takeUnretainedValue()
        let count = CFArrayGetCount(array)
        guard count > 0 else { return [] }
        var channels: [OpaquePointer] = []
        channels.reserveCapacity(count)
        for index in 0..<count {
            guard let value = CFArrayGetValueAtIndex(array, index) else { continue }
            channels.append(OpaquePointer(UnsafeMutableRawPointer(mutating: value)))
        }
        return channels
    }

    private static func retained(_ text: String) -> OpaquePointer? {
        let value = text as CFString
        return OpaquePointer(Unmanaged.passRetained(value).toOpaque())
    }

    private static func string(_ ref: OpaquePointer?) -> String? {
        guard let ref else { return nil }
        let value = Unmanaged<CFString>.fromOpaque(UnsafeRawPointer(ref)).takeUnretainedValue()
        return value as String
    }

    private static func release(_ ref: OpaquePointer?) {
        guard let ref else { return }
        Unmanaged<CFTypeRef>.fromOpaque(UnsafeRawPointer(ref)).release()
    }
}
