import AppKit
import Combine

/// In-process status item. One shared `MemoryDashboardVM` feeds the dot; this type does not sample.
///
/// `MenuBarExtra` is the wrong surface for interaction A: `.menu` opens a menu and `.window` opens a
/// floating panel. Primary click has to focus the main window, with quit only on the secondary click.
/// `NSStatusItem` stays in this process (`activationPolicy` remains `.regular`; no helper, no XPC).
@MainActor
final class MenuBarController: NSObject {
    private var statusItem: NSStatusItem?
    private var cancellable: AnyCancellable?
    private var rendered: MenuBarDot?
    private var currentDot: @MainActor () -> MenuBarDot = { .unavailable }
    private var onFocusMemory: @MainActor () -> Void = {}
    private var onQuit: @MainActor () -> Void = {}

    func install(
        currentDot: @escaping @MainActor () -> MenuBarDot,
        onFocusMemory: @escaping @MainActor () -> Void,
        onQuit: @escaping @MainActor () -> Void
    ) {
        self.currentDot = currentDot
        self.onFocusMemory = onFocusMemory
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
        cancellable = dashboard.objectWillChange.sink { [weak self] _ in
            Task { @MainActor in
                self?.render()
            }
        }
        render()
    }

    /// ⌘Q and 「退出 Pulse」 both end here, via `applicationWillTerminate`.
    func uninstall() {
        cancellable = nil
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
        if pointer.showsQuitMenu {
            presentQuitMenu(from: sender)
        } else {
            onFocusMemory()
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
