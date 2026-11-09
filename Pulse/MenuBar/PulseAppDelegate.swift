import AppKit
import Combine

enum PulseWindowID {
    static let main = "pulse-main"
}

/// Main-thread delegate. Owns the one dashboard for the process.
/// Closing the last window does not terminate; ⌘Q does, and removes the status item.
@MainActor
final class PulseAppDelegate: NSObject, NSApplicationDelegate, ObservableObject {
    let dashboard = MemoryDashboardVM()
    private let menuBar = MenuBarController()
    private let pressureNotices = PressureNoticeCenter()
    private var openMainWindow: (() -> Void)?
    private var gate = MenuBarSamplingGate(sceneActive: true, mainWindowVisible: false)
    /// Attachments still reporting a live main window. A closing window decrements once.
    private var visibleMainWindows: [ObjectIdentifier: Int] = [:]
    private var dashboardChanges: AnyCancellable?

    override init() {
        super.init()
        dashboardChanges = dashboard.objectWillChange.sink { [weak self] _ in
            MainActor.assumeIsolated {
                self?.objectWillChange.send()
            }
        }
    }

    nonisolated func applicationDidFinishLaunching(_ notification: Notification) {
        MainActor.assumeIsolated {
            self.didLaunch()
        }
    }

    nonisolated func applicationWillTerminate(_ notification: Notification) {
        MainActor.assumeIsolated {
            self.menuBar.uninstall()
        }
    }

    nonisolated func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        MenuBarLifecycle.terminateAfterLastWindowClosed
    }

    nonisolated func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            MainActor.assumeIsolated {
                self.focusMemoryPage()
            }
        }
        return true
    }

    private func didLaunch() {
        NSApp.setActivationPolicy(.regular)
        menuBar.install(
            currentDot: { [weak self] in self?.currentDot() ?? .unavailable },
            onOpenPulse: { [weak self] in self?.focusMemoryPage() },
            onQuit: {
                DispatchQueue.main.async {
                    NSApp.terminate(nil)
                }
            }
        )
        installPressureNotices()
        startSampling()
    }

    private func installPressureNotices() {
        pressureNotices.install { [weak self] in
            self?.focusMemoryPage()
        }
    }

    /// Status item 「打开 Pulse」 with zero windows. The app scene installs this; a window is not required.
    func bindOpenWindow(_ openWindow: @escaping () -> Void) {
        openMainWindow = openWindow
    }

    func bind(_ dashboard: MemoryDashboardVM, openWindow: @escaping () -> Void) {
        precondition(dashboard === self.dashboard)
        openMainWindow = openWindow
        startSampling()
    }

    /// Idempotent. Pace follows the gate: a hidden window keeps the background interval.
    private func startSampling() {
        dashboard.start()
        menuBar.observe(dashboard)
        pressureNotices.observe(dashboard)
        applyPace()
    }

    func noteSceneActive(_ active: Bool) {
        gate.sceneActive = active
        applyPace()
    }

    func noteMainWindow(_ id: ObjectIdentifier, change: Int) {
        let next = (visibleMainWindows[id] ?? 0) + change
        if next <= 0 {
            visibleMainWindows[id] = nil
        } else {
            visibleMainWindows[id] = next
        }
        gate.mainWindowVisible = !visibleMainWindows.isEmpty
        applyPace()
    }

    /// Unique open / focus path for 「打开 Pulse」. Lands on the memory page.
    /// Does not write `selectedPid`. Select-if-present is `MemoryDashboardVM.selectPidIfPresent`.
    func focusMemoryPage() {
        dashboard.focusMemoryPage()
        NSApp.activate()
        if let window = NSApp.windows.first(where: { candidate in
            candidate.identifier?.rawValue == PulseWindowID.main
                && (candidate.isVisible || candidate.isMiniaturized)
        }) {
            if window.isMiniaturized {
                window.deminiaturize(nil)
            }
            window.makeKeyAndOrderFront(nil)
            gate.sceneActive = true
            applyPace()
            return
        }
        openMainWindow?()
        gate.sceneActive = true
        applyPace()
    }

    private func applyPace() {
        // Same sampler as #10. Background (hidden or window closed) only lengthens the interval.
        dashboard.setForeground(gate.isForeground)
    }

    private func currentDot() -> MenuBarDot {
        MenuBarDot.resolve(
            pressure: dashboard.snapshot?.pressure,
            samplingFailed: dashboard.samplingFailed
        )
    }
}
