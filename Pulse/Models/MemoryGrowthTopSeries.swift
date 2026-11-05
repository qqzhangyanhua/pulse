import Foundation

/// Shared `ChartSample` ring. Same 90-point window as the selected-pid detail series.
enum ChartSampleRing {
    static let limit = 90

    static func append(
        _ value: Double,
        at date: Date,
        id: UInt64,
        to series: inout [ChartSample],
        limit: Int = limit
    ) {
        series.append(ChartSample(id: id, date: date, value: value))
        if series.count > limit {
            series.removeFirst(series.count - limit)
        }
    }
}

/// Current memory-page sort Top N=5. Hard cap; not the viewport and not the name filter.
enum MemoryGrowthTopSeries {
    static let pidLimit = 5
    static let seriesLimit = ChartSampleRing.limit

    static func pids(from rows: [ProcessRow], sort: ProcessTableSort) -> [Int32] {
        Array(sort.ordered(rows).prefix(pidLimit).map(\.pid))
    }
}

/// Bounded per-pid memory series. A pid that leaves Top 5 is dropped this turn.
struct MemoryGrowthTopStore: Equatable, Sendable {
    private(set) var seriesByPid: [Int32: [ChartSample]] = [:]

    func series(for pid: Int32) -> [ChartSample]? {
        seriesByPid[pid]
    }

    /// Seed a Top 5 pid with the selected-pid detail ring so entering Top 5
    /// does not truncate an already-growing sidebar series. Does not append.
    mutating func adopt(pid: Int32, series: [ChartSample]) {
        seriesByPid[pid] = series
    }

    /// Drop anything not in the capped Top 5. Does not append a sample.
    mutating func retain(only topPids: [Int32]) {
        let kept = Set(Array(topPids.prefix(MemoryGrowthTopSeries.pidLimit)))
        for pid in seriesByPid.keys where !kept.contains(pid) {
            seriesByPid.removeValue(forKey: pid)
        }
    }

    /// One sample tick. Caps at 5, drops fallen pids, appends one point per remaining pid.
    mutating func advance(
        values: [Int32: Double],
        topPids: [Int32],
        at date: Date,
        nextSampleID: inout UInt64
    ) {
        let kept = Array(topPids.prefix(MemoryGrowthTopSeries.pidLimit))
        retain(only: kept)
        for pid in kept {
            guard let value = values[pid] else {
                seriesByPid.removeValue(forKey: pid)
                continue
            }
            var series = seriesByPid[pid] ?? []
            ChartSampleRing.append(
                value,
                at: date,
                id: nextSampleID,
                to: &series,
                limit: MemoryGrowthTopSeries.seriesLimit
            )
            nextSampleID += 1
            seriesByPid[pid] = series
        }
    }
}
