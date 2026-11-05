import Darwin
import Foundation

/// Background sampling actor. Snapshots are immutable value types; the main thread only reads them.
actor MemorySampler {
    private let seriesLimit = 90
    private var nextSampleID: UInt64 = 1
    private var pressureSeries: [ChartSample] = []
    private var selectedPid: Int32?
    private var selectedMemorySeries: [ChartSample] = []
    private var selectedCPUSeries: [ChartSample] = []
    private var cpuTicks: [Int32: CPUTick] = [:]
    private var previousHostCPU: HostCPUTicks?
    private var previousHostNetwork: HostNetworkSnapshot?
    private var identityCache: [Int32: ProcessIdentity] = [:]

    func setSelectedPid(_ pid: Int32?) {
        guard selectedPid != pid else { return }
        selectedPid = pid
        selectedMemorySeries.removeAll(keepingCapacity: true)
        selectedCPUSeries.removeAll(keepingCapacity: true)
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

        guard let rawProcesses = ProcessEnumerator.list() else {
            return .success(
                SampledFrame(
                    snapshot: snapshot,
                    rows: [],
                    detail: nil,
                    processListFailed: true,
                    systemCpuPercent: systemCpuPercent,
                    hostNetworkRates: hostNetworkRates
                )
            )
        }

        var nextTicks: [Int32: CPUTick] = [:]
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

            rows.append(
                ProcessRow(
                    pid: raw.pid,
                    name: identity.name,
                    bundleIdentifier: identity.bundleIdentifier,
                    executablePath: identity.path,
                    cpuPercent: cpu,
                    memoryBytes: raw.memoryBytes,
                    threadCount: raw.threadCount
                )
            )
        }

        cpuTicks = nextTicks
        identityCache = nextIdentities

        rows.sort { lhs, rhs in
            if lhs.memoryBytes != rhs.memoryBytes {
                return lhs.memoryBytes > rhs.memoryBytes
            }
            return lhs.pid < rhs.pid
        }

        let detail = detailFrame(from: rows, at: capturedAt)
        return .success(
            SampledFrame(
                snapshot: snapshot,
                rows: rows,
                detail: detail,
                processListFailed: false,
                systemCpuPercent: systemCpuPercent,
                hostNetworkRates: hostNetworkRates
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

    private func detailFrame(from rows: [ProcessRow], at date: Date) -> ProcessDetail? {
        guard let selectedPid,
              let row = rows.first(where: { $0.pid == selectedPid })
        else {
            return nil
        }

        append(Double(row.memoryBytes), at: date, to: &selectedMemorySeries)
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
        let sample = ChartSample(id: nextSampleID, date: date, value: value)
        nextSampleID += 1
        series.append(sample)
        if series.count > seriesLimit {
            series.removeFirst(series.count - seriesLimit)
        }
    }
}
