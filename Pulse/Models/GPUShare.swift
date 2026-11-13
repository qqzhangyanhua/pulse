import Foundation

/// One AGXDeviceUserClient after its registry properties are read.
/// `accumulatedGPUTimeNanoseconds` is nil when that client's time could not be read.
struct GPUShareClientSample: Equatable, Sendable {
    var id: UInt64
    var pid: Int32?
    var creatorName: String?
    var accumulatedGPUTimeNanoseconds: UInt64?
}

/// One pid's GPU share for a pair of frames. Nil percent is 「—」, never 0.
struct GPUShareReading: Equatable, Sendable {
    var pid: Int32
    var percent: Double?
    var text: String
    var creatorName: String?
}

/// Pure decode of `AGXDeviceUserClient` registry properties.
/// Pid comes from `IOUserClientCreator`. Time is `AppUsage[].accumulatedGPUTime` in nanoseconds.
enum GPUShareDecoder {
    static let creatorKey = "IOUserClientCreator"
    static let usageKey = "AppUsage"
    static let timeKey = "accumulatedGPUTime"

    static func parse(id: UInt64, properties: [String: Any]) -> GPUShareClientSample {
        let creator = creatorFields(properties[creatorKey])
        return GPUShareClientSample(
            id: id,
            pid: creator?.pid,
            creatorName: creator?.name,
            accumulatedGPUTimeNanoseconds: accumulatedTime(properties[usageKey])
        )
    }

    /// Same pid's clients are summed. A new client is only a baseline.
    /// A disappeared client, a rewound counter, an unreadable time, or a zero interval is 「—」.
    static func shares(
        previous: [GPUShareClientSample],
        current: [GPUShareClientSample],
        elapsedNanoseconds: UInt64
    ) -> [GPUShareReading] {
        let currentByPid = Dictionary(grouping: current.filter { $0.pid != nil }) { $0.pid! }
        let previousByPid = Dictionary(grouping: previous.filter { $0.pid != nil }) { $0.pid! }
        let pids = currentByPid.keys.sorted()
        return pids.map { pid in
            let reading = share(
                pid: pid,
                previous: previousByPid[pid] ?? [],
                current: currentByPid[pid] ?? [],
                elapsedNanoseconds: elapsedNanoseconds
            )
            return reading
        }
    }

    private static func share(
        pid: Int32,
        previous: [GPUShareClientSample],
        current: [GPUShareClientSample],
        elapsedNanoseconds: UInt64
    ) -> GPUShareReading {
        let name = current.compactMap(\.creatorName).first
        let missing = GPUShareReading(
            pid: pid,
            percent: nil,
            text: CPUPercentText.missing,
            creatorName: name
        )
        guard elapsedNanoseconds > 0 else { return missing }
        guard !current.contains(where: { $0.accumulatedGPUTimeNanoseconds == nil }) else { return missing }
        guard !previous.isEmpty else { return missing }
        let previousIDs = Set(previous.map(\.id))
        let currentIDs = Set(current.map(\.id))
        guard previousIDs.isSubset(of: currentIDs) else { return missing }
        guard !previous.contains(where: { $0.accumulatedGPUTimeNanoseconds == nil }) else { return missing }
        let overlappedCurrent = current.filter { previousIDs.contains($0.id) }
        guard let before = sum(previous), let after = sum(overlappedCurrent) else { return missing }
        guard after >= before else { return missing }
        let percent = Double(after - before) / Double(elapsedNanoseconds) * 100
        guard percent.isFinite else { return missing }
        return GPUShareReading(
            pid: pid,
            percent: percent,
            text: CPUPercentText.string(percent),
            creatorName: name
        )
    }

    private static func sum(_ samples: [GPUShareClientSample]) -> UInt64? {
        var total: UInt64 = 0
        var seen = Set<UInt64>()
        for sample in samples {
            guard seen.insert(sample.id).inserted else { return nil }
            guard let time = sample.accumulatedGPUTimeNanoseconds else { return nil }
            let (next, overflow) = total.addingReportingOverflow(time)
            guard !overflow else { return nil }
            total = next
        }
        return total
    }

    private static func creatorFields(_ value: Any?) -> (pid: Int32, name: String?)? {
        guard let text = value as? String else { return nil }
        let prefix = "pid "
        guard text.hasPrefix(prefix) else { return nil }
        let rest = text.dropFirst(prefix.count)
        let parts = rest.split(separator: ",", maxSplits: 1, omittingEmptySubsequences: false)
        guard let pidText = parts.first else { return nil }
        let trimmedPid = pidText.trimmingCharacters(in: .whitespaces)
        guard let pid = Int32(trimmedPid), pid >= 0, String(pid) == trimmedPid else { return nil }
        let name = parts.count > 1
            ? parts[1].trimmingCharacters(in: .whitespacesAndNewlines)
            : ""
        return (pid, name.isEmpty ? nil : String(name))
    }

    /// Nil means the time could not be read. An empty list is not a real zero.
    private static func accumulatedTime(_ value: Any?) -> UInt64? {
        guard let value, let entries = usageEntries(from: value), !entries.isEmpty else { return nil }
        var total: UInt64 = 0
        for entry in entries {
            guard let time = nanoseconds(from: entry[timeKey]) else { return nil }
            let (next, overflow) = total.addingReportingOverflow(time)
            guard !overflow else { return nil }
            total = next
        }
        return total
    }

