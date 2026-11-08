import SwiftUI

/// Settings page. Each control is its own section.
struct PulseSettingsView: View {
    @AppStorage(MenuBarReadingPreference.defaultsKey) private var storedMode = MenuBarReadingMode.dot.rawValue
    @AppStorage(PressureNoticePreference.defaultsKey) private var pressureNoticeEnabled = true
    @State private var notificationDenied = false

    var body: some View {
        Form {
            Section("菜单栏") {
                Picker("读数", selection: $storedMode) {
                    ForEach(MenuBarReadingMode.allCases, id: \.rawValue) { mode in
                        Text(mode.settingsLabel).tag(mode.rawValue)
                    }
                }
                .pickerStyle(.radioGroup)
            }
            Section("通知") {
                Toggle("压力偏高时通知", isOn: $pressureNoticeEnabled)
                if notificationDenied {
                    Text(PressureNoticeCopy.permissionDenied)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 420)
        .padding(20)
        .onAppear(perform: refreshNoticePermission)
        .onChange(of: pressureNoticeEnabled) { _, enabled in
            guard enabled else { return }
            PressureNoticeCenter.requestPermission { denied in
                notificationDenied = denied
            }
        }
    }

    private func refreshNoticePermission() {
        PressureNoticeCenter.readDenied { denied in
            notificationDenied = denied
        }
    }
}
