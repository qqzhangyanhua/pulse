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
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                ProcessIconView(
                    pid: row.pid,
                    bundleIdentifier: row.bundleIdentifier,
                    executablePath: row.executablePath,
                    size: 16
                )
                .accessibilityHidden(true)
                processName(row)
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
            if let fraction = row.barFraction {
                FractionCapsuleTrack(fraction: fraction)
            }
        }
    }

    /// The name only. A pid outside the live process rows stays plain text.
    @ViewBuilder
    private func processName(_ row: GPUShareRow) -> some View {
        if vm.gpuShareNameOpensMemoryPage(row.pid) {
            Button {
                vm.openGPUShareProcess(row.pid)
            } label: {
                nameLabel(row.name)
            }
            .buttonStyle(.plain)
        } else {
            nameLabel(row.name)
        }
    }

    private func nameLabel(_ name: String) -> some View {
        Text(name)
            .font(.callout)
            .lineLimit(1)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}
