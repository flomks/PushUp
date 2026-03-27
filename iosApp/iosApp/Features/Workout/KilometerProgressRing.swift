import SwiftUI

/// Circular progress for the current kilometer: 360° = 1 km, start at 12 o'clock, clockwise.
///
/// - Drawing uses meters into the current km; at exact multiples of 1000 m (except 0) the ring reads as **full** so the head stays at 12 o'clock without an empty flash.
/// - Pulsing and tail only depend on **total** distance > 0, not on the lap fraction, so nothing “stops” at 12 o’clock when a lap completes.
struct KilometerProgressRing: View {

    let distanceMeters: Double

    static let ringDiameter: CGFloat = 255
    fileprivate static let trackLineWidth: CGFloat = 2
    fileprivate static let progressLineWidth: CGFloat = 2.8

    @State private var tailRevealProgress: CGFloat = 0
    @State private var didPlayTailIntro = false

    /// Progress along the **current** km for trims and head angle [0, 1]. At exact km boundaries (non-zero total) uses 1 so the stroke stays closed and the head remains at 12 o’clock.
    private var lapProgressDraw: CGFloat {
        let r = distanceMeters.truncatingRemainder(dividingBy: 1000)
        if r < 1e-4 && distanceMeters > 1e-4 {
            return 1
        }
        return CGFloat(r / 1000)
    }

    private static let tailLayerCount = 14
    private static let tailSegmentWidth: CGFloat = 0.018

    var body: some View {
        ZStack {
            Circle()
                .stroke(AppColors.separator.opacity(0.95), lineWidth: Self.trackLineWidth)

            if lapProgressDraw > 0 {
                ForEach(0..<Self.tailLayerCount, id: \.self) { i in
                    let from = max(0, lapProgressDraw - CGFloat(i + 1) * Self.tailSegmentWidth)
                    let to = max(0, lapProgressDraw - CGFloat(i) * Self.tailSegmentWidth)
                    if to > from {
                        let opacity = (0.1 + 0.9 * Double(Self.tailLayerCount - i) / Double(Self.tailLayerCount)) * Double(tailRevealProgress)
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

            KilometerRingHeadMarker(
                distanceMeters: distanceMeters,
                lapProgress: lapProgressDraw
            )
        }
        .frame(width: Self.ringDiameter, height: Self.ringDiameter)
        .animation(.easeOut(duration: 0.08), value: distanceMeters)
        .onAppear {
            if distanceMeters > 0.0001 && !didPlayTailIntro {
                didPlayTailIntro = true
                tailRevealProgress = 1
            }
        }
        .onChange(of: distanceMeters) { old, new in
            guard !didPlayTailIntro else { return }
            if old < 0.0001 && new > 0.0001 {
                didPlayTailIntro = true
                withAnimation(.easeOut(duration: 0.85)) {
                    tailRevealProgress = 1
                }
            }
        }
    }
}

// MARK: - Head marker

private struct KilometerRingHeadMarker: View {
    let distanceMeters: Double
    let lapProgress: CGFloat

    private static let coreDiameter: CGFloat = 13
    private static let haloDiameter: CGFloat = 28

    var body: some View {
        GeometryReader { geo in
            let size = min(geo.size.width, geo.size.height)
            let radius = (size - KilometerProgressRing.progressLineWidth) / 2
            let angle = -CGFloat.pi / 2 + lapProgress * 2 * CGFloat.pi
            let cx = size / 2 + radius * cos(angle)
            let cy = size / 2 + radius * sin(angle)

            // Always animate (including 0 m at lap start); pause only saves work when the ring is unused.
            TimelineView(.animation(minimumInterval: 1 / 30, paused: false)) { context in
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
