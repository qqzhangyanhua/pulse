import SwiftUI

/// Host facts and the current load. No chart and no process list. Those belong to the resource tabs.
struct MachineOverviewSection: View {
    @EnvironmentObject private var vm: MemoryDashboardVM

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            factsRow
            statusBlock
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var factsAccessibility: String {
        guard let facts = vm.machineFacts else { return "正在读取本机…" }
        return MachinePageCopy.accessibilityLabel(facts: facts, thermalNotice: nil)
    }

    private var factsRow: some View {
        Group {
            if let facts = vm.machineFacts {
                readyFacts(facts)
            } else {
                loadingFacts
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 172)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(factsAccessibility)
    }

    private var loadingFacts: some View {
        HStack(spacing: 12) {
            MachineIdentityCard(facts: nil)
                .frame(maxWidth: .infinity)
            ForEach(MachineCard.allCases) { card in
                MachineFactCard(
                    symbol: card.symbol,
                    title: card.title,
                    value: nil,
                    caption: nil,
                    tint: card.tint
                )
                .frame(maxWidth: 210)
            }
        }
    }

    private func readyFacts(_ facts: MachineFacts) -> some View {
        HStack(spacing: 12) {
            MachineIdentityCard(facts: facts)
                .frame(maxWidth: .infinity)
            MachineFactCard(
                symbol: MachineCard.uptime.symbol,
                title: MachineCard.uptime.title,
                value: MachinePageCopy.uptimeValue(facts.uptime),
                caption: MachinePageCopy.bootCaption(facts.bootedAt),
                tint: MachineCard.uptime.tint
            )
            .frame(maxWidth: 210)
            MachineFactCard(
                symbol: MachineCard.power.symbol,
                title: MachineCard.power.title,
                value: MachinePageCopy.powerValue(
                    source: facts.power.source,
                    percent: facts.power.batteryPercent
                ),
                caption: MachinePageCopy.powerCaption(
                    source: facts.power.source,
                    percent: facts.power.batteryPercent,
                    lowPowerMode: facts.power.lowPowerMode
                ),
                tint: MachineCard.power.tint
            )
            .frame(maxWidth: 210)
            MachineFactCard(
                symbol: MachineCard.volume.symbol,
                title: MachineCard.volume.title,
                value: MachinePageCopy.volumeValue(
                    available: facts.volume.availableBytes,
                    total: facts.volume.totalBytes
                ),
                caption: MachinePageCopy.volumeCaption(
                    available: facts.volume.availableBytes,
                    total: facts.volume.totalBytes
                ),
                tint: MachineCard.volume.tint
            )
            .frame(maxWidth: 210)
        }
    }

    private var statusBlock: some View {
        let snapshot = vm.snapshot
        let loadState = vm.loadState
        let pressure = MachineStatusCopy.pressure(snapshot: snapshot, loadState: loadState)
        let used = MachineStatusCopy.usedMemory(snapshot: snapshot, loadState: loadState)
        let swap = MachineStatusCopy.swap(snapshot: snapshot, loadState: loadState)
        let cpu = MachineStatusCopy.cpu(
            snapshot: snapshot,
            loadState: loadState,
            percent: vm.systemCpuPercent
        )
        let pressureColors = pressureTint(snapshot: snapshot, loadState: loadState)

        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                statusLink(MachineStatusCopy.buttonLabel(
                    title: "压力",
                    value: pressure.accessibilityValue,
                    destination: MachineStatusCopy.memoryDestination
                )) {
                    vm.selectPage(.memory)
                } label: {
                    statusCard(
                        systemImage: "gauge.medium",
                        title: "压力",
                        cell: pressure,
                        valueColor: pressureColors.value,
                        iconColor: pressureColors.icon,
                        border: pressureColors.border
                    )
                }
                statusLink(MachineStatusCopy.buttonLabel(
                    title: "已用",
                    value: used.accessibilityValue,
                    destination: MachineStatusCopy.memoryDestination
                )) {
                    vm.selectPage(.memory)
                } label: {
                    statusCard(
                        systemImage: "memorychip",
                        title: "已用",
                        cell: used,
                        iconColor: PulsePalette.accent
                    )
                }
                statusLink(MachineStatusCopy.buttonLabel(
                    title: "交换",
                    value: swap.accessibilityValue,
                    destination: MachineStatusCopy.memoryDestination
                )) {
                    vm.selectPage(.memory)
                } label: {
                    statusCard(
                        systemImage: "arrow.left.arrow.right",
                        title: "交换",
                        cell: swap
                    )
                }
                statusLink(MachineStatusCopy.buttonLabel(
                    title: "CPU",
                    value: cpu.accessibilityValue,
                    destination: MachineStatusCopy.cpuDestination
                )) {
                    vm.selectPage(.cpu)
                } label: {
                    statusCard(
                        systemImage: "cpu",
                        title: "CPU",
                        cell: cpu,
                        iconColor: PulsePalette.chartCPU
                    )
                }
            }
            .frame(height: 104)

            if let notice = vm.thermalNotice {
                ThermalNoticeLine(text: notice)
            }
        }
    }

    private func pressureTint(snapshot: MemorySnapshot?, loadState: LoadState) -> (value: Color, icon: Color, border: Color) {
        guard MachineStatusCopy.phase(snapshot: snapshot, loadState: loadState) == .ready,
              let snapshot else {
            return (.primary, .secondary, PulsePalette.hairline)
        }
        let tone = snapshot.pressure == .elevated
            ? PulsePalette.pressureElevated
            : PulsePalette.pressureNormal
        let border = tone.opacity(snapshot.pressure == .elevated ? 0.55 : 0.16)
        return (tone, tone, border)
    }

    private func statusLink<Label: View>(
        _ accessibility: String,
        action: @escaping () -> Void,
        @ViewBuilder label: () -> Label
    ) -> some View {
        Button(action: action, label: label)
            .buttonStyle(.plain)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(accessibility)
            .accessibilityAddTraits(.isButton)
    }

    @ViewBuilder
    private func statusCard(
        systemImage: String,
        title: String,
        cell: MachineStatusCopy.Cell,
        valueColor: Color = .primary,
        iconColor: Color = .secondary,
        border: Color = PulsePalette.hairline
    ) -> some View {
        if let value = cell.value {
            MetricStatCard(
                systemImage: systemImage,
                title: title,
                value: value,
                valueColor: valueColor,
                caption: cell.caption,
                iconColor: iconColor,
                border: border
            )
        } else {
            PulseCard(padding: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    Label(title, systemImage: systemImage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .labelStyle(.titleAndIcon)
                        .lineLimit(1)
                    SkeletonBlock(width: 72, height: 18)
                    Text(cell.caption)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                }
            }
        }
    }
}

