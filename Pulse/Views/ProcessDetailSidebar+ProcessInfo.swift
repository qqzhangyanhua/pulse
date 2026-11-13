import SwiftUI

extension ProcessDetailSidebar {
    /// Every resource page. The cache lives in the child view, not the VM.
    @ViewBuilder
    func processInfo(_ detail: ProcessDetail) -> some View {
        ProcessInfoSection(
            pid: detail.row.pid,
            startTimeSeconds: detail.row.startTimeSeconds
        )
        .id(detail.row.pid)
    }
}

/// Signature and Rosetta are read when this view's pid identity changes.
private struct ProcessInfoSection: View {
    let pid: Int32
    let startTimeSeconds: UInt64?

    @State private var signatureText = "—"
    @State private var rosettaLine: String?

    var body: some View {
        let start = ProcessStartTimeText.string(seconds: startTimeSeconds, timeZone: .current)
        VStack(alignment: .leading, spacing: 8) {
            Text("进程信息")
                .font(.subheadline.weight(.semibold))
            fact(title: "启动时间", value: start)
            fact(title: "签名", value: signatureText)
            if let rosettaLine {
                Text(rosettaLine)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(PulsePalette.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(PulsePalette.hairline, lineWidth: 1)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spokenLabel(start: start))
        .task(id: pid) {
            let reading = ProcessCodeSignatureReader.read(pid: pid)
            guard !Task.isCancelled else { return }
            signatureText = ProcessSignatureDecoder.text(for: reading.facts)
            rosettaLine = ProcessRosettaDecoder.line(processFlags: reading.processFlags)
        }
    }

    private func fact(title: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer(minLength: 8)
            Text(value)
                .font(.callout.monospacedDigit())
                .multilineTextAlignment(.trailing)
        }
    }

    private func spokenLabel(start: String) -> String {
        var parts = ["进程信息", "启动时间 \(start)", "签名 \(signatureText)"]
        if let rosettaLine {
            parts.append(rosettaLine)
        }
        return parts.joined(separator: "，")
    }
}
