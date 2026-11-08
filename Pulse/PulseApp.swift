import AppKit
import SwiftUI

@main
struct PulseApp: App {
    @NSApplicationDelegateAdaptor(PulseAppDelegate.self) private var appDelegate
    @Environment(\.openWindow) private var openWindow

    var body: some Scene {
        // Scene setup, not the window. Zero windows can still open the main window from the status item.
        let openWindow = self.openWindow
        let _ = appDelegate.bindOpenWindow {
            openWindow(id: PulseWindowID.main)
        }
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
                .environmentObject(appDelegate.dashboard)
        }
        .defaultSize(width: 1280, height: 820)
        .windowResizability(.contentMinSize)
        .windowToolbarStyle(.unifiedCompact)
        .commands {
            PulseWindowCommands(dashboard: appDelegate.dashboard)
        }

        Settings {
            PulseSettingsView()
        }
    }
}

private struct PulseWindowCommands: Commands {
    let dashboard: MemoryDashboardVM
    @FocusedValue(\.focusNameFilter) private var focusNameFilter
    @FocusedValue(\.nameFilterFocused) private var nameFilterFocused

    var body: some Commands {
        CommandGroup(replacing: .newItem) {}
        CommandGroup(replacing: .pasteboard) {
            Button("剪切") {
                NSApp.sendAction(#selector(NSText.cut(_:)), to: nil, from: nil)
            }
            .keyboardShortcut("x", modifiers: .command)
            copyProcessRowCommand
            Button("粘贴") {
                NSApp.sendAction(#selector(NSText.paste(_:)), to: nil, from: nil)
            }
            .keyboardShortcut("v", modifiers: .command)
            Button("全选") {
                NSApp.sendAction(#selector(NSText.selectAll(_:)), to: nil, from: nil)
            }
            .keyboardShortcut("a", modifiers: .command)
        }
        CommandMenu("视图") {
            Button("内存") { dashboard.selectPage(.memory) }
                .keyboardShortcut("1", modifiers: .command)
            Button("CPU") { dashboard.selectPage(.cpu) }
                .keyboardShortcut("2", modifiers: .command)
            Button("磁盘") { dashboard.selectPage(.disk) }
                .keyboardShortcut("3", modifiers: .command)
            Button("网络") { dashboard.selectPage(.network) }
                .keyboardShortcut("4", modifiers: .command)
            Button("本机") { dashboard.selectPage(.machine) }
                .keyboardShortcut("5", modifiers: .command)
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
        .disabled(!dashboard.selectedPage.allowsProcessQuit)
    }

    /// ⌘C stays with the name filter. An empty selection returns before the pasteboard.
    @ViewBuilder
    private var copyProcessRowCommand: some View {
        if nameFilterFocused == true {
            copyProcessRowButton
        } else {
            copyProcessRowButton
                .keyboardShortcut("c", modifiers: .command)
        }
    }

    private var copyProcessRowButton: some View {
        Button("复制") {
            copySelectedProcessRow()
        }
        .disabled(copyProcessRowDisabled)
    }

    private var copyProcessRowDisabled: Bool {
        nameFilterFocused != true && dashboard.selectedRow == nil
    }

    private func copySelectedProcessRow() {
        if nameFilterFocused == true {
            NSApp.sendAction(#selector(NSText.copy(_:)), to: nil, from: nil)
            return
        }
        guard let row = dashboard.selectedRow else { return }
        let line = ProcessRowCopy.line(page: dashboard.selectedPage, row: row)
        switch dashboard.selectedPage {
        case .memory, .cpu, .disk, .network:
            break
        case .machine, .gpu:
            return
        }
        let board = NSPasteboard.general
        board.clearContents()
        board.setString(line, forType: .string)
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
