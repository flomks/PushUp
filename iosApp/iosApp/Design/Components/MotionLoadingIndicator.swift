import SwiftUI

struct MotionLoadingIndicator: View {
    let tint: Color
    let lineCount: Int
    let lineWidth: CGFloat
    let height: CGFloat
    let speed: Double

    init(
        tint: Color = Color(red: 0.13, green: 0.81, blue: 0.41),
        lineCount: Int = 5,
        lineWidth: CGFloat = 4,
        height: CGFloat = 18,
        speed: Double = 1.0
    ) {
        self.tint = tint
        self.lineCount = max(lineCount, 3)
        self.lineWidth = lineWidth
        self.height = height
        self.speed = speed
    }

    var body: some View {
        TimelineView(.animation) { timeline in
            let time = timeline.date.timeIntervalSinceReferenceDate * speed

            HStack(alignment: .center, spacing: lineWidth * 0.8) {
                ForEach(0..<lineCount, id: \.self) { index in
                    let amplitude = barAmplitude(at: index, time: time)
                    Capsule(style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [
                                    tint.opacity(0.32),
                                    tint.opacity(0.72),
                                    tint
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .frame(
                            width: lineWidth,
                            height: max(height * amplitude, height * 0.28)
                        )
                }
            }
            .frame(height: height)
            .drawingGroup()
        }
        .accessibilityHidden(true)
    }

    private func barAmplitude(at index: Int, time: Double) -> CGFloat {
        let phase = Double(index) * 0.55
        let waveA = sin(time * 4.8 + phase)
        let waveB = cos(time * 3.1 - phase * 0.7)
        let raw = 0.56 + (waveA * 0.24) + (waveB * 0.18)
        return CGFloat(min(max(raw, 0.2), 1.0))
    }
}

struct MotionLoadingRow: View {
    let title: String
    let subtitle: String?
    let tint: Color

    init(
        title: String,
        subtitle: String? = nil,
        tint: Color = Color(red: 0.13, green: 0.81, blue: 0.41)
    ) {
        self.title = title
        self.subtitle = subtitle
        self.tint = tint
    }

    var body: some View {
        HStack(spacing: 12) {
            MotionLoadingIndicator(tint: tint)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)

                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(Color.white.opacity(0.48))
                }
            }

            Spacer(minLength: 0)
        }
    }
}
