import Darwin
import Foundation

/// Background sampling actor. Snapshots are immutable value types; the main thread only reads them.
actor MemorySampler {
    private let seriesLimit = ChartSampleRing.limit
    private var nextSampleID: UInt64 = 1
    private var pressureSeries: [ChartSample] = []
    private var selectedPid: Int32?
    private var selectedMemorySeries: [ChartSample] = []
    private var selectedCPUSeries: [ChartSample] = []
    private var cpuTicks: [Int32: CPUTick] = [:]
    private var diskTicks: [Int32: DiskTick] = [:]
    private var previousHostCPU: HostCPUTicks?
    private var previousHostNetwork: HostNetworkSnapshot?
    private var previousHostDisk: HostDiskSnapshot?
    private var identityCache: [Int32: ProcessIdentity] = [:]
    /// Last memory-page table sort. Leaving memory does not follow CPU / disk sort.
    private var memoryPageSort = ProcessTableSort.defaultSort(for: .memory)
    private var lastRows: [ProcessRow] = []
    private var topMemoryStore = MemoryGrowthTopStore()

    func setSelectedPid(_ pid: Int32?) {
        guard selectedPid != pid else { return }
        selectedPid = pid
        selectedMemorySeries.removeAll(keepingCapacity: true)
        selectedCPUSeries.removeAll(keepingCapacity: true)
    }

    /// Memory-page sort only. A churning sort drops fallen Top 5 series immediately.
    func setMemoryPageSort(_ sort: ProcessTableSort) {
        guard memoryPageSort != sort else { return }
        memoryPageSort = sort
        topMemoryStore.retain(only: MemoryGrowthTopSeries.pids(from: lastRows, sort: sort))
    }

    func sample() -> Result<SampledFrame, HostMemoryError> {
        let host: RawHostMemory
        do {
            host = try HostMemoryReader.read()
        } catch let error as HostMemoryError {
            return .failure(error)
        } catch {
            return .failure(.statistics(KERN_FAILURE))
        }

        let capturedAt = Date()
        append(host.pressureMetric, at: capturedAt, to: &pressureSeries)

        let snapshot = MemorySnapshot(
            usedBytes: host.usedBytes,
            totalBytes: host.totalBytes,
            breakdown: MemoryBreakdown(
                appBytes: host.appBytes,
                wiredBytes: host.wiredBytes,
                compressedBytes: host.compressedBytes,
                cachedBytes: host.cachedBytes
            ),
            pressure: host.pressure,
            pressureMetric: host.pressureMetric,
            pressureSeries: pressureSeries,
            capturedAt: capturedAt
        )
        let systemCpuPercent = consumeSystemCPU()
        let hostNetworkRates = consumeSystemNetwork(at: capturedAt)
        let hostDiskRates = consumeSystemDisk(at: capturedAt)

        guard let rawProcesses = ProcessEnumerator.list() else {
            lastRows = []
            topMemoryStore.retain(only: [])
            return .success(
                SampledFrame(
                    snapshot: snapshot,
                    rows: [],
                    detail: nil,
                    processListFailed: true,
                    systemCpuPercent: systemCpuPercent,
                    hostNetworkRates: hostNetworkRates,
                    hostDiskRates: hostDiskRates,
                    topMemorySeries: topMemoryStore.seriesByPid
                )
            )
        }

        var nextTicks: [Int32: CPUTick] = [:]
        var nextDiskTicks: [Int32: DiskTick] = [:]
        var nextIdentities: [Int32: ProcessIdentity] = [:]
        var rows: [ProcessRow] = []
        rows.reserveCapacity(rawProcesses.count)

        for raw in rawProcesses {
            let identity = ProcessIdentityResolver.resolve(
                sample: raw,
                cached: identityCache[raw.pid]
            )
            nextIdentities[raw.pid] = identity

            let tick = CPUTick(
                userTimeNs: raw.userTimeNs,
                systemTimeNs: raw.systemTimeNs,
                date: capturedAt
            )
            let cpu = ProcessCPUPercent.percent(previous: cpuTicks[raw.pid], current: tick)
            nextTicks[raw.pid] = tick

            let diskReading: DiskTick?
            if let bytesRead = raw.diskBytesRead, let bytesWritten = raw.diskBytesWritten {
                diskReading = DiskTick(bytesRead: bytesRead, bytesWritten: bytesWritten, date: capturedAt)
            } else {
                diskReading = nil
            }
            let disk = ProcessDiskLoad.advance(previous: diskTicks[raw.pid], reading: diskReading)
            if let baseline = disk.baseline {
                nextDiskTicks[raw.pid] = baseline
            }

            rows.append(
                ProcessRow(
                    pid: raw.pid,
                    name: identity.name,
                    bundleIdentifier: identity.bundleIdentifier,
                    executablePath: identity.path,
                    cpuPercent: cpu,
                    memoryBytes: raw.memoryBytes,
                    threadCount: raw.threadCount,
                    diskReadBytesPerSecond: disk.rates.readBytesPerSecond,
                    diskWriteBytesPerSecond: disk.rates.writeBytesPerSecond
                )
            )
        }

        cpuTicks = nextTicks
        diskTicks = nextDiskTicks
        identityCache = nextIdentities

        rows.sort { lhs, rhs in
            if lhs.memoryBytes != rhs.memoryBytes {
                return lhs.memoryBytes > rhs.memoryBytes
            }
            return lhs.pid < rhs.pid
        }

        lastRows = rows
        let topPids = MemoryGrowthTopSeries.pids(from: rows, sort: memoryPageSort)
        if let selectedPid, topPids.contains(selectedPid), !selectedMemorySeries.isEmpty {
            topMemoryStore.adopt(pid: selectedPid, series: selectedMemorySeries)
        }
        var memoryValues: [Int32: Double] = [:]
        memoryValues.reserveCapacity(rows.count)
        for row in rows {
            memoryValues[row.pid] = Double(row.memoryBytes)
        }
        topMemoryStore.advance(
            values: memoryValues,
            topPids: topPids,
            at: capturedAt,
            nextSampleID: &nextSampleID
        )

        let detail = detailFrame(from: rows, at: capturedAt, topPids: topPids)
        return .success(
            SampledFrame(
                snapshot: snapshot,
                rows: rows,
                detail: detail,
                processListFailed: false,
                systemCpuPercent: systemCpuPercent,
                hostNetworkRates: hostNetworkRates,
                hostDiskRates: hostDiskRates,
                topMemorySeries: topMemoryStore.seriesByPid
            )
        )
    }

    private func consumeSystemCPU() -> Double? {
        let advanced = SystemCPULoad.advance(previous: previousHostCPU, reading: HostCPUReader.read())
        previousHostCPU = advanced.baseline
        return advanced.percent
    }

    private func consumeSystemNetwork(at date: Date) -> HostNetworkRates {
        let advanced = HostNetworkLoad.advance(
            previous: previousHostNetwork,
            reading: HostNetworkReader.read(at: date)
        )
        previousHostNetwork = advanced.baseline
        return advanced.rates
    }

    private func consumeSystemDisk(at date: Date) -> HostDiskRates {
        let advanced = HostDiskLoad.advance(
            previous: previousHostDisk,
            reading: HostDiskReader.read(at: date)
        )
        previousHostDisk = advanced.baseline
        return advanced.rates
    }

    private func detailFrame(from rows: [ProcessRow], at date: Date, topPids: [Int32]) -> ProcessDetail? {
        guard let selectedPid,
              let row = rows.first(where: { $0.pid == selectedPid })
        else {
            return nil
        }

        if topPids.contains(selectedPid), let shared = topMemoryStore.series(for: selectedPid) {
            selectedMemorySeries = shared
        } else {
            append(Double(row.memoryBytes), at: date, to: &selectedMemorySeries)
        }
        if let cpu = row.cpuPercent {
            append(cpu, at: date, to: &selectedCPUSeries)
        }

        return ProcessDetail(
            row: row,
            memorySeries: selectedMemorySeries,
            cpuSeries: selectedCPUSeries
        )
    }

    private func append(_ value: Double, at date: Date, to series: inout [ChartSample]) {
        ChartSampleRing.append(value, at: date, id: nextSampleID, to: &series, limit: seriesLimit)
        nextSampleID += 1
    }
}
