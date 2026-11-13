import Darwin
import Foundation

/// One `dlopen` of IOReport. Energy Model is one subscription.
/// CPU Stats and GPU Stats are separate group deltas on that same library.
/// The first sample of a subscription has no delta, so watts and frequency stay nil.
enum HostEnergyModelReader {
    private static let frameworkPath = "/System/Library/PrivateFrameworks/IOReport.framework/IOReport"
    private static let energyGroup = "Energy Model"
    private static let cpuStatsGroup = "CPU Stats"
    private static let gpuStatsGroup = "GPU Stats"
    private static let channelsKey = "IOReportChannels"

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
    private typealias SimpleInteger = @convention(c) (OpaquePointer?, Int32) -> Int64
    private typealias StateCount = @convention(c) (OpaquePointer?) -> Int32
    private typealias StateName = @convention(c) (OpaquePointer?, Int32) -> OpaquePointer?
    private typealias StateResidency = @convention(c) (OpaquePointer?, Int32) -> Int64

    private struct Symbols {
        var copyChannels: CopyChannels
        var createSubscription: CreateSubscription
        var createSamples: CreateSamples
        var createSamplesDelta: CreateSamples
        var channelName: ChannelString
        var unitLabel: ChannelString
        var subgroup: ChannelString
        var simpleInteger: SimpleInteger
        var stateCount: StateCount
        var stateName: StateName
        var stateResidency: StateResidency
    }

    private struct Subscription {
        var handle: OpaquePointer
        var channels: OpaquePointer
        var previous: OpaquePointer?
    }

    private static var library: UnsafeMutableRawPointer?
    private static var symbols: Symbols?
    private static var unavailable = false
    private static var energy = Subscription?.none
    private static var cpuStats = Subscription?.none
    private static var gpuStats = Subscription?.none
    private static var previousAt: Date?

    /// `cpu`, `gpu`, and `rails` choose which channels to decode.
    /// The energy subscription is still the one Energy Model group.
    /// Previous cumulative is 0 because the sample is already a delta.
    static func read(
        at date: Date = Date(),
        cpu: Bool = false,
        gpu: Bool = false,
        rails: Bool = false
    ) -> EnergyModelReading? {
        guard cpu || gpu || rails else { return nil }
        guard let symbols = loadedSymbols() else { return nil }
        let elapsed = previousAt.map { date.timeIntervalSince($0) } ?? 0
        let current = energyChannels(symbols: symbols)
        let channels = current.map { channel in
            (
                previous: EnergyModelChannel(name: channel.name, unit: channel.unit, cumulative: 0),
                current: channel
            )
        }
        var reading = EnergyModelReading()
        if cpu {
            let frequencies = clusterFrequencies(symbols: symbols)
            let cpuReading = EnergyModelDecoder.cpuReading(
                channels: channels,
                elapsed: elapsed,
                performanceHertz: frequencies.performance,
                efficiencyHertz: frequencies.efficiency
            )
            reading.cpuWatts = cpuReading.cpuWatts
            reading.performanceHertz = cpuReading.performanceHertz
            reading.efficiencyHertz = cpuReading.efficiencyHertz
        }
        if gpu {
            reading.gpuWatts = EnergyModelDecoder.gpuWatts(channels: channels, elapsed: elapsed)
            reading.gpuHertz = gpuFrequency(symbols: symbols)
        }
        if rails {
            reading.aneWatts = EnergyModelDecoder.aneWatts(channels: channels, elapsed: elapsed)
            reading.dramWatts = EnergyModelDecoder.dramWatts(channels: channels, elapsed: elapsed)
        }
        previousAt = date
        if current.isEmpty,
           reading.cpuWatts == nil,
           reading.performanceHertz == nil,
           reading.efficiencyHertz == nil,
           reading.gpuWatts == nil,
           reading.gpuHertz == nil,
           reading.aneWatts == nil,
           reading.dramWatts == nil {
            return nil
        }
        return reading
    }

    /// One GPU Stats delta. Frequency is the state with the greatest residency,
    /// and only when that state's name parses as hertz.
    private static func gpuFrequency(symbols: Symbols) -> Double? {
        var states: [(name: String, residency: Int64)] = []
        withDeltaChannels(in: gpuStatsGroup, slot: &gpuStats, symbols: symbols) { channels in
            for channel in channels {
                let count = symbols.stateCount(channel)
                guard count > 0, count <= 64 else { continue }
                for index in 0..<count {
                    guard let name = string(symbols.stateName(channel, index)) else { continue }
                    states.append((name: name, residency: symbols.stateResidency(channel, index)))
                }
            }
        }
        return EnergyModelDecoder.dominantHertz(states)
    }

