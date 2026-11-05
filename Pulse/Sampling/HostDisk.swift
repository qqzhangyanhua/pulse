import Foundation

/// One `IOBlockStorageDriver` snapshot. Identity is only a delta key (registry / BSD name).
struct HostDiskDriverCounters: Sendable, Equatable {
    let id: String
    let bytesRead: UInt64
    let bytesWritten: UInt64
}

/// Two-frame host rates. Nil means first frame, a failed read, a wrap, or no comparable driver.
struct HostDiskRates: Sendable, Equatable {
    let readBytesPerSecond: Double?
    let writeBytesPerSecond: Double?

    static let missing = HostDiskRates(readBytesPerSecond: nil, writeBytesPerSecond: nil)
}

struct HostDiskSnapshot: Sendable, Equatable {
    let drivers: [String: HostDiskDriverCounters]
    let capturedAt: Date

    init(drivers: [HostDiskDriverCounters], capturedAt: Date) {
        var map: [String: HostDiskDriverCounters] = [:]
        map.reserveCapacity(drivers.count)
        for driver in drivers {
            map[driver.id] = driver
        }
        self.drivers = map
        self.capturedAt = capturedAt
    }

    init(drivers: [String: HostDiskDriverCounters], capturedAt: Date) {
        self.drivers = drivers
        self.capturedAt = capturedAt
    }
}

struct HostDiskSample: Sendable, Equatable {
    let rates: HostDiskRates
    let baseline: HostDiskSnapshot?
}

/// Two-frame wall-clock host disk: Δbytes / Δseconds on IOBlockStorageDriver counters.
/// Per-driver deltas are summed so a new driver cannot emit an astronomical spike.
enum HostDiskLoad {
    static func rates(previous: HostDiskSnapshot?, current: HostDiskSnapshot) -> HostDiskRates {
        guard let previous else { return .missing }
        let seconds = current.capturedAt.timeIntervalSince(previous.capturedAt)
        guard seconds > 0 else { return .missing }

        var readDelta: UInt64 = 0
        var writeDelta: UInt64 = 0
        var compared = 0

        for (id, currentDriver) in current.drivers {
            guard let previousDriver = previous.drivers[id] else { continue }
            guard currentDriver.bytesRead >= previousDriver.bytesRead,
                  currentDriver.bytesWritten >= previousDriver.bytesWritten
            else {
                return .missing
            }
            readDelta += currentDriver.bytesRead - previousDriver.bytesRead
            writeDelta += currentDriver.bytesWritten - previousDriver.bytesWritten
            compared += 1
        }

        guard compared > 0 else { return .missing }
        return HostDiskRates(
            readBytesPerSecond: Double(readDelta) / seconds,
            writeBytesPerSecond: Double(writeDelta) / seconds
        )
    }

    /// Failed reads stay `nil` and keep the last baseline. A successful read always becomes the next baseline.
    static func advance(previous: HostDiskSnapshot?, reading: HostDiskSnapshot?) -> HostDiskSample {
        guard let reading else {
            return HostDiskSample(rates: .missing, baseline: previous)
        }
        return HostDiskSample(
            rates: rates(previous: previous, current: reading),
            baseline: reading
        )
    }
}

/// Cumulative `ri_diskio_*` counters for one process. The first frame is `nil`.
struct DiskTick: Sendable, Equatable {
    let bytesRead: UInt64
    let bytesWritten: UInt64
    let date: Date
}

struct ProcessDiskSample: Sendable, Equatable {
    let rates: HostDiskRates
    let baseline: DiskTick?
}

/// Two-frame wall-clock process disk. EPERM / a missed rusage keeps the last baseline.
enum ProcessDiskLoad {
    static func rates(previous: DiskTick?, current: DiskTick) -> HostDiskRates {
        guard let previous,
              current.bytesRead >= previous.bytesRead,
              current.bytesWritten >= previous.bytesWritten
        else {
            return .missing
        }
        let seconds = current.date.timeIntervalSince(previous.date)
        guard seconds > 0 else { return .missing }
        return HostDiskRates(
            readBytesPerSecond: Double(current.bytesRead - previous.bytesRead) / seconds,
            writeBytesPerSecond: Double(current.bytesWritten - previous.bytesWritten) / seconds
        )
    }

    static func advance(previous: DiskTick?, reading: DiskTick?) -> ProcessDiskSample {
        guard let reading else {
            return ProcessDiskSample(rates: .missing, baseline: previous)
        }
        return ProcessDiskSample(
            rates: rates(previous: previous, current: reading),
            baseline: reading
        )
    }
}
