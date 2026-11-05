import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var vm: MemoryDashboardVM

    var body: some View {
        NavigationStack {
            MemoryDashboardView()
                .background(PulsePalette.windowBackground)
                .onAppear {
                    // Status-item clicks set memory before the window is ordered front.
                    // Other resource pages are not built in this PR, so a stale page snaps back.
                    if vm.selectedPage != .memory {
                        vm.focusMemoryPage()
                    }
                }
        }
        .frame(minWidth: 1100, minHeight: 720)
        .preferredColorScheme(.dark)
        .modifier(PulseWindowBackground())
    }
}

/// `ContainerBackgroundPlacement.window` is macOS 15+. The deployment target stays 14.0,
/// so that placement is applied only when it exists. macOS 14 paints the same dark
/// color on the root view instead; the navigation content above uses it as well.
private struct PulseWindowBackground: ViewModifier {
    func body(content: Content) -> some View {
        if #available(macOS 15, *) {
            content.containerBackground(PulsePalette.windowBackground, for: .window)
        } else {
            content.background(PulsePalette.windowBackground)
        }
    }
}

#Preview {
    ContentView()
        .environmentObject(MemoryDashboardVM())
        .frame(width: 1280, height: 820)
}
