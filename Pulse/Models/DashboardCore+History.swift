import Foundation

extension DashboardCore {
    /// Copies this successful tick. A missing GPU read stays nil, including when the page still shows an older percent.
    mutating func noteHistory(_ frame: SampledFrame) {
        let pressure = frame.snapshot.pressure
        var events = pendingHistoryEvents
        events.append(contentsOf: HistoryPolicy.events(
            previousPressure: lastHistoryPressure,
            pressure: pressure,
            thermal: nil,
            previousThermal: nil,
            lifecycle: nil
        ))
        pendingHistoryEvents = []
        lastHistoryPressure = pressure
        let gpuPercent = frame.gpuNodes == nil ? nil : gpuPage.utilizationPercent
        let capturedAt = frame.snapshot.capturedAt
        let retention = historyRetention
        historyDraft = HistoryDraft(
            sample: HistorySample(
                at: capturedAt,
                usedBytes: frame.snapshot.usedBytes,
                pressure: pressure,
                swapUsedBytes: frame.snapshot.swapUsedBytes,
                cpuPercent: frame.systemCpuPercent,
                networkInBytesPerSecond: frame.hostNetworkRates.inboundBytesPerSecond,
                networkOutBytesPerSecond: frame.hostNetworkRates.outboundBytesPerSecond,
                diskReadBytesPerSecond: frame.hostDiskRates.readBytesPerSecond,
                diskWriteBytesPerSecond: frame.hostDiskRates.writeBytesPerSecond,
                gpuPercent: gpuPercent
            ),
            top: HistoryPolicy.topProcesses(
                frame.rows.map {
                    HistoryProcessCandidate(pid: $0.pid, name: $0.name, primary: $0.cpuPercent)
                },
                limit: 10
            ),
            events: events,
            dropRawBefore: HistoryPolicy.dropRaw(before: capturedAt),
            dropMinuteBefore: HistoryPolicy.minuteDrop(before: capturedAt, retention: retention),
            retentionCutoff: HistoryPolicy.retentionCutoff(retention, now: capturedAt)
        )
    }

    /// The adapter writes this, then the published core no longer holds it.
    mutating func consumeHistoryDraft() -> HistoryDraft? {
        let draft = historyDraft
        historyDraft = nil
        return draft
    }

    /// Records the condition itself. Nominal, fair, and unknown stay events even when the notice is hidden.
    mutating func noteHistoryThermal(_ condition: ThermalCondition) {
        let name: String
        switch condition {
        case .nominal:
            name = "nominal"
        case .fair:
            name = "fair"
        case .serious:
            name = "serious"
        case .critical:
            name = "critical"
        case .unknown:
            name = "unknown"
        }
        pendingHistoryEvents.append(contentsOf: HistoryPolicy.events(
            previousPressure: nil,
            pressure: nil,
            thermal: name,
            previousThermal: lastHistoryThermalName,
            lifecycle: nil
        ))
        lastHistoryThermalName = name
    }
}
