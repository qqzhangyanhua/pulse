import Foundation

/// Pages the status item can land on. The main window presents memory, CPU, network, and disk.
/// GPU stays in the enum so a click can force memory instead of following it.
enum DashboardPage: String, Equatable, Sendable, CaseIterable {
    case memory
    case cpu
    case disk
    case network
    case gpu

    /// Memory, CPU, network, and disk are tappable. GPU stays disabled.
    var isSelectable: Bool {
        switch self {
        case .memory, .cpu, .network, .disk:
            return true
        case .gpu:
            return false
        }
    }
}

struct MenuBarNavigation: Equatable, Sendable {
    private(set) var selectedPage: DashboardPage

    init(selectedPage: DashboardPage = .memory) {
        self.selectedPage = selectedPage
    }

    /// Status-item primary click. Always memory, including when the open window was elsewhere.
    mutating func focusMemoryPage() {
        selectedPage = .memory
    }

    /// Main-window tab. Disabled pages are refused and the current page stays put.
    @discardableResult
    mutating func select(_ page: DashboardPage) -> Bool {
        guard page.isSelectable else { return false }
        selectedPage = page
        return true
    }
}

enum MenuBarDotKind: Equatable, Sendable {
    /// Calm green. Not a "safe" badge and not a third alarm color.
    case calmGreen
    /// Calm amber. Elevated pressure stays short of alarm red.
    case calmAmber
    /// No snapshot yet, or the latest sample failed. Never drawn as a fake normal.
    case unavailable
}

struct MenuBarDotColor: Equatable, Sendable {
    let red: Double
    let green: Double
    let blue: Double

    /// Same sRGB as `PulsePalette.pressureNormal`.
    static let calmGreen = MenuBarDotColor(red: 0.22, green: 0.80, blue: 0.48)
    /// Same sRGB as `PulsePalette.pressureElevated`.
    static let calmAmber = MenuBarDotColor(red: 0.96, green: 0.62, blue: 0.20)
    /// Same sRGB as `PulsePalette.cached`.
    static let unavailable = MenuBarDotColor(red: 0.58, green: 0.59, blue: 0.63)

    /// Alarm red is intentionally not a menu-bar color. Amber stays above this green floor.
    var isAlarmRed: Bool {
        red >= 0.85 && green <= 0.40 && blue <= 0.40
    }
}

enum MenuBarCopy {
    static let unavailableTooltip = "暂时读不到"
    static let quitTitle = "退出 Pulse"
    static let openPulseTitle = "打开 Pulse"
    static let processesEmpty = "暂无进程"
}

struct MenuBarDot: Equatable, Sendable {
    let kind: MenuBarDotKind
    let color: MenuBarDotColor
    /// Nil while a real pressure reading is showing. The bar itself never carries wording.
    let tooltip: String?
    /// Status items can draw a title next to the image. This stays empty.
    let statusItemTitle: String

    static let unavailable = MenuBarDot(
        kind: .unavailable,
        color: .unavailable,
        tooltip: MenuBarCopy.unavailableTooltip,
        statusItemTitle: ""
    )

    static func resolve(pressure: PressureLevel?, samplingFailed: Bool) -> MenuBarDot {
        guard !samplingFailed, let pressure else {
            return .unavailable
        }
        switch pressure {
        case .normal:
            return MenuBarDot(
                kind: .calmGreen,
                color: .calmGreen,
                tooltip: nil,
                statusItemTitle: ""
            )
        case .elevated:
            return MenuBarDot(
                kind: .calmAmber,
                color: .calmAmber,
                tooltip: nil,
                statusItemTitle: ""
            )
        }
    }
}

enum MenuBarStatusItemAction: Equatable, Sendable {
    /// Strip B. Primary click shows the popover; it does not open the main window.
    case showPopover
    /// Secondary click / Control-click. Same quit item as ⌘Q.
    case showQuitMenu
}

enum MenuBarPointer: Equatable, Sendable {
    case primary
    case secondary

    static func classify(isSecondaryClick: Bool, controlDown: Bool) -> MenuBarPointer {
        if isSecondaryClick || controlDown { return .secondary }
        return .primary
    }

    var statusItemAction: MenuBarStatusItemAction {
        switch self {
        case .primary:
            return .showPopover
        case .secondary:
            return .showQuitMenu
        }
    }

    var showsQuitMenu: Bool { statusItemAction == .showQuitMenu }
    var showsPopover: Bool { statusItemAction == .showPopover }
}

/// Locked strip B slots. Live values come from `MenuBarPopoverSnapshot`.
enum MenuBarPopoverSection: String, Equatable, Sendable, CaseIterable, Identifiable {
    case hostPressure
    case topProcesses
    case openPulse

