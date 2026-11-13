extension MemoryDashboardVM {
    /// One-shot memory Top card reveal. The next locate replaces it.
    var topAppLocateReveal: TopAppLocation.Reveal? { core.topAppLocateReveal }

    /// Memory Top card. A nil plan writes nothing.
    func locateMemoryTopApp(name: String, pid: Int32) {
        mutateCore { $0.locateMemoryTopApp(name: name, pid: pid) }
    }

    /// Tree jump or return. A memory keep that would drop `pid` turns off first.
    func focusProcessFromTree(_ pid: Int32) {
        mutateCore { $0.focusProcessFromTree(pid) }
    }
}
