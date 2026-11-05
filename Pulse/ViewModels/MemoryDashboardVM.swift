import Foundation
import SwiftUI

@MainActor
final class MemoryDashboardVM: ObservableObject {
    @Published private(set) var loadState: LoadState = .sampling
    @Published private(set) var snapshot: MemorySnapshot?
    @Published private(set) var rows: [ProcessRow] = []
    @Published private(set) var processListFailed = false
    @Published private(set) var detail: ProcessDetail?
    @Published private(set) var machineLabel: String?
    @Published private(set) var quitPhase: QuitPhase = .idle
    @Published private(set) var quitMessage: String?
    @Published var filter = ""
    @Published var sortOrder: [KeyPathComparator<ProcessRow>] = [
        KeyPathComparator(\ProcessRow.memoryBytes, order: .reverse)
    ]

    @Published var selectedPid: Int32? {
        didSet {
            guard oldValue != selectedPid else { return }
            detail = nil
            quitPhase = .idle
            quitMessage = nil
            let pid = selectedPid
            Task { await sampler.setSelectedPid(pid) }
        }
    }

    private let sampler = MemorySampler()
    private var loopTask: Task<Void, Never>?
    private var started = false
    private var isForeground = true

    var visibleRows: [ProcessRow] {
        let query = filter.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return rows }
        return rows.filter { $0.name.localizedCaseInsensitiveContains(query) }
    }

    var selectedRow: ProcessRow? {
        guard let selectedPid else { return nil }
        return rows.first { $0.pid == selectedPid }
    }

    var hasActiveFilter: Bool {
        !filter.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    func start() {
        guard !started else { return }
        started = true
        machineLabel = MachineInfo.toolbarLabel()
        loopTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { break }
                if self.isForeground {
                    await self.tick()
                    try? await Task.sleep(nanoseconds: 1_500_000_000)
                } else {
                    try? await Task.sleep(nanoseconds: 400_000_000)
                }
            }
        }
    }

    func setForeground(_ active: Bool) {
        isForeground = active
    }

    func retrySampling() {
        loadState = .sampling
        snapshot = nil
        rows = []
        processListFailed = false
        Task { await tick() }
    }

    func quitSelected() async {
        guard let pid = selectedPid else { return }
        quitPhase = .quitting
        quitMessage = nil
        let result = await ProcessActions.terminate(pid: pid)
        applyQuit(result, fallback: "未能退出。可以请系统立即结束该进程。")
    }

    func forceQuitSelected() async {
        guard let pid = selectedPid, let name = selectedRow?.name ?? detail?.row.name else { return }
        guard ProcessActions.confirmForceQuit(displayName: name) else { return }
        quitPhase = .quitting
        quitMessage = nil
        let result = await ProcessActions.forceTerminate(pid: pid)
        applyQuit(result, fallback: "系统未能结束该进程。")
    }

    private func applyQuit(_ result: ProcessActionResult, fallback: String) {
        switch result {
        case .exited, .notFound:
            selectedPid = nil
            detail = nil
            quitPhase = .idle
            quitMessage = nil
        case .requestFailed, .stillRunning:
            quitPhase = .failed
            quitMessage = fallback
        }
    }

    private func tick() async {
        let result = await sampler.sample()
        switch result {
        case .success(let frame):
            snapshot = frame.snapshot
            rows = frame.rows
            processListFailed = frame.processListFailed
            if let frameDetail = frame.detail {
                detail = frameDetail
            } else if let pid = selectedPid, !frame.rows.contains(where: { $0.pid == pid }) {
                selectedPid = nil
                detail = nil
                if quitPhase == .quitting {
                    quitPhase = .idle
                    quitMessage = nil
                }
            }
            loadState = .ready
        case .failure:
            if snapshot == nil {
                loadState = .failed
            }
        }
    }
}
