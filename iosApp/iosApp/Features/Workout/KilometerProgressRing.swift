import SwiftUI

/// Circular progress for the current kilometer: 360° = 1 km, start at 12 o'clock, clockwise.
struct KilometerProgressRing: View {

    /// Total distance; progress within the current km uses `truncatingRemainder(dividingBy: 1000)`.
    let distanceMeters: Double

    static let ringDiameter: CGFloat = 255
    fileprivate static let trackLineWidth: CGFloat = 2
    fileprivate static let progressLineWidth: CGFloat = 2.8

    private var progress01: CGFloat {
        let d = distanceMeters.truncatingRemainder(dividingBy: 1000)
        return CGFloat(d / 1000)
    }

    private static let tailLayerCount = 14
    private static let tailSegmentWidth: CGFloat = 0.018

    var body: some View {
        ZStack {
            Circle()
                .stroke(AppColors.separator.opacity(0.95), lineWidth: Self.trackLineWidth)

            if progress01 > 0.0001 {
                ForEach(0..<Self.tailLayerCount, id: \.self) { i in
                    let from = max(0, progress01 - CGFloat(i + 1) * Self.tailSegmentWidth)
                    let to = max(0, progress01 - CGFloat(i) * Self.tailSegmentWidth)
                    if to > from {
                        let opacity = 0.1 + 0.9 * Double(Self.tailLayerCount - i) / Double(Self.tailLayerCount)
                        Circle()
                            .trim(from: from, to: to)
                            .stroke(
                                Color.white.opacity(opacity),
                                style: StrokeStyle(lineWidth: Self.progressLineWidth, lineCap: .round)
                            )
                            .rotationEffect(.degrees(-90))
                    }
                }
            }

            KilometerRingHeadMarker(progress01: progress01)
        }
        .frame(width: Self.ringDiameter, height: Self.ringDiameter)
        .animation(.easeOut(duration: 0.08), value: distanceMeters)
    }
}

// MARK: - Head marker

private struct KilometerRingHeadMarker: View {
    let progress01: CGFloat

    private static let coreDiameter: CGFloat = 13
    private static let haloDiameter: CGFloat = 28

    var body: some View {
        GeometryReader { geo in
            let size = min(geo.size.width, geo.size.height)
            let radius = (size - KilometerProgressRing.progressLineWidth) / 2
            let angle = -CGFloat.pi / 2 + progress01 * 2 * CGFloat.pi
            let cx = size / 2 + radius * cos(angle)
            let cy = size / 2 + radius * sin(angle)

            TimelineView(.animation(minimumInterval: 1 / 30, paused: progress01 <= 0.0001)) { context in
                let t = context.date.timeIntervalSinceReferenceDate
                let breath = 1.0 + 0.18 * sin(t * 2 * .pi / 1.25)
                let haloPulse = 1.0 + 0.12 * sin(t * 2 * .pi / 1.25 + 0.4)

                ZStack {
                    Circle()
                        .fill(Color.white.opacity(0.22 + 0.18 * sin(t * 2 * .pi / 1.25)))
                        .frame(width: Self.haloDiameter, height: Self.haloDiameter)
                        .scaleEffect(haloPulse)

                    Circle()
                        .stroke(Color.white.opacity(0.95), lineWidth: 2.2)
                        .frame(width: Self.coreDiameter + 5, height: Self.coreDiameter + 5)
                        .scaleEffect(breath)

                    Circle()
                        .fill(Color.white)
                        .frame(width: Self.coreDiameter, height: Self.coreDiameter)
                        .shadow(color: Color.white.opacity(0.9), radius: 5 + 4 * sin(t * 2 * .pi / 1.25))
                }
                .position(x: cx, y: cy)
                .opacity(progress01 > 0.0001 ? 1 : 0)
            }
        }
        .allowsHitTesting(false)
    }
}

#if DEBUG
#Preview {
    ZStack {
        Color.black
        KilometerProgressRing(distanceMeters: 350)
    }
}
#endif
