import SwiftUI

// MARK: - FormScoreIndicator

/// Displays the current form score as a colour-coded pill badge.
///
/// The colour follows the `AppColors.formScoreColor(_:)` convention:
/// - Green  (>= 0.75): good form
/// - Orange (>= 0.50): acceptable form
/// - Red    (<  0.50): poor form
///
/// When `score` is `nil` (no push-up counted yet) the indicator shows a
/// neutral "---" placeholder so the layout does not shift on the first rep.
///
/// **Usage**
/// ```swift
/// FormScoreIndicator(score: viewModel.formScore)
/// ```
struct FormScoreIndicator: View {

    // MARK: - Input

    /// The combined form score in [0.0, 1.0], or `nil` when unavailable.
    let score: Double?
    let supportsFormScoring: Bool

    // MARK: - Body

    var body: some View {
        HStack(spacing: AppSpacing.xs) {
            // Coloured dot
            Circle()
                .fill(indicatorColor)
                .frame(width: 10, height: 10)
                .shadow(color: indicatorColor.opacity(0.6), radius: 4, x: 0, y: 0)

            VStack(alignment: .leading, spacing: 1) {
                Text("FORM")
                    .font(AppTypography.captionSemibold)
                    .foregroundStyle(.white.opacity(0.65))
                    .tracking(1.5)

                Text(scoreText)
                    .font(AppTypography.roundedHeadline)
                    .foregroundStyle(indicatorColor)
                    .contentTransition(.numericText())
                    .animation(.easeInOut(duration: 0.3), value: score)
            }
        }
        .padding(.horizontal, AppSpacing.sm)
        .padding(.vertical, AppSpacing.xs)
        .background(.ultraThinMaterial, in: Capsule())
        .animation(.easeInOut(duration: 0.3), value: score)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityDescription)
    }

    // MARK: - Private Helpers

    private var indicatorColor: Color {
        guard supportsFormScoring else { return AppColors.info }
        guard let score else { return AppColors.textSecondary }
        return AppColors.formScoreColor(score)
    }

    private var scoreText: String {
        guard supportsFormScoring else { return "SIDE ONLY" }
        guard let score else { return "---" }
        return "\(Int(score * 100))%"
    }

    private var accessibilityDescription: String {
        guard supportsFormScoring else { return "Form score available only in side view" }
        guard let score else { return "Form score not available" }
        let percentage = Int(score * 100)
        let quality: String
        switch score {
        case 0.75...: quality = "good"
        case 0.50...: quality = "fair"
        default:      quality = "poor"
        }
        return "Form score \(percentage) percent, \(quality)"
    }
}

// MARK: - Previews

#if DEBUG
#Preview("Form Score - Good") {
    ZStack {
        Color.black.ignoresSafeArea()
        FormScoreIndicator(score: 0.88, supportsFormScoring: true)
    }
}

#Preview("Form Score - Warning") {
    ZStack {
        Color.black.ignoresSafeArea()
        FormScoreIndicator(score: 0.62, supportsFormScoring: true)
    }
}

#Preview("Form Score - Poor") {
    ZStack {
        Color.black.ignoresSafeArea()
        FormScoreIndicator(score: 0.35, supportsFormScoring: true)
    }
}

#Preview("Form Score - Nil") {
    ZStack {
        Color.black.ignoresSafeArea()
        FormScoreIndicator(score: nil, supportsFormScoring: true)
    }
}

#Preview("Form Score - Front Only") {
    ZStack {
        Color.black.ignoresSafeArea()
        FormScoreIndicator(score: nil, supportsFormScoring: false)
    }
}
#endif