private struct MachineIdentityCard: View {
    let facts: MachineFacts?

    var body: some View {
        PulseCard {
            VStack(alignment: .leading, spacing: 6) {
                label
                if let facts {
                    Text(MachinePageCopy.modelValue(facts.modelName))
                        .font(.system(size: 22, weight: .semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                    Text(MachinePageCopy.chipValue(facts.chipName))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Text(MachinePageCopy.osValue(facts.os))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Text(MachinePageCopy.capacityLine(
                        coreCount: facts.coreCount,
                        physicalMemoryBytes: facts.physicalMemoryBytes
                    ))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                } else {
                    SkeletonBlock(width: 160, height: 22)
                    Text("正在读取本机…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    SkeletonBlock(width: 120, height: 10)
                    SkeletonBlock(width: 96, height: 10)
                }
                Spacer(minLength: 0)
            }
        }
    }

    private var label: some View {
        HStack(spacing: 8) {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(PulsePalette.accent.opacity(0.22))
                .frame(width: 22, height: 22)
                .overlay {
                    Image(systemName: "desktopcomputer")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(PulsePalette.accent)
                }
            Text("这台 Mac")
                .font(.subheadline.weight(.medium))
                .lineLimit(1)
        }
    }
}

private enum MachineCard: String, CaseIterable, Identifiable {
    case uptime
    case power
    case volume

    var id: String { rawValue }

    var title: String {
        switch self {
        case .uptime: return "已开机"
        case .power: return "电源"
        case .volume: return "磁盘剩余"
        }
    }

    var symbol: String {
        switch self {
        case .uptime: return "clock"
        case .power: return "bolt"
        case .volume: return "internaldrive"
        }
    }

    var tint: Color {
        switch self {
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
    /// Nil with a value hides the caption. Nil while loading draws a caption skeleton.
    let caption: String?
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
                    if let caption, !caption.isEmpty {
                        Text(caption)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                } else {
                    SkeletonBlock(width: 120, height: 28)
                    SkeletonBlock(width: 88, height: 10)
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
