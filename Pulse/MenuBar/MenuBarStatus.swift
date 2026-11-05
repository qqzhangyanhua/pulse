import Foundation

/// Pages the status item can land on. The main window presents memory and CPU.
/// Disk, network, and GPU stay in the enum so a click can force memory instead of following them.
enum DashboardPage: String, Equatable, Sendable, CaseIterable {
    case memory
    case cpu
    case disk
    case network
    case gpu

    /// CPU is tappable. Disk, network, and GPU stay disabled.
    var isSelectable: Bool {
        switch self {
        case .memory, .cpu:
            return true
        case .disk, .network, .gpu:
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

enum MenuBarPointer: Equatable, Sendable {
    case primary
    case secondary

    static func classify(isSecondaryClick: Bool, controlDown: Bool) -> MenuBarPointer {
        if isSecondaryClick || controlDown { return .secondary }
        return .primary
    }

    /// Secondary click is the quit menu. Primary click focuses the memory page and does not open a panel.
    var showsQuitMenu: Bool { self == .secondary }
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
