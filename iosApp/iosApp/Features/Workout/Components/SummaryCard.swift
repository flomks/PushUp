import SwiftUI

// MARK: - SummaryCard

/// A rich summary card displayed on the workout completion screen.
///
/// Shows the session's key metrics in a visually distinct card with
/// animated number counting, star quality rating, earned time credit
/// highlight, and an optional comparison badge.
///
/// **Usage**
/// ```swift
/// SummaryCard(
///     pushUpCount: 42,
///     durationSeconds: 480,
///     earnedMinutes: 5,
///     qualityScore: 0.84,
///     comparisonPercent: 12
/// )
/// ```
struct SummaryCard: View {

    // MARK: - Input

    /// Total push-ups completed in the session.
    let pushUpCount: Int

    /// Session duration in seconds.
    let durationSeconds: Int

    /// Time credit earned in whole minutes.
    let earnedMinutes: Int

    /// Average form quality score in [0.0, 1.0].
    let qualityScore: Double?

    /// Percentage above (+) or below (-) the user's personal average.
    /// `nil` when no comparison data is available.
    let comparisonPercent: Int?

    // MARK: - Animation State

    /// Drives the count-up animation for the push-up number.
    @State private var displayedCount: Int = 0

    /// Drives the count-up animation for earned minutes.
    @State private var displayedMinutes: Int = 0

    /// Controls entry animation for the card content.
    @State private var contentVisible: Bool = false

    // MARK: - Body

