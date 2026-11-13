import SwiftUI

extension ProcessDetailSidebar {
    /// Every resource page. The cache lives in the child view, not the VM.
    @ViewBuilder
    func processInfo(_ detail: ProcessDetail) -> some View {
        ProcessInfoSection(
            pid: detail.row.pid,
            startTimeSeconds: detail.row.startTimeSeconds,
            userID: detail.row.userID
        )
        .id(detail.row.pid)
    }
}

/// Signature, Rosetta, and sockets are read when this view's pid identity changes.
private struct ProcessInfoSection: View {
    let pid: Int32
    let startTimeSeconds: UInt64?
    let userID: UInt32?

    @State private var signatureText = "—"
    @State private var rosettaLine: String?
    /// Nil until a successful socket read. An unreadable list stays nil.
    @State private var loadedSockets: [ProcessSocketFact]?

    var body: some View {
        let start = ProcessStartTimeText.string(seconds: startTimeSeconds, timeZone: .current)
        let selfUid = ProcessSocketReader.currentUserID()
        let sockets = ProcessSocketPresentation.text(
            rowUid: userID,
            selfUid: selfUid,
            facts: isOwnUser(rowUid: userID, selfUid: selfUid) ? loadedSockets : nil
        )
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
            fact(title: "监听端口", value: sockets.listening)
            fact(title: "连接", value: sockets.connections)
            if let note = sockets.permissionNote {
                Text(note)
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
        .accessibilityLabel(spokenLabel(start: start, sockets: sockets))
        .task(id: pid) {
            let reading = ProcessCodeSignatureReader.read(pid: pid)
            guard !Task.isCancelled else { return }
            signatureText = ProcessSignatureDecoder.text(for: reading.facts)
            rosettaLine = ProcessRosettaDecoder.line(processFlags: reading.processFlags)
            let uid = ProcessSocketReader.currentUserID()
            guard isOwnUser(rowUid: userID, selfUid: uid) else { return }
            let facts = ProcessSocketReader.read(pid: pid)
            guard !Task.isCancelled else { return }
            loadedSockets = facts
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
                .lineLimit(nil)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func spokenLabel(start: String, sockets: ProcessSocketSectionText) -> String {
        var parts = ["进程信息", "启动时间 \(start)", "签名 \(signatureText)"]
        if let rosettaLine {
            parts.append(rosettaLine)
        }
        parts.append("监听端口 \(spoken(sockets.listening))")
        parts.append("连接 \(spoken(sockets.connections))")
        if let note = sockets.permissionNote {
            parts.append(note)
        }
        return parts.joined(separator: "，")
    }

    private func spoken(_ value: String) -> String {
        value.replacingOccurrences(of: "\n", with: "、")
    }
}
