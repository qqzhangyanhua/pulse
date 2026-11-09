import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// Observes the frozen preview without adding another published field on the dashboard VM.
@MainActor
final class SnapshotExportStore: ObservableObject {
    private var gate = SnapshotExportSaveGate()
    @Published private(set) var session: SnapshotExportSession?

    func present(_ session: SnapshotExportSession) {
        gate.present(session)
        publish()
    }

    func dismiss() {
        gate.dismiss()
        publish()
    }

    func setHideNames(_ hide: Bool) {
        gate.setHideNames(hide)
        publish()
    }

    func cancelSavePanel() {
        publish()
    }

    func noteWriteFailed() {
        gate.noteWriteFailed()
        publish()
    }

    func noteWriteSucceeded() {
        gate.noteWriteSucceeded()
        publish()
    }

    func beginSavePanel() -> SnapshotExportSaveAttempt? {
        let attempt = gate.beginSavePanel()
        publish()
        return attempt
    }

    func receiveSavePanel(
        _ attempt: SnapshotExportSaveAttempt,
        confirmed: Bool
    ) -> SnapshotExportSavePanelDecision {
        let decision = gate.receiveSavePanel(attempt, confirmed: confirmed)
        publish()
        return decision
    }

    func finishSavePanel(_ attempt: SnapshotExportSaveAttempt, succeeded: Bool) {
        gate.finishSavePanel(attempt, succeeded: succeeded)
        publish()
    }

    private func publish() {
        session = gate.session
    }
}

struct SnapshotExportSheetPresenter: View {
    @ObservedObject var store: SnapshotExportStore
    let vm: MemoryDashboardVM

    var body: some View {
        Color.clear
            .sheet(
                isPresented: Binding(
                    get: { store.session != nil },
                    set: { presented in
                        if !presented {
                            vm.cancelSnapshotExportPreview()
                        }
                    }
                )
            ) {
                SnapshotExportPreview(store: store, vm: vm)
            }
    }
}

/// Read-only sheet. Process lines are text. Saving uses the document already formatted for this freeze.
struct SnapshotExportPreview: View {
    @ObservedObject var store: SnapshotExportStore
    let vm: MemoryDashboardVM

    var body: some View {
        if let session = store.session {
            preview(session.document, session: session)
        }
    }

    private func preview(_ document: SnapshotDocument, session: SnapshotExportSession) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            ScrollView {
                Text(document.previewText)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
            }
            if let banner = session.banner {
                Text(banner)
                    .font(.callout)
            }
            Toggle(
                isOn: Binding(
                    get: { session.hideNames },
                    set: { vm.setSnapshotExportHidesNames($0) }
                )
            ) {
                Text("隐藏进程名")
            }
            .accessibilityLabel("隐藏进程名")
            .accessibilityValue(session.hideNames ? "开" : "关")
            HStack {
                Button("取消") {
                    vm.cancelSnapshotExportPreview()
                }
                Spacer()
                Button("保存到本机") {
                    presentSavePanel()
                }
            }
        }
        .padding(16)
        .frame(minWidth: 560, minHeight: 460)
    }

    private func presentSavePanel() {
        guard let attempt = store.beginSavePanel() else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.html]
        panel.nameFieldStringValue = store.session?.document.suggestedFilename ?? ""
        panel.canCreateDirectories = true
        panel.begin { response in
            let url = panel.url
            Task { @MainActor in
                let confirmed = response == .OK && url != nil
                switch self.store.receiveSavePanel(attempt, confirmed: confirmed) {
                case .ignore, .cancelled:
                    return
                case .write(let html):
                    guard let url else {
                        self.store.finishSavePanel(attempt, succeeded: false)
                        return
                    }
                    do {
                        try SnapshotExportFile.commit(html: html, to: url)
                        self.store.finishSavePanel(attempt, succeeded: true)
                    } catch {
                        self.store.finishSavePanel(attempt, succeeded: false)
                    }
                }
            }
        }
    }
}
