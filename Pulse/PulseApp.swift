import SwiftUI

@main
struct PulseApp: App {
    @StateObject private var dashboard = MemoryDashboardVM()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup("Pulse") {
            ContentView()
                .environmentObject(dashboard)
                .onChange(of: scenePhase) { _, phase in
                    dashboard.setForeground(phase == .active)
                }
        }
        .defaultSize(width: 1280, height: 820)
        .windowResizability(.contentMinSize)
        .windowToolbarStyle(.unifiedCompact)
        .commands {
            CommandGroup(replacing: .newItem) {}
        }
    }
}
