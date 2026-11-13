import SwiftUI

/// Draft for adding or editing one custom 告警规则. The builtin rule is not edited here.
struct AlertRuleEditorModel: Identifiable, Equatable {
    var id: String
    var isNew: Bool
    var enabled: Bool
    var objectIsApp: Bool
    var appName: String
    var metric: AlertMetric
    var thresholdText: String
    var durationMinutes: Int
    var cooldownMinutes: Int
    var dailyLimit: Int

    var metricChoices: [AlertMetric] {
        objectIsApp ? [.cpu, .memoryFootprint] : Array(AlertMetric.allCases)
    }

    static func fresh() -> AlertRuleEditorModel {
        AlertRuleEditorModel(
            id: "pulse.alert.\(UUID().uuidString)",
            isNew: true,
            enabled: true,
            objectIsApp: false,
            appName: "",
            metric: .cpu,
            thresholdText: "80",
            durationMinutes: Int(CustomAlertRule.defaultDuration / 60),
            cooldownMinutes: Int(CustomAlertRule.defaultCooldown / 60),
            dailyLimit: CustomAlertRule.defaultDailyLimit
        )
    }

    static func editing(_ rule: CustomAlertRule) -> AlertRuleEditorModel {
        let objectIsApp: Bool
        let appName: String
        switch rule.object {
        case .machine:
            objectIsApp = false
            appName = ""
        case .app(let name):
            objectIsApp = true
            appName = name
        }
        return AlertRuleEditorModel(
            id: rule.id,
            isNew: false,
            enabled: rule.enabled,
            objectIsApp: objectIsApp,
            appName: appName,
            metric: rule.metric,
            thresholdText: rule.metric.displayThreshold(rule.threshold),
            durationMinutes: max(Int(rule.duration / 60), 0),
            cooldownMinutes: max(Int(rule.cooldown / 60), 0),
            dailyLimit: max(rule.dailyLimit, 1)
        )
    }

    func validated() -> CustomAlertRule? {
        let object: AlertObject = objectIsApp
            ? .app(appName.trimmingCharacters(in: .whitespacesAndNewlines))
            : .machine
        var chosen = metric
        if objectIsApp, chosen != .cpu, chosen != .memoryFootprint {
            chosen = .cpu
        }
        guard let threshold = chosen.storedThreshold(displayText: thresholdText) else { return nil }
        let rule = CustomAlertRule(
            id: id,
            enabled: enabled,
            object: object,
            metric: chosen,
            threshold: threshold,
            duration: TimeInterval(durationMinutes) * 60,
            cooldown: TimeInterval(cooldownMinutes) * 60,
            dailyLimit: dailyLimit
        )
        return rule.isValid ? rule : nil
    }
}

struct AlertRuleEditor: View {
    @State private var model: AlertRuleEditorModel
    @State private var message: String?
    var onSave: (AlertRuleEditorModel) -> Void
    var onCancel: () -> Void

    init(
        model: AlertRuleEditorModel,
        onSave: @escaping (AlertRuleEditorModel) -> Void,
        onCancel: @escaping () -> Void
    ) {
        _model = State(initialValue: model)
        self.onSave = onSave
        self.onCancel = onCancel
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(AlertRuleCopy.sectionTitle)
                .font(.headline)
                .accessibilityAddTraits(.isHeader)
            Picker("对象", selection: $model.objectIsApp) {
                Text("整机").tag(false)
                Text("某个 App").tag(true)
            }
            .pickerStyle(.radioGroup)
            .accessibilityLabel("告警规则对象")
            if model.objectIsApp {
                TextField("App 名称", text: $model.appName)
                    .accessibilityLabel("告警规则的 App 名称")
            }
            Picker("指标", selection: $model.metric) {
                ForEach(model.metricChoices, id: \.self) { metric in
                    Text(metric.title).tag(metric)
                }
            }
            .accessibilityLabel("告警规则指标")
            if model.metric != .memoryPressure {
                TextField("阈值（\(model.metric.thresholdUnit)）", text: $model.thresholdText)
                    .accessibilityLabel("告警规则阈值")
            }
            Stepper(value: $model.durationMinutes, in: 0...1440) {
                Text("持续 \(model.durationMinutes) 分钟")
            }
            .accessibilityLabel("告警规则持续时长")
            Stepper(value: $model.cooldownMinutes, in: 0...1440) {
                Text("冷却 \(model.cooldownMinutes) 分钟")
            }
            .accessibilityLabel("告警规则冷却")
            Stepper(value: $model.dailyLimit, in: 1...99) {
                Text("每日上限 \(model.dailyLimit) 次")
            }
            .accessibilityLabel("告警规则每日上限")
            if let message {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            HStack {
                Button("取消", action: onCancel)
                    .accessibilityLabel("取消编辑告警规则")
                Button(AlertRuleCopy.saveButton) {
                    guard model.validated() != nil else {
                        message = AlertRuleCopy.incomplete
                        return
                    }
                    onSave(model)
                }
                .accessibilityLabel(AlertRuleCopy.saveButton)
            }
        }
        .padding(20)
        .frame(width: 420)
        .onChange(of: model.objectIsApp) { _, isApp in
            guard isApp, model.metric != .cpu, model.metric != .memoryFootprint else { return }
            model.metric = .cpu
        }
    }
}
