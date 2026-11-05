import SwiftUI

struct ContentView: View {
    var body: some View {
        NavigationStack {
            MemoryDashboardView()
                .background(PulsePalette.windowBackground)
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
