import SwiftUI

/// Full-width advice card. Not an inline caption. Replaces the one-line notice while advice is showing.
struct ThermalAdviceCard: View {
    @EnvironmentObject private var vm: MemoryDashboardVM

    var body: some View {
        if let advice = vm.thermalAdvice {
            adviceCard(advice)
        }
    }

    private func adviceCard(_ advice: ThermalAdvice) -> some View {
        PulseCard {
            if advice.noHighLoad {
                Text(ThermalAdvice.noHighLoadMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    Text(ThermalNotice.throttling)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    ForEach(advice.processes, id: \.pid) { process in
                        processRow(process)
                    }
                }
            }
        }
        // Content height: `PulseCard` would otherwise expand like a hero tile.
        .fixedSize(horizontal: false, vertical: true)
    }

    private func processRow(_ process: ThermalAdviceProcess) -> some View {
        HStack(spacing: 8) {
            ProcessIconView(
                pid: process.pid,
                bundleIdentifier: process.bundleIdentifier,
                executablePath: process.executablePath,
                size: 16
            )
                .accessibilityHidden(true)
            Text(process.name)
                .font(.callout)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(CPUPercentText.string(process.cpuPercent))
                .font(.caption)
                .foregroundStyle(.secondary)
                .monospacedDigit()
            Button("退出") {
                let pid = process.pid
                Task { await vm.terminateThermalAdvice(pid: pid) }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
    }
}
