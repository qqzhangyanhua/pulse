import SwiftUI

struct ProcessLine: View {
    let row: ProcessRow
    var selected: Bool
    var showsNetwork: Bool
    var downloadBytesPerSecond: Double?
    var uploadBytesPerSecond: Double?
    var showsDisk: Bool
    var showsEnergy: Bool
    /// Phase-6 chip. Per-row Top5 ∩ `.rising`; selection is not a gate. Nil paints nothing.
    var growthBadge: MemoryGrowthListBadge?
    var paused = false
    var loweredPriority = false
    var onResume: () -> Void = {}
    var onRestorePriority: () -> Void = {}
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 0) {
            HStack(spacing: 8) {
                ProcessIconView(pid: row.pid, bundleIdentifier: row.bundleIdentifier, size: 16)
                Text(row.name)
                    .lineLimit(1)
                if paused {
                    PausedProcessMark { onResume() }
                }
                if loweredPriority {
                    LoweredPriorityMark { onRestorePriority() }
                }
                if let growthBadge {
                    MemoryGrowthRisingBadge(badge: growthBadge)
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            metric(ByteFormat.cpu(row.cpuPercent), dot: PulsePalette.chartCPU)
                .frame(width: ProcessColumn.cpu, alignment: .trailing)
            metric(ByteFormat.memory(row.memoryBytes), dot: PulsePalette.accent)
                .frame(width: ProcessColumn.memory, alignment: .trailing)
            if showsNetwork {
                diskCell(NetworkRateText.string(downloadBytesPerSecond))
                    .frame(width: ProcessColumn.networkRate, alignment: .trailing)
                    .accessibilityLabel("\(NetworkPageCopy.downloadTitle) \(NetworkRateText.string(downloadBytesPerSecond))")
                diskCell(NetworkRateText.string(uploadBytesPerSecond))
                    .frame(width: ProcessColumn.networkRate, alignment: .trailing)
                    .accessibilityLabel("\(NetworkPageCopy.uploadTitle) \(NetworkRateText.string(uploadBytesPerSecond))")
            }
            if showsDisk {
                diskCell(DiskRateText.string(row.diskReadBytesPerSecond))
                    .frame(width: ProcessColumn.disk, alignment: .trailing)
                diskCell(DiskRateText.string(row.diskWriteBytesPerSecond))
                    .frame(width: ProcessColumn.disk, alignment: .trailing)
            }
            if showsEnergy {
                diskCell(ProcessEnergyText.watts(row.energyWatts))
                    .frame(width: ProcessColumn.energy, alignment: .trailing)
                diskCell(ProcessEnergyText.wakeups(row.wakeupsPerSecond))
                    .frame(width: ProcessColumn.wakeups, alignment: .trailing)
            }
            Text("\(row.threadCount)")
                .monospacedDigit()
                .frame(width: ProcessColumn.threads, alignment: .trailing)
        }
        .font(.callout)
        .foregroundStyle(selected ? Color.white : Color.primary)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.16), value: selected)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
        .modifier(PauseResumeAction(enabled: paused, resume: onResume))
        .modifier(PriorityRestoreAction(enabled: loweredPriority, restore: onRestorePriority))
    }

    private var accessibilityLabel: String {
        var parts = [row.name]
        if paused {
            parts.append("已暂停")
        }
        if loweredPriority {
            parts.append("已降低优先级")
        }
        parts.append("CPU \(ByteFormat.cpu(row.cpuPercent))")
        parts.append("内存 \(ByteFormat.memory(row.memoryBytes))")
        if showsNetwork {
            parts.append("\(NetworkPageCopy.downloadTitle) \(NetworkRateText.string(downloadBytesPerSecond))")
            parts.append("\(NetworkPageCopy.uploadTitle) \(NetworkRateText.string(uploadBytesPerSecond))")
        }
        if showsDisk {
            parts.append("\(DiskPageCopy.readTitle) \(DiskRateText.string(row.diskReadBytesPerSecond))")
            parts.append("\(DiskPageCopy.writeTitle) \(DiskRateText.string(row.diskWriteBytesPerSecond))")
        }
        if showsEnergy {
            parts.append("\(ProcessEnergyText.impactTitle) \(ProcessEnergyText.watts(row.energyWatts))")
            parts.append("\(ProcessEnergyText.wakeTitle) \(ProcessEnergyText.wakeups(row.wakeupsPerSecond))")
        }
        if let growthBadge {
            parts.append(growthBadge.help)
        }
        parts.append("\(row.threadCount) 线程")
        return parts.joined(separator: "，")
    }

    private func diskCell(_ text: String) -> some View {
        Text(text)
            .monospacedDigit()
            .foregroundStyle(selected ? Color.white.opacity(0.88) : Color.primary)
    }

    private func metric(_ text: String, dot: Color) -> some View {
        HStack(spacing: 6) {
            Circle()
                .fill(dot)
                .frame(width: 6, height: 6)
            Text(text)
                .monospacedDigit()
        }
    }
}

/// Calm selected-row chip. Secondary ink only; no red, flash, or click-through.
private struct MemoryGrowthRisingBadge: View {
    let badge: MemoryGrowthListBadge

    var body: some View {
        Text(badge.title)
            .font(.caption2)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background(Color.secondary.opacity(0.14), in: Capsule())
            .help(badge.help)
            .accessibilityHidden(true)
            .layoutPriority(1)
    }
}
