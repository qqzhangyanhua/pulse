import AppKit
import SwiftUI

@main
struct PulseApp: App {
    @NSApplicationDelegateAdaptor(PulseAppDelegate.self) private var appDelegate
    @StateObject private var dashboard = MemoryDashboardVM()

    var body: some Scene {
        WindowGroup("Pulse", id: PulseWindowID.main) {
            ContentView()
                .background {
                    ZStack {
                        OpenWindowHook(delegate: appDelegate)
                        ScenePaceBridge { appDelegate.noteSceneActive($0) }
                        MainWindowAnchor(delegate: appDelegate)
                    }
                    .allowsHitTesting(false)
                }
                .environmentObject(dashboard)
        }
        .defaultSize(width: 1280, height: 820)
        .windowResizability(.contentMinSize)
        .windowToolbarStyle(.unifiedCompact)
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandGroup(replacing: .appTermination) {
                Button(action: { NSApp.terminate(nil) }) {
                    Text(verbatim: MenuBarCopy.quitTitle)
                }
                .keyboardShortcut("q")
            }
        }
    }
}

private struct OpenWindowHook: View {
    let delegate: PulseAppDelegate
    @Environment(\.openWindow) private var openWindow
    @EnvironmentObject private var dashboard: MemoryDashboardVM

    var body: some View {
        Color.clear
            .onAppear {
                delegate.bind(dashboard) {
                    openWindow(id: PulseWindowID.main)
                }
            }
    }
}

private struct ScenePaceBridge: View {
    @Environment(\.scenePhase) private var scenePhase
    let onActive: (Bool) -> Void

    var body: some View {
        Color.clear
            .onAppear { onActive(scenePhase == .active) }
            .onChange(of: scenePhase) { _, phase in
                onActive(phase == .active)
            }
    }
}
