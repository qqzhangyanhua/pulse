import AppKit
import ServiceManagement
import SwiftUI

/// Settings page. Each control is its own section.
/// Menu-bar reading and pressure notice are stored. The login-item switch is read from SMAppService.
struct PulseSettingsView: View {
    @AppStorage(MenuBarReadingPreference.defaultsKey) private var storedMode = MenuBarReadingMode.dot.rawValue
    @AppStorage(PressureNoticePreference.defaultsKey) private var pressureNoticeEnabled = true
    @AppStorage(AlertRuleStore.defaultsKey) private var storedCustomRules = ""
    @State private var notificationDenied = false
    @State private var registrationError: String?
    @State private var statusGeneration = 0
    @State private var editor: AlertRuleEditorModel?

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
            Section("告警规则") {
                Toggle("压力偏高时通知", isOn: $pressureNoticeEnabled)
                    .accessibilityLabel("告警规则：压力偏高时通知")
                Text(AlertRuleCopy.builtinNote)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("内置告警规则不能删除")
                if notificationDenied {
                    Text(PressureNoticeCopy.permissionDenied)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if alertCatalog.custom.isEmpty {
                    Text(AlertRuleCopy.emptyCustom)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                ForEach(alertCatalog.custom) { rule in
                    alertRuleRow(rule)
                }
                Button(AlertRuleCopy.addButton) {
                    editor = .fresh()
                }
                .accessibilityLabel(AlertRuleCopy.addButton)
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
        .frame(width: 460)
        .padding(20)
        .onAppear(perform: refreshNoticePermission)
        .sheet(item: $editor) { model in
            AlertRuleEditor(model: model) { saved in
                saveAlertRule(saved)
            } onCancel: {
                editor = nil
            }
        }
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

    private var alertCatalog: AlertRuleCatalog {
        AlertRuleStore.catalog(stored: storedCustomRules)
    }

    private func alertRuleRow(_ rule: CustomAlertRule) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Toggle(rule.notificationBody, isOn: customEnabled(rule))
                .accessibilityLabel("停用或启用告警规则：\(rule.notificationBody)")
            Text(rule.listDetail)
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack {
                Button("编辑") { editor = .editing(rule) }
                    .accessibilityLabel("编辑告警规则：\(rule.notificationBody)")
                Button("删除") {
                    storedCustomRules = AlertRuleStore.stored(alertCatalog.removing(id: rule.id))
                }
                .accessibilityLabel("删除告警规则：\(rule.notificationBody)")
            }
        }
    }

    private func customEnabled(_ rule: CustomAlertRule) -> Binding<Bool> {
        Binding(
            get: { rule.enabled },
            set: { enabled in
                storedCustomRules = AlertRuleStore.stored(
                    alertCatalog.settingEnabled(id: rule.id, enabled: enabled)
                )
                if enabled {
                    allowNotices()
                }
            }
        )
    }

    private func saveAlertRule(_ model: AlertRuleEditorModel) {
        guard let rule = model.validated() else { return }
        let next = model.isNew ? alertCatalog.adding(rule) : alertCatalog.replacing(rule)
        guard next.custom.contains(rule) else { return }
        storedCustomRules = AlertRuleStore.stored(next)
        editor = nil
        if rule.enabled {
            allowNotices()
        }
    }

    private func allowNotices() {
        PressureNoticeCenter.requestPermission { denied in
            notificationDenied = denied
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
