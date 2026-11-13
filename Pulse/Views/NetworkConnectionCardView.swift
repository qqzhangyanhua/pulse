import AppKit
import SwiftUI

/// Status, type, Wi-Fi signal, SSID, and a click-only public IP. Sampling keeps skeletons, not a fetch.
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
                    let card = NetworkConnectionCard.project(vm.hostConnection, wifi: vm.hostWiFi, ssidPermission: vm.ssidPermission)
                    valueRow(card.status)
                    valueRow(card.type)
                    if let signal = card.signal {
                        valueRow(signal)
                    }
                    if let ssid = card.ssid {
                        ssidRow(ssid)
                    }
                    publicIPRow
                }
            }
        }
        .frame(height: cardHeight, alignment: .top)
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

    private func ssidRow(_ row: NetworkConnectionSSID) -> some View {
        HStack(spacing: 8) {
            Text(row.title)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            ssidValue(row)
            if let note = row.note {
                Text(note)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            if row.allowsRequest {
                Button(NetworkPageCopy.ssidAllow) {
                    vm.allowWiFiSSID()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
            Spacer(minLength: 0)
        }
    }

    private func ssidValue(_ row: NetworkConnectionSSID) -> some View {
        Text(row.value)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.primary)
            .lineLimit(1)
            .truncationMode(.middle)
            .help(row.help ?? row.value)
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
        let card = NetworkConnectionCard.project(vm.hostConnection, wifi: vm.hostWiFi, ssidPermission: vm.ssidPermission)
        var label = "\(NetworkPageCopy.connectionTitle)，\(card.status.title) \(card.status.value)，\(card.type.title) \(card.type.value)"
        if let signal = card.signal {
            label += "，\(signal.title) \(signal.value)"
        }
        if let ssid = card.ssid {
            label += "，\(ssid.title) \(ssid.value)"
            if let note = ssid.note {
                label += "，\(note)"
            }
        }
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

    /// 148 fits title, status, type, and the public-IP row. Wi-Fi adds signal and the name: 206.
    private var cardHeight: CGFloat {
        if placeholder { return 148 }
        let card = NetworkConnectionCard.project(vm.hostConnection, wifi: vm.hostWiFi, ssidPermission: vm.ssidPermission)
        return card.ssid == nil ? 148 : 206
    }
}
