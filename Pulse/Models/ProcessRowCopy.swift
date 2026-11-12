import Foundation

/// One tab-separated process-table line. The view writes the pasteboard.
enum ProcessRowCopy {
    static func line(
        page: DashboardPage,
        row: ProcessRow,
        energyWindow: ProcessEnergyRates? = nil
    ) -> String {
        switch page {
        case .memory:
            return joined(prefix(row) + [threads(row)])
        case .cpu:
            return joined(prefix(row) + [
                ProcessEnergyText.watts(row.energyWatts),
                ProcessEnergyText.wakeups(row.wakeupsPerSecond),
                threads(row),
            ])
        case .energy:
            _ = energyWindow
            return joined(prefix(row) + [
                ProcessEnergyText.watts(row.energyWatts),
                ProcessEnergyText.wakeups(row.wakeupsPerSecond),
                threads(row),
            ])
        case .disk:
            return joined(prefix(row) + [
                DiskRateText.string(row.diskReadBytesPerSecond),
                DiskRateText.string(row.diskWriteBytesPerSecond),
                threads(row),
            ])
        case .network:
            return joined(prefix(row) + [row.networkAvailability.label, threads(row)])
        case .machine, .gpu:
            return ""
        }
    }

    private static func prefix(_ row: ProcessRow) -> [String] {
        [
            row.name,
            row.groupedMemberCount.map(String.init) ?? String(row.pid),
            CPUPercentText.string(row.cpuPercent),
            ByteFormat.memory(row.memoryBytes),
        ]
    }

    private static func threads(_ row: ProcessRow) -> String {
        String(row.threadCount)
    }

    private static func joined(_ fields: [String]) -> String {
        fields.joined(separator: "\t")
    }
}
