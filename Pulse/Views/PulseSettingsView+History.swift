import SwiftUI

/// Occupied space, retention, and clearing. Its own section, not 通知 or 告警规则.
struct HistorySettingsSection: View {
    @AppStorage(HistoryRetentionPreference.defaultsKey) private var storedDays = 90
    @State private var confirmClear = false
    @State private var occupiedBytes: UInt64?

    var body: some View {
        Section("历史") {
            LabeledContent("占用空间") {
                Text(HistorySettingsCopy.occupied(occupiedBytes))
            }
            Picker("保留", selection: retentionSelection) {
                Text("7 天").tag(7)
                Text("30 天").tag(30)
                Text("90 天").tag(90)
            }
            Button("清空历史") {
                confirmClear = true
            }
            .accessibilityLabel("清空历史")
            Text("历史只保存在这台 Mac 上")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .onAppear(perform: refreshOccupied)
        .onChange(of: storedDays) { _, _ in
            truncateToSelection()
            refreshOccupied()
        }
        .confirmationDialog(
            "清空历史？",
            isPresented: $confirmClear,
            titleVisibility: .visible
        ) {
            Button("清空历史", role: .destructive) {
                HistoryStore.shared.deleteAll()
                refreshOccupied()
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("已保存的历史会删掉。实时曲线还在。")
        }
    }

    private var retentionSelection: Binding<Int> {
        Binding(
            get: { HistoryRetentionPreference.resolved(storedDays).dayCount },
            set: { storedDays = $0 }
        )
    }

    /// Dates come from `HistoryPolicy`. This view does not turn days into seconds.
    private func truncateToSelection() {
        let retention = HistoryRetentionPreference.resolved(storedDays)
        let now = Date()
        HistoryStore.shared.truncate(
            dropMinuteBefore: HistoryPolicy.minuteDrop(before: now, retention: retention),
            retentionCutoff: HistoryPolicy.retentionCutoff(retention, now: now)
        )
    }

    private func refreshOccupied() {
        occupiedBytes = HistoryStore.shared.byteCount()
    }
}
