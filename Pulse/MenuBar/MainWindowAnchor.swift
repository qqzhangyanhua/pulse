import AppKit
import SwiftUI

/// Tags the main window and reports open/close so the status item can keep sampling after the window goes away.
struct MainWindowAnchor: NSViewRepresentable {
    let delegate: PulseAppDelegate

    func makeCoordinator() -> Coordinator {
        Coordinator(delegate: delegate)
    }

    func makeNSView(context: Context) -> AnchorView {
        let view = AnchorView(frame: .zero)
        view.onWindow = { [weak coordinator = context.coordinator] window in
            MainActor.assumeIsolated {
                coordinator?.attach(window)
            }
        }
        return view
    }

    func updateNSView(_ nsView: AnchorView, context: Context) {
        if let window = nsView.window {
            context.coordinator.attach(window)
        }
    }

    static func dismantleNSView(_ nsView: AnchorView, coordinator: Coordinator) {
        coordinator.detach()
    }

    @MainActor
    final class Coordinator {
        let delegate: PulseAppDelegate
        private var attached: ObjectIdentifier?
        private var reported = false
        private var closeObserver: NSObjectProtocol?

        init(delegate: PulseAppDelegate) {
            self.delegate = delegate
        }

        func attach(_ window: NSWindow) {
            let id = ObjectIdentifier(window)
            guard attached != id else { return }
            releaseAttachment()
            attached = id
            window.identifier = NSUserInterfaceItemIdentifier(PulseWindowID.main)
            closeObserver = NotificationCenter.default.addObserver(
                forName: NSWindow.willCloseNotification,
                object: window,
                queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.releaseAttachment()
                }
            }
            delegate.noteMainWindow(id, change: 1)
            reported = true
        }

        func detach() {
            releaseAttachment()
        }

        private func releaseAttachment() {
            if let closeObserver {
                NotificationCenter.default.removeObserver(closeObserver)
                self.closeObserver = nil
            }
            if reported, let attached {
                delegate.noteMainWindow(attached, change: -1)
            }
            reported = false
            attached = nil
        }
    }
}

final class AnchorView: NSView {
    var onWindow: ((NSWindow) -> Void)?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let window {
            onWindow?(window)
        }
    }
}