    var body: some View {
        VStack(spacing: AppSpacing.lg) {
            pushUpHero
            Divider()
                .background(AppColors.separator)
            metricsRow
            if let comparisonPercent {
                comparisonBadge(percent: comparisonPercent)
            }
        }
        .padding(AppSpacing.lg)
        .background(
            RoundedRectangle(cornerRadius: AppSpacing.cornerRadiusLarge)
                .fill(.ultraThinMaterial)
                .shadow(color: .black.opacity(0.25), radius: 20, x: 0, y: 8)
        )
        .opacity(contentVisible ? 1 : 0)
        .scaleEffect(contentVisible ? 1 : 0.92)
        .onAppear {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.75).delay(0.15)) {
                contentVisible = true
            }
            animateCountUp()
        }
    }

    // MARK: - Push-Up Hero

    private var pushUpHero: some View {
        VStack(spacing: AppSpacing.xs) {
            Text("\(displayedCount)")
                .font(AppTypography.displayLarge)
                .foregroundStyle(.white)
                .contentTransition(.numericText(countsDown: false))
                .animation(.easeOut(duration: 0.05), value: displayedCount)

            Text("Push-Ups")
                .font(AppTypography.roundedHeadline)
                .foregroundStyle(.white.opacity(0.75))
                .tracking(1)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(pushUpCount) Push-Ups")
    }

    // MARK: - Metrics Row

    private var metricsRow: some View {
        HStack(spacing: 0) {
            // Duration
            metricCell(
                icon: .clock,
                value: formattedDuration,
                label: "Duration",
                tint: AppColors.info
            )

            metricDivider

            // Earned time credit
            earnedCreditCell

            if qualityScore != nil {
                metricDivider

                // Quality score
                qualityCell
            }
        }
    }

    // MARK: - Earned Credit Cell

    private var earnedCreditCell: some View {
        VStack(spacing: AppSpacing.xxs) {
            Image(icon: .clockBadgeCheckmark)
                .font(.system(size: AppSpacing.iconSizeStandard, weight: .semibold))
                .foregroundStyle(AppColors.success)

            Text("+\(displayedMinutes) Min")
                .font(AppTypography.bodySemibold)
                .foregroundStyle(AppColors.success)
                .contentTransition(.numericText(countsDown: false))
                .animation(.easeOut(duration: 0.05), value: displayedMinutes)

            Text("Earned")
                .font(AppTypography.captionSemibold)
                .foregroundStyle(.white.opacity(0.6))
                .tracking(0.5)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("+\(earnedMinutes) minutes earned")
    }

    // MARK: - Quality Cell

    private var qualityCell: some View {
        VStack(spacing: AppSpacing.xxs) {
            starRating(score: qualityScore ?? 0)

            Text(qualityLabel)
                .font(AppTypography.bodySemibold)
                .foregroundStyle(qualityColor)

            Text("Quality")
                .font(AppTypography.captionSemibold)
                .foregroundStyle(.white.opacity(0.6))
                .tracking(0.5)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Quality: \(qualityLabel)")
    }

    // MARK: - Star Rating

    @ViewBuilder
    private func starRating(score: Double) -> some View {
        let filledStars = Int((score * 5).rounded())
        HStack(spacing: 2) {
            ForEach(0..<5, id: \.self) { index in
                Image(systemName: index < filledStars ? "star.fill" : "star")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(
                        index < filledStars
                            ? AppColors.secondaryVariant
                            : .white.opacity(0.3)
                    )
            }
        }
    }

    // MARK: - Metric Cell

    @ViewBuilder
    private func metricCell(
        icon: AppIcon,
        value: String,
        label: String,
        tint: Color
    ) -> some View {
        VStack(spacing: AppSpacing.xxs) {
            Image(icon: icon)
                .font(.system(size: AppSpacing.iconSizeStandard, weight: .semibold))
                .foregroundStyle(tint)

            Text(value)
                .font(AppTypography.bodySemibold)
                .foregroundStyle(.white)

            Text(label)
                .font(AppTypography.captionSemibold)
                .foregroundStyle(.white.opacity(0.6))
                .tracking(0.5)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Metric Divider

    private var metricDivider: some View {
        Rectangle()
            .fill(.white.opacity(0.15))
            .frame(width: 1, height: 48)
    }

    // MARK: - Comparison Badge

    @ViewBuilder
    private func comparisonBadge(percent: Int) -> some View {
        let isPositive = percent >= 0
        let icon = isPositive ? "arrow.up.right" : "arrow.down.right"
        let color = isPositive ? AppColors.success : AppColors.error
        let text = isPositive
            ? "\(percent)% better than your average"
            : "\(abs(percent))% below your average"

        HStack(spacing: AppSpacing.xs) {
            Image(systemName: icon)
                .font(.system(size: AppSpacing.iconSizeSmall, weight: .bold))
                .foregroundStyle(color)

            Text(text)
                .font(AppTypography.captionSemibold)
                .foregroundStyle(color)
        }
        .padding(.horizontal, AppSpacing.sm)
        .padding(.vertical, AppSpacing.xs)
        .background(color.opacity(0.15), in: Capsule())
        .accessibilityLabel(text)
    }

    // MARK: - Computed Properties

    private var formattedDuration: String {
        let m = durationSeconds / 60
        let s = durationSeconds % 60
        return String(format: "%d:%02d", m, s)
    }

    private var qualityLabel: String {
        guard let score = qualityScore else { return "---" }
        return "\(Int(score * 100))%"
    }

    private var qualityColor: Color {
        guard let score = qualityScore else { return AppColors.textSecondary }
        return AppColors.formScoreColor(score)
    }

    // MARK: - Count-Up Animation

    /// Animates the push-up count and earned minutes from 0 to their
    /// final values over ~1.2 seconds using a timer-driven approach.
    private func animateCountUp() {
        let totalSteps = 30
        let interval: TimeInterval = 1.2 / Double(totalSteps)
        var step = 0

        Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { timer in
            step += 1
            let progress = Double(step) / Double(totalSteps)
            // Ease-out curve: fast start, slow finish
            let eased = 1 - pow(1 - progress, 3)

            displayedCount = Int(Double(pushUpCount) * eased)
            displayedMinutes = Int(Double(earnedMinutes) * eased)

            if step >= totalSteps {
                timer.invalidate()
                // Snap to exact final values
                displayedCount = pushUpCount
                displayedMinutes = earnedMinutes
            }
        }
    }
}

// MARK: - Previews

#if DEBUG
#Preview("Summary Card - Full") {
    ZStack {
        LinearGradient(
            colors: [Color(light: "#1a1a2e", dark: "#0d0d1a"), Color(light: "#16213e", dark: "#0d1117")],
            startPoint: .top,
            endPoint: .bottom
        )
        .ignoresSafeArea()

        SummaryCard(
            pushUpCount: 42,
            durationSeconds: 487,
            earnedMinutes: 5,
            qualityScore: 0.84,
            comparisonPercent: 12
        )
        .padding(AppSpacing.xl)
    }
}

#Preview("Summary Card - No Comparison") {
    ZStack {
        Color.black.ignoresSafeArea()
        SummaryCard(
            pushUpCount: 15,
            durationSeconds: 180,
            earnedMinutes: 2,
            qualityScore: 0.61,
            comparisonPercent: nil
        )
        .padding(AppSpacing.xl)
    }
}

#Preview("Summary Card - Below Average") {
    ZStack {
        Color.black.ignoresSafeArea()
        SummaryCard(
            pushUpCount: 8,
            durationSeconds: 120,
            earnedMinutes: 1,
            qualityScore: 0.45,
            comparisonPercent: -8
        )
        .padding(AppSpacing.xl)
    }
}
#endif
