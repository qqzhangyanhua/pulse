import SwiftUI

/// 4 pt capsule track shared by the GPU memory, share, and frequency bars.
/// A non-positive fraction leaves the fill off. Hidden from VoiceOver so nearby text keeps the real value.
struct FractionCapsuleTrack: View {
    var fraction: Double

    var body: some View {
        GeometryReader { proxy in
            track(width: proxy.size.width)
        }
        .frame(height: 4)
        .accessibilityHidden(true)
    }

    private func track(width: CGFloat) -> some View {
        let clamped = min(max(fraction, 0), 1)
        return ZStack(alignment: .leading) {
            Capsule().fill(Color.white.opacity(0.08))
            if clamped > 0 {
                Capsule()
                    .fill(PulsePalette.accent)
                    .frame(width: width * CGFloat(clamped))
            }
        }
    }
}