    private static func usageEntries(from value: Any) -> [[String: Any]]? {
        if let entries = value as? [[String: Any]] { return entries }
        let items: [Any]
        if let list = value as? [Any] {
            items = list
        } else if let list = value as? NSArray {
            items = list.compactMap { $0 }
        } else {
            return nil
        }
        var entries: [[String: Any]] = []
        for item in items {
            guard let entry = dictionary(from: item) else { return nil }
            entries.append(entry)
        }
        return entries
    }

    private static func dictionary(from value: Any) -> [String: Any]? {
        if let dict = value as? [String: Any] { return dict }
        guard let dict = value as? NSDictionary else { return nil }
        var fields: [String: Any] = [:]
        for (key, item) in dict {
            guard let name = key as? String else { continue }
            fields[name] = item
        }
        return fields
    }

    private static func nanoseconds(from value: Any?) -> UInt64? {
        guard let value else { return nil }
        if value is Bool { return nil }
        if let number = value as? UInt64 { return number }
        if let number = value as? UInt { return UInt64(exactly: number) }
        if let number = value as? UInt32 { return UInt64(number) }
        if let number = value as? Int { return whole(number) }
        if let number = value as? Int32 { return whole(Int(number)) }
        if let number = value as? Int64 { return whole(number) }
        if let number = value as? Double { return whole(number) }
        if let number = value as? NSNumber {
            return whole(number.doubleValue)
        }
        return nil
    }

    private static func whole(_ value: Int) -> UInt64? {
        guard value >= 0 else { return nil }
        return UInt64(value)
    }

    private static func whole(_ value: Int64) -> UInt64? {
        guard value >= 0 else { return nil }
        return UInt64(value)
    }

    private static func whole(_ value: Double) -> UInt64? {
        guard value.isFinite, value >= 0, value <= Double(UInt64.max), value == value.rounded() else {
            return nil
        }
        return UInt64(value)
    }
}

enum GPUShareCopy {
    static let title = "GPU 占比"
    static let pulse = "Pulse"
    static let missing = "读不到 GPU 占比"
    static let limit = 5
}

/// Missing is the whole card. Rows are the ranked processes, never a list of zeros.
enum GPUSharePresentation: Equatable, Sendable {
    case missing
    case rows([GPUShareRow])
}

struct GPUShareRow: Equatable, Sendable, Identifiable {
    var pid: Int32
    var name: String
    var percent: Double?
    var shareText: String
    var bundleIdentifier: String?
    var executablePath: String?
    var id: Int32 { pid }
}

struct GPUShareBaseline: Equatable, Sendable {
    var sampledAt: Date
    var clients: [GPUShareClientSample]
}

struct GPUShareStep: Equatable, Sendable {
    /// False keeps the card and the baseline already published.
    var publish: Bool
    var card: GPUSharePresentation
    var baseline: GPUShareBaseline?
}

enum GPUShareProjection {
    static func step(
        clients: [GPUShareClientSample],
        rows: [ProcessRow],
        ownPid: Int32,
        sampledAt: Date,
        baseline: GPUShareBaseline?
    ) -> GPUShareStep {
        if clients.isEmpty {
            return GPUShareStep(publish: true, card: .missing, baseline: nil)
        }
        guard let baseline else {
            return GPUShareStep(
                publish: true,
                card: .rows([]),
                baseline: GPUShareBaseline(sampledAt: sampledAt, clients: clients)
            )
        }
        let elapsed = sampledAt.timeIntervalSince(baseline.sampledAt)
        let nanos = elapsed * 1_000_000_000
        guard elapsed > 0, nanos.isFinite, nanos >= 1, nanos <= Double(UInt64.max) else {
            return GPUShareStep(publish: false, card: .rows([]), baseline: baseline)
        }
        let readings = GPUShareDecoder.shares(
            previous: baseline.clients,
            current: clients,
            elapsedNanoseconds: UInt64(nanos.rounded())
        )
        return GPUShareStep(
            publish: true,
            card: .rows(rank(readings, rows: rows, ownPid: ownPid)),
            baseline: GPUShareBaseline(sampledAt: sampledAt, clients: clients)
        )
    }

    /// Numeric percents descending, then nils. Pulse stays in the list and is labeled here.
    private static func rank(
        _ readings: [GPUShareReading],
        rows: [ProcessRow],
        ownPid: Int32
    ) -> [GPUShareRow] {
        let ordered = readings.sorted { lhs, rhs in
            switch (lhs.percent, rhs.percent) {
            case let (left?, right?) where left != right:
                return left > right
            case (.some, .some), (.none, .none):
                return lhs.pid < rhs.pid
            case (.some, .none):
                return true
            case (.none, .some):
                return false
            }
        }
        return ordered.prefix(GPUShareCopy.limit).map { reading in
            let row = rows.first { $0.pid == reading.pid }
            return GPUShareRow(
                pid: reading.pid,
                name: displayName(pid: reading.pid, row: row, creatorName: reading.creatorName, ownPid: ownPid),
                percent: reading.percent,
                shareText: reading.text,
                bundleIdentifier: row?.bundleIdentifier,
                executablePath: row?.executablePath
            )
        }
    }

    private static func displayName(
        pid: Int32,
        row: ProcessRow?,
        creatorName: String?,
        ownPid: Int32
    ) -> String {
        if pid == ownPid { return GPUShareCopy.pulse }
        if let name = row?.name, !name.isEmpty { return name }
        if let creatorName, !creatorName.isEmpty { return creatorName }
        return String(pid)
    }
}
