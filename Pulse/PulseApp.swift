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
            PulseWindowCommands(dashboard: dashboard)
        }
    }
}

private struct PulseWindowCommands: Commands {
    let dashboard: MemoryDashboardVM
    @FocusedValue(\.focusNameFilter) private var focusNameFilter
    @FocusedValue(\.nameFilterFocused) private var nameFilterFocused

    var body: some Commands {
        CommandGroup(replacing: .newItem) {}
        CommandMenu("视图") {
            Button("内存") { dashboard.selectPage(.memory) }
                .keyboardShortcut("1", modifiers: .command)
            Button("CPU") { dashboard.selectPage(.cpu) }
                .keyboardShortcut("2", modifiers: .command)
            Button("磁盘") { dashboard.selectPage(.disk) }
                .keyboardShortcut("3", modifiers: .command)
            Button("网络") { dashboard.selectPage(.network) }
                .keyboardShortcut("4", modifiers: .command)
            Divider()
            Button("过滤名称") {
                focusNameFilter?()
            }
            .keyboardShortcut("f", modifiers: .command)
            .disabled(focusNameFilter == nil)
            ordinaryQuitCommand()
        }
        CommandGroup(replacing: .appTermination) {
            Button(action: { NSApp.terminate(nil) }) {
                Text(verbatim: MenuBarCopy.quitTitle)
            }
            .keyboardShortcut("q")
        }
    }

    /// Omit the key equivalent while the name filter is focused so the field keeps delete-to-line-start.
    @ViewBuilder
    private func ordinaryQuitCommand() -> some View {
        if nameFilterFocused == true {
            quitSelectedButton
        } else {
            quitSelectedButton
                .keyboardShortcut(.delete, modifiers: .command)
        }
    }

    private var quitSelectedButton: some View {
        Button("退出选中进程") {
            Task { await dashboard.quitSelected() }
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
