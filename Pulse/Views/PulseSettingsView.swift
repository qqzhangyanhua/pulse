import AppKit
import ServiceManagement
import SwiftUI

/// Settings page. Each control is its own section.
/// Menu-bar reading and pressure notice are stored. The login-item switch is read from SMAppService.
struct PulseSettingsView: View {
    @AppStorage(MenuBarReadingPreference.defaultsKey) private var storedMode = MenuBarReadingMode.dot.rawValue
    @AppStorage(PressureNoticePreference.defaultsKey) private var pressureNoticeEnabled = true
    @State private var notificationDenied = false
    @State private var registrationError: String?
    @State private var statusGeneration = 0

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
            Section("登录时打开 Pulse") {
                Toggle("登录时打开 Pulse", isOn: loginItemOn)
                if let caption = loginControl.caption {
                    Text(caption)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if loginControl.offersSystemSettings {
                    Button(LoginItemProjection.openSettingsButton) {
                        SMAppService.openSystemSettingsLoginItems()
                    }
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
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            rereadLoginItem()
        }
    }

    private func refreshNoticePermission() {
        PressureNoticeCenter.readDenied { denied in
            notificationDenied = denied
        }
    }

    private var loginControl: LoginItemControl {
        _ = statusGeneration
        return LoginItemProjection.control(status: loginItemStatus, registrationError: registrationError)
    }

    private var loginItemOn: Binding<Bool> {
        Binding(
            get: { loginControl.isOn },
            set: { turnOn in
                registrationError = nil
                do {
                    if turnOn {
                        try SMAppService.mainApp.register()
                    } else {
                        try SMAppService.mainApp.unregister()
                    }
                } catch {
                    registrationError = error.localizedDescription
                }
                statusGeneration += 1
            }
        )
    }

    private var loginItemStatus: LoginItemStatus {
        switch SMAppService.mainApp.status {
        case .notRegistered:
            return .notRegistered
        case .enabled:
            return .enabled
        case .requiresApproval:
            return .requiresApproval
        case .notFound:
            return .notFound
        @unknown default:
            return .notRegistered
        }
    }

    /// Coming back from System Settings reads status again. A stored bool would stay stale.
    private func rereadLoginItem() {
        statusGeneration += 1
        switch loginItemStatus {
        case .enabled, .requiresApproval:
            registrationError = nil
        case .notRegistered, .notFound:
            break
        }
    }
}
