import Foundation

/// Portable machine-page overview. It does not sample, store history, or read the host.
enum MachineOverview {
    enum Page: Equatable {
        case memory
        case cpu
    }

    struct Card: Equatable {
        var title: String
        /// Nil while the first read is still in flight. An em dash is a real missing value.
        var value: String? = nil
        var caption: String? = nil
        /// Point difference from the previous CPU sample. Nil when it cannot be stated.
        var delta: String? = nil
        /// The input series once it has two points. Nil hides the line.
        var series: [ChartSample]? = nil
        var seriesNote: String? = nil
        /// Nil hides the battery bar. Zero is an empty battery.
        var batteryPercent: Int? = nil
        /// Nil is not a button.
        var page: Page? = nil
    }

    struct Ring: Equatable {
        enum Tone: Equatable {
            case sampling
            case missing
            case normal
            case elevated
        }

        var tone: Tone
        /// Nil while sampling. Never a 0–100 score.
        var label: String?
        var page: Page
    }

    struct Diagnostic: Equatable {
        var title: String
        var status: String
        var page: Page?
    }

    struct Identity: Equatable {
        var title: String
        var loading: Bool
        var model: String?
        var chip: String?
        var system: String?
        var capacity: String?
    }

    struct Model: Equatable {
        var identity: Identity
        var ring: Ring
        var cpu: Card
        var memory: Card
        var disk: Card
        var power: Card
        var uptime: Card
        var swap: Card
        /// Nil hides the cycle / health / power block. A desktop Mac stays nil.
        var battery: Battery?
        var liveUpdate: String
        var diagnostics: [Diagnostic]
        var thermalNotice: String?
    }

    struct Battery: Equatable {
        var cycles: String
        var health: String
        var power: String
    }

    static func project(
        facts: MachineFacts?,
        snapshot: MemorySnapshot?,
        loadState: LoadState,
        cpuPercent: Double?,
        cpuSeries: [ChartSample],
        memorySeries: [ChartSample],
        thermalNotice: String?,
        calendar: Calendar = .current
    ) -> Model {
        let cpuCell = MachineStatusCopy.cpu(snapshot: snapshot, loadState: loadState, percent: cpuPercent)
        let memoryCell = MachineStatusCopy.usedMemory(snapshot: snapshot, loadState: loadState)
        let swapCell = MachineStatusCopy.swap(snapshot: snapshot, loadState: loadState)
        let cpuBound = boundSeries(cpuSeries, currentMissing: cpuPercent == nil)
        let memoryBound = boundSeries(memorySeries, currentMissing: snapshot == nil)
        return Model(
            identity: identity(facts),
            ring: ring(snapshot: snapshot, loadState: loadState),
            cpu: Card(
                title: "CPU",
                value: cpuCell.value,
                caption: cpuCell.caption,
                delta: cpuDelta(percent: cpuPercent, series: cpuSeries),
                series: cpuBound.series,
                seriesNote: cpuBound.note,
                page: .cpu
            ),
            memory: Card(
                title: "内存",
                value: memoryCell.value,
                caption: memoryCell.caption,
                series: memoryBound.series,
                seriesNote: memoryBound.note,
                page: .memory
            ),
            disk: disk(facts),
            power: power(facts),
            uptime: uptime(facts, calendar: calendar),
            swap: Card(title: "交换", value: swapCell.value, caption: swapCell.caption, page: .memory),
            battery: battery(facts?.battery),
            liveUpdate: liveUpdate(snapshot: snapshot, loadState: loadState, calendar: calendar),
            diagnostics: diagnostics(
                facts: facts,
                snapshot: snapshot,
                loadState: loadState,
                cpuPercent: cpuPercent
            ),
            thermalNotice: MachinePageCopy.thermalLine(thermalNotice)
        )
    }

    /// The newest point has to be this reading. An older sample is not "较上次".
    private static func cpuDelta(percent: Double?, series: [ChartSample]) -> String? {
        guard let percent, series.count >= 2, series.last?.value == percent else { return nil }
        let delta = percent - series[series.count - 2].value
        let plain = String(format: "%.1f", locale: posix, delta)
        if plain == "0.0" || plain == "-0.0" {
            return "较上次 0.0%"
        }
        let signed = String(format: "%+.1f", locale: posix, delta)
        return "较上次 \(signed)%"
    }

    private static func boundSeries(
        _ series: [ChartSample],
        currentMissing: Bool
    ) -> (series: [ChartSample]?, note: String?) {
        guard series.count >= 2 else { return (nil, nil) }
        let note = currentMissing ? HistoryCurvePresentation.unavailable : nil
        return (series, note)
    }

    private static func identity(_ facts: MachineFacts?) -> Identity {
        guard let facts else {
            return Identity(title: "这台 Mac", loading: true, model: nil, chip: nil, system: nil, capacity: nil)
        }
        return Identity(
            title: "这台 Mac",
            loading: false,
            model: MachinePageCopy.modelValue(facts.modelName),
            chip: MachinePageCopy.chipValue(facts.chipName),
            system: MachinePageCopy.osValue(facts.os),
            capacity: MachinePageCopy.capacityLine(
                coreCount: facts.coreCount,
                physicalMemoryBytes: facts.physicalMemoryBytes
            )
        )
    }

