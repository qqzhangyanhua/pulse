import ServiceManagement
import SwiftUI

extension MachineOverviewSection {
    var launchItemsSection: some View {
        PulseCard {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    iconLabel(LaunchItemCopy.title, symbol: "list.bullet", tint: PulsePalette.accent)
                    Spacer(minLength: 4)
                    Button(LaunchItemCopy.openSettings) {
                        SMAppService.openSystemSettingsLoginItems()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
                if vm.launchItems.isEmpty {
                    Text(LaunchItemCopy.empty)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                } else {
                    columnTitles
                    ScrollView {
                        VStack(alignment: .leading, spacing: 6) {
                            ForEach(vm.launchItems) { row in
                                launchItemRow(row)
                            }
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 220, alignment: .topLeading)
    }

    private var columnTitles: some View {
        HStack(spacing: 8) {
            Text("名称")
                .frame(maxWidth: .infinity, alignment: .leading)
            Text("来源")
                .frame(width: 148, alignment: .leading)
            Text("签名")
                .frame(width: 148, alignment: .leading)
            Text("启用")
                .frame(width: 72, alignment: .leading)
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
    }

    private func launchItemRow(_ row: LaunchItemRow) -> some View {
        HStack(spacing: 8) {
            Text(row.label)
                .font(.caption.weight(.medium))
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(row.source)
                .frame(width: 148, alignment: .leading)
            Text(row.signature)
                .frame(width: 148, alignment: .leading)
            Text(row.enabled)
                .frame(width: 72, alignment: .leading)
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(row.label)，来源 \(row.source)，签名 \(row.signature)，启用 \(row.enabled)")
    }
}
