import SwiftUI

struct ContentView: View {
    var body: some View {
        MemoryDashboardView()
            .frame(minWidth: 880, minHeight: 560)
    }
}

#Preview {
    ContentView()
        .environmentObject(MemoryDashboardVM())
        .frame(width: 1100, height: 720)
}
