import Foundation

/// Memory-tab toolbar chrome for the windowed-app keep. Session-only.
enum WindowedAppChrome {
    static let toggleTitle = "仅窗口 App"
    static let help = "只留下可以打开窗口的 App。"

    static func showsToggle(page: DashboardPage) -> Bool {
        page == .memory
    }
}

/// Memory-page projection. Name filter and the rising keep run first.
/// OFF, and every non-memory page, return the rows unchanged.
enum WindowedAppFilter {
    static func apply(
        rows: [ProcessRow],
        page: DashboardPage,
        windowedOnly: Bool,
        windowedPids: Set<Int32>
    ) -> [ProcessRow] {
        guard windowedOnly, page == .memory else { return rows }
        return rows.filter { windowedPids.contains($0.pid) }
    }

    /// ON drops a pid that cannot open a window. OFF does not restore one.
    static func selectedPid(
        current: Int32?,
        page: DashboardPage,
        windowedOnly: Bool,
        windowedPids: Set<Int32>
    ) -> Int32? {
        guard let current else { return nil }
        guard windowedOnly, page == .memory else { return current }
        return windowedPids.contains(current) ? current : nil
    }
}
