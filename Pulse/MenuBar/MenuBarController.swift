import AppKit
import Combine
import SwiftUI

/// In-process status item. One shared `MemoryDashboardVM` feeds the dot and strip B;
/// this type does not sample.
///
/// `MenuBarExtra` is the wrong surface: `.menu` opens a menu and `.window` opens a second
/// floating panel. Interaction A stays a color dot. Primary click shows strip B as an
/// `NSPopover` on this button; 「打开 Pulse」 focuses the existing main window. Quit stays
/// on the secondary click. `activationPolicy` remains `.regular` (no helper, no XPC).
@MainActor
final class MenuBarController: NSObject, NSPopoverDelegate {
    private var statusItem: NSStatusItem?
    private var cancellable: AnyCancellable?
    private weak var dashboard: MemoryDashboardVM?
    private var rendered: MenuBarDot?
    private var currentDot: @MainActor () -> MenuBarDot = { .unavailable }
    private var onOpenPulse: @MainActor () -> Void = {}
    private var onQuit: @MainActor () -> Void = {}
    private var popover: NSPopover?
    /// Transient popovers close on the mouse-down that also hits the status button.
    /// Ignore that same click so the strip does not bounce back open.
    private var popoverClosedAt: Date?

    func install(
        currentDot: @escaping @MainActor () -> MenuBarDot,
        onOpenPulse: @escaping @MainActor () -> Void,
        onQuit: @escaping @MainActor () -> Void
    ) {
        self.currentDot = currentDot
        self.onOpenPulse = onOpenPulse
        self.onQuit = onQuit
        if statusItem == nil {
            let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
            item.button?.imagePosition = .imageOnly
            item.button?.title = ""
            item.button?.target = self
            item.button?.action = #selector(handleClick(_:))
            item.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
            item.button?.setAccessibilityLabel("Pulse")
            statusItem = item
        }
        render()
    }

    func observe(_ dashboard: MemoryDashboardVM) {
        self.dashboard = dashboard
        cancellable = dashboard.objectWillChange.sink { [weak self] _ in
            Task { @MainActor in
                self?.render()
            }
        }
        render()
    }

    /// ⌘Q and 「退出 Pulse」 both end here, via `applicationWillTerminate`.
    func uninstall() {
        dismissPopover()
        cancellable = nil
        dashboard = nil
        rendered = nil
        guard let statusItem else { return }
        NSStatusBar.system.removeStatusItem(statusItem)
        self.statusItem = nil
    }

    private func render() {
        let dot = currentDot()
        guard let button = statusItem?.button else { return }
        button.title = dot.statusItemTitle
        button.imagePosition = .imageOnly
        button.toolTip = dot.tooltip
        guard dot != rendered else { return }
        rendered = dot
        let image = MenuBarDotImage.make(dot)
        image.isTemplate = false
        button.image = image
    }

    @objc nonisolated private func handleClick(_ sender: NSStatusBarButton) {
        MainActor.assumeIsolated {
            self.handleClickOnMain(sender)
        }
    }

    private func handleClickOnMain(_ sender: NSStatusBarButton) {
        let event = NSApp.currentEvent
        let type = event?.type
        let pointer = MenuBarPointer.classify(
            isSecondaryClick: type == .rightMouseUp,
            controlDown: event?.modifierFlags.contains(.control) ?? false
        )
        switch pointer.statusItemAction {
        case .showQuitMenu:
            dismissPopover()
            presentQuitMenu(from: sender)
        case .showPopover:
            togglePopover(from: sender)
        }
    }

    private func togglePopover(from button: NSStatusBarButton) {
        if let popover, popover.isShown {
            dismissPopover()
            return
        }
        if let popoverClosedAt, Date().timeIntervalSince(popoverClosedAt) < 0.3 {
            return
        }
        presentPopover(from: button)
    }

    private func presentPopover(from button: NSStatusBarButton) {
        guard let dashboard else { return }
        let popover = NSPopover()
        popover.behavior = .transient
        popover.animates = true
        popover.delegate = self
        let hosting = NSHostingController(
            rootView: MenuBarPopoverView(dashboard: dashboard) { [weak self] in
                self?.openPulse()
            }
        )
        hosting.sizingOptions = .preferredContentSize
        popover.contentViewController = hosting
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        self.popover = popover
    }

    private func openPulse() {
        dismissPopover()
        onOpenPulse()
    }

    private func dismissPopover() {
        guard let popover else { return }
        popover.delegate = nil
        popover.performClose(nil)
        self.popover = nil
    }

    func popoverDidClose(_ notification: Notification) {
        popoverClosedAt = Date()
        if let closing = notification.object as? NSPopover, closing == popover {
            popover = nil
        }
    }

    private func presentQuitMenu(from button: NSStatusBarButton) {
        let menu = NSMenu()
        let quit = NSMenuItem(title: MenuBarCopy.quitTitle, action: #selector(quit(_:)), keyEquivalent: "")
        quit.target = self
        menu.addItem(quit)
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: button.bounds.height), in: button)
    }

    @objc nonisolated private func quit(_ sender: NSMenuItem) {
        MainActor.assumeIsolated {
            self.onQuit()
        }
    }
}

enum MenuBarDotImage {
    static func make(_ dot: MenuBarDot) -> NSImage {
        let side: CGFloat = 18
        let image = NSImage(size: NSSize(width: side, height: side), flipped: false) { rect in
            let rgb = dot.color
            NSColor(srgbRed: rgb.red, green: rgb.green, blue: rgb.blue, alpha: 1).setFill()
            let diameter: CGFloat = 8
            let dotRect = NSRect(
                x: rect.midX - diameter / 2,
                y: rect.midY - diameter / 2,
                width: diameter,
                height: diameter
            )
            NSBezierPath(ovalIn: dotRect).fill()
            return true
        }
        image.isTemplate = false
        return image
    }
}