    /// One CPU Stats delta. Each cluster's frequency is the state that spent the
    /// most time there, and only when that state's name says a frequency.
    private static func clusterFrequencies(symbols: Symbols) -> (performance: Double?, efficiency: Double?) {
        var performance: (residency: Int64, name: String)?
        var efficiency: (residency: Int64, name: String)?
        withDeltaChannels(in: cpuStatsGroup, slot: &cpuStats, symbols: symbols) { channels in
            for channel in channels {
                let count = symbols.stateCount(channel)
                guard count > 0, count <= 64 else { continue }
                let subgroup = string(symbols.subgroup(channel)) ?? ""
                let channelName = string(symbols.channelName(channel)) ?? ""
                for index in 0..<count {
                    guard let name = string(symbols.stateName(channel, index)) else { continue }
                    let residency = symbols.stateResidency(channel, index)
                    guard residency > 0 else { continue }
                    if belongsToCluster("P", subgroup: subgroup, channel: channelName, state: name) {
                        if residency > (performance?.residency ?? -1) {
                            performance = (residency, name)
                        }
                    }
                    if belongsToCluster("E", subgroup: subgroup, channel: channelName, state: name) {
                        if residency > (efficiency?.residency ?? -1) {
                            efficiency = (residency, name)
                        }
                    }
                }
            }
        }
        return (
            performance.flatMap { EnergyModelDecoder.hertz(fromStateName: $0.name) },
            efficiency.flatMap { EnergyModelDecoder.hertz(fromStateName: $0.name) }
        )
    }

    private static func energyChannels(symbols: Symbols) -> [EnergyModelChannel] {
        var found: [EnergyModelChannel] = []
        withDeltaChannels(in: energyGroup, slot: &energy, symbols: symbols) { channels in
            found = channels.compactMap { channel in
                guard
                    let name = string(symbols.channelName(channel)),
                    let unit = string(symbols.unitLabel(channel))
                else { return nil }
                let value = symbols.simpleInteger(channel, 0)
                guard value >= 0 else { return nil }
                return EnergyModelChannel(name: name, unit: unit, cumulative: Double(value))
            }
        }
        return found
    }

    private static func belongsToCluster(
        _ marker: String,
        subgroup: String,
        channel: String,
        state: String
    ) -> Bool {
        let blob = subgroup + "\n" + channel + "\n" + state
        if marker == "P" {
            return blob.contains("Performance") || blob.contains("P-Cluster") || blob.contains("P-Core")
        }
        return blob.contains("Efficiency") || blob.contains("E-Cluster") || blob.contains("E-Core")
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
            let channelName: ChannelString = symbol("IOReportChannelGetChannelName", in: opened),
            let unitLabel: ChannelString = symbol("IOReportChannelGetUnitLabel", in: opened),
            let subgroup: ChannelString = symbol("IOReportChannelGetSubGroup", in: opened),
            let simpleInteger: SimpleInteger = symbol("IOReportSimpleGetIntegerValue", in: opened),
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
            channelName: channelName,
            unitLabel: unitLabel,
            subgroup: subgroup,
            simpleInteger: simpleInteger,
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

    /// Interval sample. The first call only stores a baseline and invokes `body` with nothing.
    private static func withDeltaChannels(
        in group: String,
        slot: inout Subscription?,
        symbols: Symbols,
        body: ([OpaquePointer]) -> Void
    ) {
        guard let subscription = ensure(&slot, group: group, symbols: symbols) else {
            body([])
            return
        }
        guard let sample = symbols.createSamples(subscription.handle, subscription.channels, nil) else {
            body([])
            return
        }
        guard let previous = subscription.previous else {
            slot?.previous = sample
            body([])
            return
        }
        let delta = symbols.createSamplesDelta(previous, sample, nil)
        release(previous)
        slot?.previous = sample
        guard let delta else {
            body([])
            return
        }
        defer { release(delta) }
        body(channelPointers(in: delta))
    }

    private static func ensure(
        _ slot: inout Subscription?,
        group: String,
        symbols: Symbols
    ) -> Subscription? {
        if let slot { return slot }
        guard let groupName = retained(group) else { return nil }
        defer { release(groupName) }
        guard let requested = symbols.copyChannels(groupName, nil, 0, 0, 0) else { return nil }
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
        guard let channels = out.pointee else {
            release(created)
            return nil
        }
        let made = Subscription(handle: created, channels: channels, previous: nil)
        slot = made
        return made
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
