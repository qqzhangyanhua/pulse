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
                    let card = NetworkConnectionCard.project(vm.hostConnection)
                    valueRow(card.status)
                    valueRow(card.type)
                }
            }
        }
        .frame(height: 112)
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
        let card = NetworkConnectionCard.project(vm.hostConnection)
        return "\(NetworkPageCopy.connectionTitle)，\(card.status.title) \(card.status.value)，\(card.type.title) \(card.type.value)"
    }
}
