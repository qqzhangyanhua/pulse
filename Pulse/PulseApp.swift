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
        .defaultSize(width: 1100, height: 720)
        .windowResizability(.contentMinSize)
        .commands {
            CommandGroup(replacing: .newItem) {}
        }
    }
}
