import SwiftUI

struct SymptomPanel: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let findings: (SymptomKind) -> SymptomFinding
    let open: (DashboardPage, Int32?) -> Void
    let close: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("诊断")
                        .font(.title2.weight(.semibold))
                    Spacer()
                    Button("关闭", action: close)
                        .accessibilityLabel("关闭诊断")
                }
                ForEach(SymptomKind.allCases, id: \.self) { kind in
                    card(kind, finding: findings(kind))
                }
            }
            .padding(16)
        }
        .frame(minWidth: 420, minHeight: 480)
        .animation(reduceMotion ? nil : PulseMotion.page, value: SymptomKind.allCases.count)
    }

    private func card(_ kind: SymptomKind, finding: SymptomFinding) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(kind.title)
                .font(.headline)
            if let note = finding.note {
                Text(note)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if finding.causes.isEmpty {
                Text(SymptomFinding.unknown)
                    .font(.body)
            } else {
                ForEach(Array(finding.causes.enumerated()), id: \.offset) { _, cause in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(cause.title)
                        Text(cause.evidence)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Button("去看看") {
                            open(cause.page, cause.pid)
                        }
                        .accessibilityLabel("去看看\(cause.title)")
                    }
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(PulsePalette.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(spoken(kind, finding: finding))
    }

    private func spoken(_ kind: SymptomKind, finding: SymptomFinding) -> String {
        var parts = [kind.title]
        if let note = finding.note {
            parts.append(note)
        }
        if finding.causes.isEmpty {
            parts.append(SymptomFinding.unknown)
        } else {
            for cause in finding.causes {
                parts.append("\(cause.title)，\(cause.evidence)")
            }
        }
        return parts.joined(separator: "。")
    }
}
