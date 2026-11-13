import SwiftUI

/// Connection status and type. Sampling keeps skeletons, not a guessed link.
struct NetworkConnectionCardView: View {
    var placeholder: Bool
    @EnvironmentObject private var vm: MemoryDashboardVM

    var body: some View {
        PulseCard {
            VStack(alignment: .leading, spacing: 6) {
                title
                if placeholder {
                    SkeletonBlock(width: 120, height: 12)
                    SkeletonBlock(width: 96, height: 12)
                    Text(NetworkPageCopy.sampling)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    let card = NetworkConnectionCard.project(vm.hostConnection, wifi: vm.hostWiFi)
                    valueRow(card.status)
                    valueRow(card.type)
                    if let signal = card.signal {
                        valueRow(signal)
                    }
                }
            }
        }
        .frame(height: cardHeight, alignment: .top)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
    }

    private var title: some View {
        HStack(spacing: 8) {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(PulsePalette.chartNetwork.opacity(0.22))
                .frame(width: 22, height: 22)
                .overlay {
                    Image(systemName: "link")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(PulsePalette.chartNetwork)
                }
            Text(NetworkPageCopy.connectionTitle)
                .font(.subheadline.weight(.medium))
        }
    }

    private func valueRow(_ row: NetworkConnectionRow) -> some View {
        HStack(spacing: 8) {
            Text(row.title)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text(row.value)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
            Spacer(minLength: 0)
        }
    }

    private var accessibilityLabel: String {
        if placeholder {
            return "\(NetworkPageCopy.connectionTitle)，\(NetworkPageCopy.sampling)"
        }
        let card = NetworkConnectionCard.project(vm.hostConnection, wifi: vm.hostWiFi)
        var label = "\(NetworkPageCopy.connectionTitle)，\(card.status.title) \(card.status.value)，\(card.type.title) \(card.type.value)"
        if let signal = card.signal {
            label += "，\(signal.title) \(signal.value)"
        }
        return label
    }

    /// 112 fits title, status, and type. 138 adds the signal row. Ethernet stays short.
    private var cardHeight: CGFloat {
        if placeholder { return 112 }
        let card = NetworkConnectionCard.project(vm.hostConnection, wifi: vm.hostWiFi)
        return card.signal == nil ? 112 : 138
    }
}
