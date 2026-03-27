import SwiftUI

/// Circular progress for the current kilometer: 360° = 1 km, start at 12 o'clock, clockwise.
struct KilometerProgressRing: View {

    /// Total distance; progress within the current km uses `truncatingRemainder(dividingBy: 1000)`.
    let distanceMeters: Double

    static let ringDiameter: CGFloat = 255
    private static let trackLineWidth: CGFloat = 2
    private static let progressLineWidth: CGFloat = 2.8
    private static let headDotDiameter: CGFloat = 8

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

            headDot
        }
        .frame(width: Self.ringDiameter, height: Self.ringDiameter)
    }

    private var headDot: some View {
        GeometryReader { geo in
            let size = min(geo.size.width, geo.size.height)
            let r = (size - Self.progressLineWidth) / 2
            let angle = -CGFloat.pi / 2 + progress01 * 2 * CGFloat.pi
            let cx = size / 2 + r * cos(angle)
            let cy = size / 2 + r * sin(angle)

            Circle()
                .fill(Color.white)
                .frame(width: Self.headDotDiameter, height: Self.headDotDiameter)
                .position(x: cx, y: cy)
                .opacity(progress01 > 0.0001 ? 1 : 0)
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
