import SwiftUI

struct ContentView: View {
    var body: some View {
        NavigationStack {
            MemoryDashboardView()
        }
        .frame(minWidth: 1100, minHeight: 720)
        .preferredColorScheme(.dark)
        .containerBackground(PulsePalette.windowBackground, for: .window)
    }
}

#Preview {
    ContentView()
        .environmentObject(MemoryDashboardVM())
        .frame(width: 1280, height: 820)
}