    var id: String { rawValue }
}

enum MenuBarPopoverShell {
    /// Memory Top N. The projection never pads up to this count.
    static let maxProcessRows = 3

    static var sections: [MenuBarPopoverSection] {
        Array(MenuBarPopoverSection.allCases)
    }

    /// Calm empty copy. Never a fake "正常" or a 0-byte process row.
    static func placeholder(for section: MenuBarPopoverSection) -> String {
        switch section {
        case .hostPressure:
            return MenuBarCopy.unavailableTooltip
        case .topProcesses:
            return MenuBarCopy.processesEmpty
        case .openPulse:
            return MenuBarCopy.openPulseTitle
        }
    }
}

/// One strip-B process row. Identity is pid; the surface only shows name + memory.
struct MenuBarPopoverProcess: Equatable, Sendable, Identifiable {
    var id: Int32 { pid }

    let pid: Int32
    let name: String
    let memoryBytes: UInt64
}

/// Read-only strip B. Same `snapshot` / `rows` the main window and color-dot A already read.
struct MenuBarPopoverSnapshot: Equatable, Sendable {
    /// Nil when there is no snapshot or the latest sample failed. Never a fake `.normal`.
    let pressure: PressureLevel?
    /// Nil when there is no snapshot or the latest sample failed. Never a fake 0.
    let usedBytes: UInt64?
    /// At most `MenuBarPopoverShell.maxProcessRows`, memory descending. Empty — never padded.
    let processes: [MenuBarPopoverProcess]

    static let empty = MenuBarPopoverSnapshot(pressure: nil, usedBytes: nil, processes: [])

    var pressureLine: String {
        guard let pressure else {
            return MenuBarPopoverShell.placeholder(for: .hostPressure)
        }
        return Self.pressureLine(for: pressure)
    }

    /// Product copy: "已用" + `ByteFormat.memory`. Missing / failed → "暂时读不到", never "已用 0 GB".
    var usedMemoryLine: String {
        guard let usedBytes else {
            return MenuBarCopy.unavailableTooltip
        }
        return Self.usedMemoryLine(for: usedBytes)
    }

    var processesEmptyCopy: String? {
        processes.isEmpty ? MenuBarPopoverShell.placeholder(for: .topProcesses) : nil
    }

    static func pressureLine(for pressure: PressureLevel) -> String {
        "\(pressure.title) · \(pressure.caption)"
    }

    static func usedMemoryLine(for usedBytes: UInt64) -> String {
        "已用 \(ByteFormat.memory(usedBytes))"
    }

    static func project(
        pressure: PressureLevel?,
        usedBytes: UInt64?,
        samplingFailed: Bool,
        rows: [ProcessRow],
        processListFailed: Bool
    ) -> MenuBarPopoverSnapshot {
        let hostReadable = !samplingFailed
        let resolvedPressure = hostReadable ? pressure : nil
        let resolvedUsedBytes = hostReadable ? usedBytes : nil
        let processes = processListFailed ? [] : topProcesses(from: rows)
        return MenuBarPopoverSnapshot(
            pressure: resolvedPressure,
            usedBytes: resolvedUsedBytes,
            processes: processes
        )
    }

    /// Sampler already sorts this way; the projection repeats it so a caller cannot
    /// accidentally feed the main-window table sort or a filtered slice.
    static func topProcesses(from rows: [ProcessRow]) -> [MenuBarPopoverProcess] {
        rows
            .sorted { lhs, rhs in
                if lhs.memoryBytes != rhs.memoryBytes {
                    return lhs.memoryBytes > rhs.memoryBytes
                }
                return lhs.pid < rhs.pid
            }
            .prefix(MenuBarPopoverShell.maxProcessRows)
            .map { row in
                MenuBarPopoverProcess(pid: row.pid, name: row.name, memoryBytes: row.memoryBytes)
            }
    }
}

/// Foreground pace only while the main window is on screen and the app is active.
/// Closing the window keeps the same sampler and lengthens the interval.
struct MenuBarSamplingGate: Equatable, Sendable {
    var sceneActive: Bool
    var mainWindowVisible: Bool

    var isForeground: Bool {
        sceneActive && mainWindowVisible
    }

    var step: SamplingStep {
        SamplingPace.step(isForeground: isForeground)
    }
}

enum MenuBarLifecycle {
    /// `NSApplication` would otherwise follow SwiftUI and quit when the last window closes.
    /// The status item has to outlive that window. ⌘Q still terminates.
    static let terminateAfterLastWindowClosed = false
}
