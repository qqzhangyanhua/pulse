import SwiftUI

@main
struct PulseApp: App {
    var body: some Scene {
        WindowGroup("Pulse") {
            ContentView()
        }
    }
}

struct ContentView: View {
    var body: some View {
        Text("Pulse — memory diagnostic shell")
            .frame(minWidth: 880, minHeight: 560)
    }
}
