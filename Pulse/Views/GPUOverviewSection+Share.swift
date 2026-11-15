import SwiftUI

extension GPUOverviewSection {
    /// Side by side from about 760 pt, with the share card at 340 pt. Narrower, the share card drops below.
    var chartAndShare: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: 12) {
                chartCard
                GPUShareCard()
                    .frame(width: 340)
            }
            .frame(minWidth: 760)
            VStack(alignment: .leading, spacing: 12) {
                chartCard
                GPUShareCard()
            }
        }
    }
}
