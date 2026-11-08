import SwiftUI

/// One settings page. Later switches add their own sections; this page only chooses the menu-bar reading.
struct PulseSettingsView: View {
    @AppStorage(MenuBarReadingPreference.defaultsKey) private var storedMode = MenuBarReadingMode.dot.rawValue

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
        }
        .formStyle(.grouped)
        .frame(width: 420)
        .padding(20)
    }
}
