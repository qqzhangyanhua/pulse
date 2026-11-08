import SwiftUI

struct ProcessDetailSidebarQuitControls: View {
    @EnvironmentObject private var vm: MemoryDashboardVM

    var body: some View {
        let sidebar = vm.sidebar
        return VStack(alignment: .leading, spacing: 8) {
            if let absentLabel = sidebar.absentLabel {
                Text(absentLabel)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let quitMessage = sidebar.quitMessage {
                Text(quitMessage)
                    .font(.caption)
                    .foregroundStyle(PulsePalette.pressureElevated)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let releaseNote = sidebar.releaseNote {
                Text(releaseNote)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if sidebar.showsQuittingSpinner {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text("正在退出…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            HStack(spacing: 8) {
                Button {
                    Task { await vm.forceQuitSelected() }
                } label: {
                    Text("强制退出…")
                        .foregroundStyle(PulsePalette.destructive)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .tint(PulsePalette.destructive)
                .controlSize(.large)
                .disabled(!sidebar.buttonsEnabled)

                Button {
                    Task { await vm.quitSelected() }
                } label: {
                    Label("退出", systemImage: "power")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(PulsePalette.action)
                .controlSize(.large)
                .disabled(!sidebar.buttonsEnabled)
            }
        }
        .padding(16)
        .background(PulsePalette.sidebar)
        .overlay(alignment: .top) {
            Divider()
                .overlay(PulsePalette.hairline)
        }
    }
}