    private static func ring(snapshot: MemorySnapshot?, loadState: LoadState) -> Ring {
        switch MachineStatusCopy.phase(snapshot: snapshot, loadState: loadState) {
        case .sampling:
            return Ring(tone: .sampling, label: nil, page: .memory)
        case .missing:
            return Ring(tone: .missing, label: MachineStatusCopy.missingValue, page: .memory)
        case .ready:
            switch snapshot?.pressure {
            case .elevated:
                return Ring(tone: .elevated, label: PressureLevel.elevated.title, page: .memory)
            case .normal:
                return Ring(tone: .normal, label: PressureLevel.normal.title, page: .memory)
            case nil:
                return Ring(tone: .missing, label: MachineStatusCopy.missingValue, page: .memory)
            }
        }
    }

    private static func disk(_ facts: MachineFacts?) -> Card {
        guard let facts else { return Card(title: "磁盘") }
        let volume = facts.volume
        let value = usedBytes(available: volume.availableBytes, total: volume.totalBytes)
            .map { ByteFormat.memory($0) } ?? MachineStatusCopy.missingValue
        return Card(
            title: "磁盘",
            value: value,
            caption: MachinePageCopy.volumeCaption(
                available: volume.availableBytes,
                total: volume.totalBytes
            )
        )
    }

    private static func power(_ facts: MachineFacts?) -> Card {
        guard let facts else { return Card(title: "电源") }
        let power = facts.power
        return Card(
            title: "电源",
            value: MachinePageCopy.powerValue(source: power.source, percent: power.batteryPercent),
            caption: MachinePageCopy.powerCaption(
                source: power.source,
                percent: power.batteryPercent,
                lowPowerMode: power.lowPowerMode
            ),
            batteryPercent: batteryPercent(power)
        )
    }

    private static func batteryPercent(_ power: MachinePower) -> Int? {
        guard power.source != .unknown, let percent = power.batteryPercent, percent >= 0 else { return nil }
        return percent
    }

    private static func battery(_ reading: MachineBattery?) -> Battery? {
        guard let reading else { return nil }
        let ratio = BatteryMath.healthPercent(
            fullChargeCapacity: reading.fullChargeCapacity,
            designCapacity: reading.designCapacity
        )
        let watts = BatteryMath.powerWatts(millivolts: reading.millivolts, milliamps: reading.milliamps)
        return Battery(cycles: cycleText(reading.cycleCount), health: healthText(ratio), power: wattText(watts))
    }

    private static func cycleText(_ count: Int?) -> String {
        guard let count else { return MachineStatusCopy.missingValue }
        return "\(count)"
    }

    private static func healthText(_ ratio: Double?) -> String {
        guard let ratio else { return MachineStatusCopy.missingValue }
        return "\(Int((ratio * 100).rounded()))%"
    }

    private static func wattText(_ watts: Double?) -> String {
        guard let watts else { return MachineStatusCopy.missingValue }
        let text = String(format: "%.1f W", locale: posix, watts)
        return text == "-0.0 W" ? "0.0 W" : text
    }

    private static func uptime(_ facts: MachineFacts?, calendar: Calendar) -> Card {
        guard let facts else { return Card(title: "已开机") }
        return Card(
            title: "已开机",
            value: MachinePageCopy.uptimeValue(facts.uptime),
            caption: MachinePageCopy.bootCaption(facts.bootedAt, calendar: calendar)
        )
    }

    private static func diagnostics(
        facts: MachineFacts?,
        snapshot: MemorySnapshot?,
        loadState: LoadState,
        cpuPercent: Double?
    ) -> [Diagnostic] {
        [
            Diagnostic(
                title: "内存压力",
                status: memoryStatus(snapshot: snapshot, loadState: loadState),
                page: .memory
            ),
            Diagnostic(title: "磁盘空间", status: diskStatus(facts?.volume), page: nil),
            Diagnostic(title: "CPU 负载", status: cpuStatus(cpuPercent), page: .cpu),
        ]
    }

    private static func memoryStatus(snapshot: MemorySnapshot?, loadState: LoadState) -> String {
        switch MachineStatusCopy.phase(snapshot: snapshot, loadState: loadState) {
        case .sampling:
            return MachineStatusCopy.samplingCaption
        case .missing:
            return MachineStatusCopy.missingCaption
        case .ready:
            return snapshot?.pressure.title ?? MachineStatusCopy.missingCaption
        }
    }

    private static func diskStatus(_ volume: MachineVolume?) -> String {
        guard let used = usedBytes(available: volume?.availableBytes, total: volume?.totalBytes),
              let total = volume?.totalBytes, total > 0 else {
            return MachineStatusCopy.missingCaption
        }
        let percent = (Double(used) / Double(total) * 100).rounded()
        return percent >= 90 ? PressureLevel.elevated.title : PressureLevel.normal.title
    }

    private static func usedBytes(available: UInt64?, total: UInt64?) -> UInt64? {
        guard let available, let total, total > 0, available <= total else { return nil }
        return total - available
    }

    private static func cpuStatus(_ percent: Double?) -> String {
        guard let percent else { return MachineStatusCopy.missingCaption }
        return percent >= 80 ? PressureLevel.elevated.title : PressureLevel.normal.title
    }

    private static func liveUpdate(
        snapshot: MemorySnapshot?,
        loadState: LoadState,
        calendar: Calendar
    ) -> String {
        if let snapshot {
            let parts = calendar.dateComponents([.hour, .minute, .second], from: snapshot.capturedAt)
            if let hour = parts.hour, let minute = parts.minute, let second = parts.second {
                return String(format: "实时更新 · %02d:%02d:%02d", hour, minute, second)
            }
        }
        if snapshot == nil, loadState == .sampling {
            return MachineStatusCopy.samplingCaption
        }
        return MachineStatusCopy.missingCaption
    }

    private static let posix = Locale(identifier: "en_US_POSIX")
}
