import Foundation

/// Per-process network detail has no byte source. The case carries no rate.
enum ProcessNetworkDetailNotice: Equatable, Sendable {
    case unavailable
}

struct MemoryExistingProjection: Equatable, Sendable {
    let pid: Int32
    let memoryBytes: UInt64
    let memorySeries: [ChartSample]
    let cpuSeries: [ChartSample]
}

struct CPUDetailProjection: Equatable, Sendable {
    let pid: Int32
    let cpuPercent: Double?
    let cpuSeries: [ChartSample]
    let memory: MemoryDetailFieldCopy
    let memoryBytes: UInt64
    let memorySeries: [ChartSample]
    let energyWatts: Double?
    let wakeupsPerSecond: Double?
    let energyReadingIsPartial: Bool
    let wakeupReadingIsPartial: Bool
}

struct NetworkDetailProjection: Equatable, Sendable {
    let pid: Int32
    let notice: ProcessNetworkDetailNotice
    let cpuPercent: Double?
    let memory: MemoryDetailFieldCopy
    let memoryBytes: UInt64
    let memorySeries: [ChartSample]
}

struct DiskDetailProjection: Equatable, Sendable {
    let pid: Int32
    let readBytesPerSecond: Double?
    let writeBytesPerSecond: Double?
    let cpuPercent: Double?
    let memory: MemoryDetailFieldCopy
    let memoryBytes: UInt64
    let memorySeries: [ChartSample]
}

struct NoResourceUpgradeProjection: Equatable, Sendable {
    let pid: Int32
    let cpuPercent: Double?
    let memory: MemoryDetailFieldCopy
    let memoryBytes: UInt64
    let memorySeries: [ChartSample]
}

enum ResourceDetailProjection: Equatable, Sendable {
    case memoryExisting(MemoryExistingProjection)
    case cpu(CPUDetailProjection)
    case network(NetworkDetailProjection)
    case disk(DiskDetailProjection)
    case noResourceUpgrade(NoResourceUpgradeProjection)
}

/// Page projection of fields that already exist on `ProcessDetail`.
/// Live totals and frozen semantics are chosen by the caller; this type does not cache them.
enum ResourceDetailPageProjection {
    static let processNetworkUnavailable = "当前进程网络暂不可用"

    /// Frozen semantics win, including a nil denominator. A pid mismatch does not
    /// fall through to the live snapshot. Nil and zero live totals stay unknown.
    static func memoryTotal(
        detailPid: Int32,
        physicalTotalBytes: UInt64?,
        frozen: FrozenMemoryFieldSemantics?
    ) -> UInt64? {
        if let frozen {
            guard frozen.pid == detailPid else { return nil }
            guard let total = frozen.physicalTotalBytes, total > 0 else { return nil }
            return total
        }
        guard let physicalTotalBytes, physicalTotalBytes > 0 else { return nil }
        return physicalTotalBytes
    }

    static func project(
        page: DashboardPage,
        detail: ProcessDetail,
        physicalTotalBytes: UInt64?,
        frozen: FrozenMemoryFieldSemantics?
    ) -> ResourceDetailProjection {
        switch page {
        case .memory:
            return .memoryExisting(
                MemoryExistingProjection(
                    pid: detail.row.pid,
                    memoryBytes: detail.row.memoryBytes,
                    memorySeries: detail.memorySeries,
                    cpuSeries: detail.cpuSeries
                )
            )
        case .cpu:
            return .cpu(
                CPUDetailProjection(
                    pid: detail.row.pid,
                    cpuPercent: detail.row.cpuPercent,
                    cpuSeries: detail.cpuSeries,
                    memory: memoryCopy(
                        page: page,
                        detail: detail,
                        physicalTotalBytes: physicalTotalBytes,
                        frozen: frozen
                    ),
                    memoryBytes: detail.row.memoryBytes,
                    memorySeries: detail.memorySeries,
                    energyWatts: detail.row.energyWatts,
                    wakeupsPerSecond: detail.row.wakeupsPerSecond,
                    energyReadingIsPartial: detail.row.energyReadingIsPartial,
                    wakeupReadingIsPartial: detail.row.wakeupReadingIsPartial
                )
            )
        case .network:
            return .network(
                NetworkDetailProjection(
                    pid: detail.row.pid,
                    notice: .unavailable,
                    cpuPercent: detail.row.cpuPercent,
                    memory: memoryCopy(
                        page: page,
                        detail: detail,
                        physicalTotalBytes: physicalTotalBytes,
                        frozen: frozen
                    ),
                    memoryBytes: detail.row.memoryBytes,
                    memorySeries: detail.memorySeries
                )
            )
        case .disk:
            return .disk(
                DiskDetailProjection(
                    pid: detail.row.pid,
                    readBytesPerSecond: detail.row.diskReadBytesPerSecond,
                    writeBytesPerSecond: detail.row.diskWriteBytesPerSecond,
                    cpuPercent: detail.row.cpuPercent,
                    memory: memoryCopy(
                        page: page,
                        detail: detail,
                        physicalTotalBytes: physicalTotalBytes,
                        frozen: frozen
                    ),
                    memoryBytes: detail.row.memoryBytes,
                    memorySeries: detail.memorySeries
                )
            )
        case .gpu, .machine, .energy:
            return .noResourceUpgrade(
                NoResourceUpgradeProjection(
                    pid: detail.row.pid,
                    cpuPercent: detail.row.cpuPercent,
                    memory: memoryCopy(
                        page: page,
                        detail: detail,
                        physicalTotalBytes: physicalTotalBytes,
                        frozen: frozen
                    ),
                    memoryBytes: detail.row.memoryBytes,
                    memorySeries: detail.memorySeries
                )
            )
        }
    }

    private static func memoryCopy(
        page: DashboardPage,
        detail: ProcessDetail,
        physicalTotalBytes: UInt64?,
        frozen: FrozenMemoryFieldSemantics?
    ) -> MemoryDetailFieldCopy {
        MemoryDetailPresentation.field(
            page: page,
            part: detail.row.memoryBytes,
            total: memoryTotal(
                detailPid: detail.row.pid,
                physicalTotalBytes: physicalTotalBytes,
                frozen: frozen
            )
        )
    }
}
