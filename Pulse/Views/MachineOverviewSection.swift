import SwiftUI

/// Same overview band as the other resource pages: fixed-height cards, icon, large figure, one caption.
/// No chart and no process list. Those belong to the resource tabs.
struct MachineOverviewSection: View {
    @EnvironmentObject private var vm: MemoryDashboardVM

    var body: some View {
        Group {
            if let facts = vm.machineFacts {
                readyBody(facts)
            } else {
                loadingBody
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
    }

    private var accessibilityLabel: String {
        guard let facts = vm.machineFacts else { return "正在读取本机…" }
        return MachinePageCopy.accessibilityLabel(facts: facts, thermalNotice: vm.thermalNotice)
    }

    private var loadingBody: some View {
        HStack(spacing: 12) {
            ForEach(MachineCard.allCases) { card in
                MachineFactCard(
                    symbol: card.symbol,
                    title: card.title,
                    value: nil,
                    caption: card == .chip ? "正在读取本机…" : nil,
                    tint: card.tint
                )
            }
        }
        .frame(height: 172)
    }

    private func readyBody(_ facts: MachineFacts) -> some View {
        HStack(spacing: 12) {
            MachineFactCard(
                symbol: MachineCard.chip.symbol,
                title: MachineCard.chip.title,
                value: MachinePageCopy.chipValue(facts.chipName),
                caption: MachinePageCopy.osValue(facts.os),
                thermalNotice: vm.thermalNotice,
                tint: MachineCard.chip.tint
            )
            MachineFactCard(
                symbol: MachineCard.uptime.symbol,
                title: MachineCard.uptime.title,
                value: MachinePageCopy.uptimeValue(facts.uptime),
                caption: MachinePageCopy.uptimeLine(facts.uptime),
                tint: MachineCard.uptime.tint
            )
            MachineFactCard(
                symbol: MachineCard.power.symbol,
                title: MachineCard.power.title,
                value: MachinePageCopy.powerValue(
                    source: facts.power.source,
                    percent: facts.power.batteryPercent
                ),
                caption: MachinePageCopy.powerLine(
                    source: facts.power.source,
                    percent: facts.power.batteryPercent,
                    lowPowerMode: facts.power.lowPowerMode
                ),
                tint: MachineCard.power.tint
            )
            MachineFactCard(
                symbol: MachineCard.volume.symbol,
                title: MachineCard.volume.title,
                value: MachinePageCopy.volumeValue(
                    available: facts.volume.availableBytes,
                    total: facts.volume.totalBytes
                ),
                caption: MachinePageCopy.volumeLine(
                    available: facts.volume.availableBytes,
                    total: facts.volume.totalBytes
                ),
                tint: MachineCard.volume.tint
            )
        }
        .frame(height: 172)
    }
}

private enum MachineCard: String, CaseIterable, Identifiable {
    case chip
    case uptime
    case power
    case volume

    var id: String { rawValue }

    var title: String {
        switch self {
        case .chip: return "芯片"
        case .uptime: return "已开机"
        case .power: return "电源"
        case .volume: return "磁盘剩余"
        }
    }

    var symbol: String {
        switch self {
        case .chip: return "cpu"
        case .uptime: return "clock"
        case .power: return "bolt"
        case .volume: return "internaldrive"
        }
    }

    var tint: Color {
        switch self {
        case .chip: return PulsePalette.accent
        case .uptime: return PulsePalette.chartCPU
        case .power: return PulsePalette.pressureElevated
        case .volume: return PulsePalette.chartDisk
        }
    }
}

/// Left column of a resource overview card, without a sparkline.
private struct MachineFactCard: View {
    let symbol: String
    let title: String
    /// Nil is the loading skeleton. A readable dash is a real missing value.
    let value: String?
    let caption: String?
    var thermalNotice: String? = nil
    var tint: Color = PulsePalette.accent

    var body: some View {
        PulseCard {
            VStack(alignment: .leading, spacing: 6) {
                label
                if let value {
                    Text(value)
                        .font(.system(size: 34, weight: .semibold))
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                } else {
                    SkeletonBlock(width: 120, height: 28)
                }
                if let caption {
                    Text(caption)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                } else {
                    SkeletonBlock(width: 88, height: 10)
                }
                if let thermalNotice {
                    ThermalNoticeLine(text: thermalNotice)
                }
                Spacer(minLength: 0)
            }
        }
    }

    private var label: some View {
        HStack(spacing: 8) {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(tint.opacity(0.22))
                .frame(width: 22, height: 22)
                .overlay {
                    Image(systemName: symbol)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(tint)
                }
            Text(title)
                .font(.subheadline.weight(.medium))
                .lineLimit(1)
        }
    }
}
