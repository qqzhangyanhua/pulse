import AppKit
import SwiftUI

/// Connection status, type, and a click-only public IP. Sampling keeps skeletons, not a fetch.
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
                    SkeletonBlock(width: 140, height: 12)
                    Text(NetworkPageCopy.sampling)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    let card = NetworkConnectionCard.project(vm.hostConnection)
                    valueRow(card.status)
                    valueRow(card.type)
                    publicIPRow
                }
            }
        }
        .frame(height: 148)
        .accessibilityElement(children: placeholder ? .combine : .contain)
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

    private var publicIPRow: some View {
        HStack(spacing: 8) {
            Text(PublicIPCopy.rowTitle)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            switch vm.publicIPRequest {
            case .idle:
                queryButton
            case .loading:
                ProgressView()
                    .controlSize(.small)
            case .success(let address, let queriedAt):
                Text(address)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text(PublicIPRequestState.queriedAtLabel(queriedAt, timeZone: TimeZone.current))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                copyButton(address)
            case .failure:
                Text(PublicIPCopy.missing)
                    .font(.subheadline.weight(.semibold))
                Text(PublicIPCopy.failed)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                retryButton
            }
            Spacer(minLength: 0)
        }
    }

    private var queryButton: some View {
        Button(PublicIPCopy.query) {
            vm.requestPublicIP()
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
    }

    private var retryButton: some View {
        Button(PublicIPCopy.retry) {
            vm.requestPublicIP()
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
    }

    private func copyButton(_ address: String) -> some View {
        Button(PublicIPCopy.copy) {
            let board = NSPasteboard.general
            board.clearContents()
            board.setString(address, forType: .string)
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
    }

    private var accessibilityLabel: String {
        if placeholder {
            return "\(NetworkPageCopy.connectionTitle)，\(NetworkPageCopy.sampling)"
        }
        let card = NetworkConnectionCard.project(vm.hostConnection)
        var label = "\(NetworkPageCopy.connectionTitle)，\(card.status.title) \(card.status.value)，\(card.type.title) \(card.type.value)"
        switch vm.publicIPRequest {
        case .success(let address, _):
            label += "，\(PublicIPCopy.rowTitle) \(address)"
        case .failure:
            label += "，\(PublicIPCopy.failed)"
        case .idle, .loading:
            break
        }
        return label
    }
}
