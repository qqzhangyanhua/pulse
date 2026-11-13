import SwiftUI

/// Top five GPU-share rows. Not a process table, and not the machine-wide utilization.
struct GPUShareCard: View {
    @EnvironmentObject private var vm: MemoryDashboardVM

    var body: some View {
        if let share = vm.gpuShare {
            card(share)
        }
    }

    private func card(_ share: GPUSharePresentation) -> some View {
        PulseCard {
            VStack(alignment: .leading, spacing: 8) {
                Text(GPUShareCopy.title)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(1)
                switch share {
                case .missing:
                    Text(GPUShareCopy.missing)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                case .rows(let rows):
                    if rows.isEmpty {
                        Text(CPUPercentText.missing)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(rows) { row in
                            processRow(row)
                        }
                    }
                }
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private func processRow(_ row: GPUShareRow) -> some View {
        HStack(spacing: 8) {
            ProcessIconView(
                pid: row.pid,
                bundleIdentifier: row.bundleIdentifier,
                executablePath: row.executablePath,
                size: 16
            )
            .accessibilityHidden(true)
            Text(row.name)
                .font(.callout)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(row.shareText)
                .font(.caption)
                .foregroundStyle(.secondary)
                .monospacedDigit()
                .accessibilityLabel("\(GPUShareCopy.title) \(row.shareText)")
            Button("退出") {
                let pid = row.pid
                Task { await vm.terminateThermalAdvice(pid: pid) }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
    }
}
