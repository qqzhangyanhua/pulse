extension MemoryDashboardVM {
    var quitPhase: QuitPhase { sidebar.quitPhase }
    var quitMessage: String? { sidebar.quitMessage }

    /// Baseline for a quit estimate. A failed or missing frame never estimates.
    var quitReleaseBaseline: UInt64? { core.quitReleaseBaseline }

    /// Close the sidebar. The quit store stays unsettled.
    func dismissSidebar() {
        mutateCore { $0.dismissSidebar() }
    }

    func quitSelected() async {
        await runCore { $0.quitSelected() }
    }

    func forceQuitSelected() async {
        await runCore { $0.beginForceQuit() }
    }
}
