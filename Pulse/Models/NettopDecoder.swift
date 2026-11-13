import Foundation

/// One process's cumulative `bytes_in` / `bytes_out`. Nil is a missing field, not zero.
struct ProcessNetworkByteCounts: Equatable, Sendable {
    var downloadBytes: UInt64?
    var uploadBytes: UInt64?
}

/// Bytes per second for the network-page columns. Nil displays 「—」 and is not zero.
struct ProcessNetworkRate: Equatable, Sendable {
    var downloadBytesPerSecond: Double?
    var uploadBytesPerSecond: Double?
}

/// One decoded nettop CSV sample. An unreadable header is not an empty zero table.
enum NettopSample: Equatable, Sendable {
    case counts([Int32: ProcessNetworkByteCounts])
    case unreadable
}

/// Fixed `nettop` invocation. The Darwin reader uses these values and does not build a shell command.
enum NettopCommand {
    static let executablePath = "/usr/bin/nettop"
    static let arguments = ["-P", "-x", "-c", "-L", "0", "-s", "1", "-n", "-J", "bytes_in,bytes_out"]
}

/// Pure `nettop -L` CSV decode. A bad line or a missing byte field stays nil.
enum NettopDecoder {
    static func decode(_ text: String) -> NettopSample {
        var downloadIndex: Int?
        var uploadIndex: Int?
        var rows: [Int32: ProcessNetworkByteCounts] = [:]
        var sawHeader = false
        for line in text.split(whereSeparator: \.isNewline) {
            let fields = split(String(line))
            if !sawHeader {
                guard let download = fields.firstIndex(of: "bytes_in"),
                      let upload = fields.firstIndex(of: "bytes_out")
                else { return .unreadable }
                downloadIndex = download
                uploadIndex = upload
                sawHeader = true
                continue
            }
            guard let downloadIndex, let uploadIndex else { return .unreadable }
            guard let pid = pid(from: fields.first ?? "") else { continue }
            rows[pid] = ProcessNetworkByteCounts(
                downloadBytes: byteCount(fields, at: downloadIndex),
                uploadBytes: byteCount(fields, at: uploadIndex)
            )
        }
        guard sawHeader, downloadIndex != nil, uploadIndex != nil else { return .unreadable }
        return .counts(rows)
    }

    static func isByteHeader(_ line: String) -> Bool {
        let fields = split(line)
        return fields.contains("bytes_in") && fields.contains("bytes_out")
    }

    private static func split(_ line: String) -> [String] {
        line.split(separator: ",", omittingEmptySubsequences: false).map {
            $0.trimmingCharacters(in: .whitespaces)
        }
    }

    private static func byteCount(_ fields: [String], at index: Int) -> UInt64? {
        guard fields.indices.contains(index) else { return nil }
        let text = fields[index]
        guard !text.isEmpty, text.allSatisfy({ $0.isASCII && $0.isNumber }) else { return nil }
        return UInt64(text)
    }

    /// Pid is the trailing integer of `name.pid`. A name may contain dots.
    private static func pid(from label: String) -> Int32? {
        guard let dot = label.lastIndex(of: ".") else { return nil }
        let suffix = label[label.index(after: dot)...]
        guard !suffix.isEmpty, suffix.allSatisfy({ $0.isASCII && $0.isNumber }) else { return nil }
        return Int32(suffix)
    }
}

/// Cumulative counters to bytes per second. The first sample has no previous counts.
enum ProcessNetworkRateMath {
    static func perSecond(
        previous: [Int32: ProcessNetworkByteCounts],
        current: [Int32: ProcessNetworkByteCounts],
        elapsedSeconds: Double
    ) -> [Int32: ProcessNetworkRate]? {
        guard elapsedSeconds.isFinite, elapsedSeconds > 0 else { return nil }
        var rates: [Int32: ProcessNetworkRate] = [:]
        for (pid, counts) in current {
            let before = previous[pid]
            rates[pid] = ProcessNetworkRate(
                downloadBytesPerSecond: direction(before?.downloadBytes, counts.downloadBytes, elapsed: elapsedSeconds),
                uploadBytesPerSecond: direction(before?.uploadBytes, counts.uploadBytes, elapsed: elapsedSeconds)
            )
        }
        return rates
    }

    private static func direction(_ before: UInt64?, _ after: UInt64?, elapsed: Double) -> Double? {
        guard let before, let after, after >= before else { return nil }
        return Double(after - before) / elapsed
    }
}

/// Splits a streaming log into one CSV sample at a time.
struct NettopSampleFramer: Equatable {
    private var lines: [String] = []
    private var sawHeader = false

    mutating func append(_ line: String) -> String? {
        if NettopDecoder.isByteHeader(line) {
            let finished = finishIfData()
            lines = [line]
            sawHeader = true
            return finished
        }
        if line.trimmingCharacters(in: .whitespaces).isEmpty {
            return finishIfData()
        }
        guard sawHeader else { return nil }
        lines.append(line)
        return nil
    }

    private mutating func finishIfData() -> String? {
        guard sawHeader, lines.count > 1 else {
            lines = []
            sawHeader = false
            return nil
        }
        let sample = lines.joined(separator: "\n")
        lines = []
        sawHeader = false
        return sample
    }
}

/// Network-page order. Missing download or upload sorts last in both directions.
enum ProcessNetworkTable {
    static func ordered(
        _ rows: [ProcessRow],
        rates: [Int32: ProcessNetworkRate],
        sort: ProcessTableSort
    ) -> [ProcessRow] {
        switch sort.column {
        case .networkDownload:
            return ordered(rows, sort: sort) { rates[$0.pid]?.downloadBytesPerSecond }
        case .networkUpload:
            return ordered(rows, sort: sort) { rates[$0.pid]?.uploadBytesPerSecond }
        case .name, .cpu, .memory, .threads, .disk, .diskRead, .diskWrite, .energy, .wakeups:
            return sort.ordered(rows)
        }
    }

    private static func ordered(
        _ rows: [ProcessRow],
        sort: ProcessTableSort,
        value: (ProcessRow) -> Double?
    ) -> [ProcessRow] {
        rows.sorted { lhs, rhs in
            switch (value(lhs), value(rhs)) {
            case (nil, nil):
                return lhs.pid < rhs.pid
            case (nil, .some):
                return false
            case (.some, nil):
                return true
            case let (lhsValue?, rhsValue?):
                if lhsValue != rhsValue {
                    return sort.descending ? lhsValue > rhsValue : lhsValue < rhsValue
                }
                return lhs.pid < rhs.pid
            }
        }
    }
}
