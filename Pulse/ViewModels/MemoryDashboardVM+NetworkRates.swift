import Foundation

extension MemoryDashboardVM {
    var processNetworkRates: [Int32: ProcessNetworkRate] { core.processNetworkRates }

    /// Start `nettop` only while the network page is selected. Leaving stops the child.
    func syncProcessNetworkWatch() {
        guard selectedPage == .network else {
            stopProcessNetworkWatch()
            return
        }
        guard nettopReader == nil else { return }
        let reader = NettopReader()
        nettopReader = reader
        reader.start { [weak self] rates in
            Task {
                await MainActor.run {
                    guard let self, self.selectedPage == .network else { return }
                    self.mutateCore { $0.apply(processNetworkRates: rates) }
                }
            }
        }
    }

    func stopProcessNetworkWatch() {
        nettopReader?.stop()
        nettopReader = nil
    }
}
