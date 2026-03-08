import SwiftUI

// MARK: - Card

/// General-purpose container card with rounded background and shadow.
///
/// Usage:
/// ```swift
/// Card {
///     VStack(alignment: .leading, spacing: AppSpacing.xs) {
///         Text("Letzte Session").font(AppTypography.headline)
///         Text("42 Push-Ups in 8 Minuten").font(AppTypography.body)
///     }
/// }
/// ```
struct Card<Content: View>: View {

    private let padding: CGFloat
    private let cornerRadius: CGFloat
    private let hasShadow: Bool
    private let content: Content

    init(
        padding: CGFloat = AppSpacing.cardPadding,
        cornerRadius: CGFloat = AppSpacing.cornerRadiusCard,
        hasShadow: Bool = true,
        @ViewBuilder content: () -> Content
    ) {
        self.padding = padding
        self.cornerRadius = cornerRadius
        self.hasShadow = hasShadow
        self.content = content()
    }

    var body: some View {
        content
            .padding(padding)
            .background(AppColors.backgroundSecondary)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
            .shadow(
                color: hasShadow ? Color.black.opacity(0.06) : .clear,
                radius: 8, x: 0, y: 2
            )
    }
}

// MARK: - StatCard

/// Compact card for a single metric with label, value, and optional trend.
///
/// Usage:
/// ```swift
/// StatCard(
///     title: "Heute",
///     value: "42",
///     subtitle: "Push-Ups",
///     icon: .figureStrengthTraining,
///     tint: AppColors.primary,
///     trend: .up(percentage: 12)
/// )
/// ```
struct StatCard: View {

    // MARK: - Trend

    enum Trend {
        case up(percentage: Int)
        case down(percentage: Int)
        case neutral

        var icon: String {
            switch self {
            case .up:      return "arrow.up.right"
            case .down:    return "arrow.down.right"
            case .neutral: return "minus"
            }
        }

        var color: Color {
            switch self {
            case .up:      return AppColors.success
            case .down:    return AppColors.error
            case .neutral: return AppColors.textSecondary
            }
        }

        var label: String {
            switch self {
            case .up(let pct):   return "+\(pct)%"
            case .down(let pct): return "-\(pct)%"
            case .neutral:       return "–"
            }
        }
    }

    // MARK: Properties

    private let title: String
    private let value: String
    private let subtitle: String?
    private let icon: AppIcon?
    private let tint: Color
    private let trend: Trend?

    init(
        title: String,
        value: String,
        subtitle: String? = nil,
        icon: AppIcon? = nil,
        tint: Color = AppColors.primary,
        trend: Trend? = nil
    ) {
        self.title = title
        self.value = value
        self.subtitle = subtitle
        self.icon = icon
        self.tint = tint
        self.trend = trend
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.xs) {

            // Header: icon + title + trend
            HStack(alignment: .center) {
                if let icon {
                    Image(systemName: icon.rawValue)
                        .font(.system(size: AppSpacing.iconSizeSmall, weight: .semibold))
                        .foregroundStyle(tint)
                }

                Text(title)
                    .font(AppTypography.caption1)
                    .foregroundStyle(AppColors.textSecondary)

                Spacer()

                if let trend {
                    trendBadge(trend)
                }
            }

            // Value -- displayMedium (34pt) fits 2-column grids
            Text(value)
                .font(AppTypography.displayMedium)
                .foregroundStyle(AppColors.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.5)

            // Subtitle
            if let subtitle {
                Text(subtitle)
                    .font(AppTypography.caption1)
                    .foregroundStyle(AppColors.textSecondary)
            }
        }
        .padding(AppSpacing.statCardPadding)
        .background(AppColors.backgroundSecondary)
        .clipShape(RoundedRectangle(cornerRadius: AppSpacing.cornerRadiusCard))
        .shadow(color: Color.black.opacity(0.05), radius: 6, x: 0, y: 2)
    }

    @ViewBuilder
    private func trendBadge(_ trend: Trend) -> some View {
        HStack(spacing: 2) {
            Image(systemName: trend.icon)
                .font(.system(size: 10, weight: .bold))
            Text(trend.label)
                .font(AppTypography.caption2)
        }
        .foregroundStyle(trend.color)
        .padding(.horizontal, AppSpacing.xxs)
        .padding(.vertical, 2)
        .background(trend.color.opacity(0.12), in: Capsule())
    }
}

// MARK: - TimeCreditCard

/// Prominent card displaying the current time-credit balance with a
/// circular progress ring.
///
/// Usage:
/// ```swift
/// TimeCreditCard(availableSeconds: 1800, totalEarnedSeconds: 3600)
/// ```
struct TimeCreditCard: View {

    private let availableSeconds: Int
    private let totalEarnedSeconds: Int
    private let isLoading: Bool

    private let ringSize: CGFloat = 160
    private let ringLineWidth: CGFloat = 12

    init(
        availableSeconds: Int,
        totalEarnedSeconds: Int,
        isLoading: Bool = false
    ) {
        self.availableSeconds = max(0, availableSeconds)
        self.totalEarnedSeconds = max(0, totalEarnedSeconds)
        self.isLoading = isLoading
    }

    var body: some View {
        Card(padding: AppSpacing.lg) {
            VStack(spacing: AppSpacing.md) {

                Text("Zeitguthaben")
                    .font(AppTypography.headline)
                    .foregroundStyle(AppColors.textSecondary)

                // Progress ring + time display
                ZStack {
                    Circle()
                        .stroke(AppColors.fill, lineWidth: ringLineWidth)
                        .frame(width: ringSize, height: ringSize)

                    Circle()
                        .trim(from: 0, to: progressFraction)
                        .stroke(
                            LinearGradient(
                                colors: [AppColors.primary, AppColors.secondary],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            style: StrokeStyle(lineWidth: ringLineWidth, lineCap: .round)
                        )
                        .frame(width: ringSize, height: ringSize)
                        .rotationEffect(.degrees(-90))
                        .animation(.easeInOut(duration: 0.6), value: progressFraction)

                    if isLoading {
                        ProgressView()
                            .progressViewStyle(.circular)
                            .tint(AppColors.primary)
                    } else {
                        VStack(spacing: AppSpacing.xxs) {
                            Text(formattedTime)
                                .font(AppTypography.monoDisplay)
                                .foregroundStyle(AppColors.textPrimary)
                                .lineLimit(1)
                                .minimumScaleFactor(0.6)

                            Text("verfuegbar")
                                .font(AppTypography.caption1)
                                .foregroundStyle(AppColors.textSecondary)
                        }
                    }
                }

                // Earned total
                HStack(spacing: AppSpacing.xxs) {
                    Image(systemName: AppIcon.checkmarkCircleFill.rawValue)
                        .foregroundStyle(AppColors.success)
                        .font(.system(size: AppSpacing.iconSizeSmall))

                    Text("Gesamt verdient: \(formattedTotalEarned)")
                        .font(AppTypography.caption1)
                        .foregroundStyle(AppColors.textSecondary)
                }
            }
            .frame(maxWidth: .infinity)
        }
    }

    // MARK: Private

    private var progressFraction: CGFloat {
        guard totalEarnedSeconds > 0 else { return 0 }
        return min(1.0, CGFloat(availableSeconds) / CGFloat(totalEarnedSeconds))
    }

    private var formattedTime: String {
        let clamped = max(0, availableSeconds)
        let h = clamped / 3600
        let m = (clamped % 3600) / 60
        let s = clamped % 60
        return String(format: "%02d:%02d:%02d", h, m, s)
    }

    private var formattedTotalEarned: String {
        let minutes = totalEarnedSeconds / 60
        return "\(minutes) Min"
    }
}

// MARK: - WorkoutSummaryCard

/// Card summarising a completed workout session.
///
/// Usage:
/// ```swift
/// WorkoutSummaryCard(
///     pushUpCount: 42, durationSeconds: 480,
///     earnedSeconds: 252, qualityScore: 0.82
/// )
/// ```
struct WorkoutSummaryCard: View {

    private let pushUpCount: Int
    private let durationSeconds: Int
    private let earnedSeconds: Int
    private let qualityScore: Double

    init(
        pushUpCount: Int,
        durationSeconds: Int,
        earnedSeconds: Int,
        qualityScore: Double
    ) {
        self.pushUpCount = pushUpCount
        self.durationSeconds = durationSeconds
        self.earnedSeconds = earnedSeconds
        self.qualityScore = min(1.0, max(0.0, qualityScore))
    }

    var body: some View {
        Card {
            VStack(spacing: AppSpacing.md) {

                // Push-up count hero
                VStack(spacing: AppSpacing.xxs) {
                    Text("\(pushUpCount)")
                        .font(AppTypography.displayLarge)
                        .foregroundStyle(AppColors.textPrimary)

                    Text("Push-Ups")
                        .font(AppTypography.subheadline)
                        .foregroundStyle(AppColors.textSecondary)
                }

                Divider()

                // Metrics row
                HStack {
                    metricItem(
                        icon: .clock,
                        value: formattedDuration,
                        label: "Dauer",
                        tint: AppColors.info
                    )

                    Divider().frame(height: 40)

                    metricItem(
                        icon: .boltFill,
                        value: "+\(earnedSeconds / 60) Min",
                        label: "Verdient",
                        tint: AppColors.success
                    )

                    Divider().frame(height: 40)

                    metricItem(
                        icon: .starFill,
                        value: String(format: "%.0f%%", qualityScore * 100),
                        label: "Qualitaet",
                        tint: AppColors.formScoreColor(qualityScore)
                    )
                }
            }
        }
    }

    @ViewBuilder
    private func metricItem(
        icon: AppIcon,
        value: String,
        label: String,
        tint: Color
    ) -> some View {
        VStack(spacing: AppSpacing.xxs) {
            Image(systemName: icon.rawValue)
                .font(.system(size: AppSpacing.iconSizeStandard, weight: .semibold))
                .foregroundStyle(tint)

            Text(value)
                .font(AppTypography.bodySemibold)
                .foregroundStyle(AppColors.textPrimary)

            Text(label)
                .font(AppTypography.caption1)
                .foregroundStyle(AppColors.textSecondary)
        }
        .frame(maxWidth: .infinity)
    }

    private var formattedDuration: String {
        let m = durationSeconds / 60
        let s = durationSeconds % 60
        return String(format: "%d:%02d", m, s)
    }
}

// MARK: - EmptyStateCard

/// Card shown when a list or section has no data.
///
/// Usage:
/// ```swift
/// EmptyStateCard(
///     icon: .figureStrengthTraining,
///     title: "Noch keine Workouts",
///     message: "Starte dein erstes Workout!",
///     actionTitle: "Workout starten",
///     action: { startWorkout() }
/// )
/// ```
struct EmptyStateCard: View {

    private let icon: AppIcon
    private let title: String
    private let message: String
    private let actionTitle: String?
    private let action: (() -> Void)?

    init(
        icon: AppIcon,
        title: String,
        message: String,
        actionTitle: String? = nil,
        action: (() -> Void)? = nil
    ) {
        self.icon = icon
        self.title = title
        self.message = message
        self.actionTitle = actionTitle
        self.action = action
    }

    var body: some View {
        Card {
            VStack(spacing: AppSpacing.md) {
                Image(systemName: icon.rawValue)
                    .font(.system(size: AppSpacing.iconSizeXL, weight: .light))
                    .foregroundStyle(AppColors.textTertiary)

                VStack(spacing: AppSpacing.xs) {
                    Text(title)
                        .font(AppTypography.headline)
                        .foregroundStyle(AppColors.textPrimary)
                        .multilineTextAlignment(.center)

                    Text(message)
                        .font(AppTypography.body)
                        .foregroundStyle(AppColors.textSecondary)
                        .multilineTextAlignment(.center)
                }

                if let actionTitle, let action {
                    PrimaryButton(actionTitle, action: action)
                        .padding(.top, AppSpacing.xs)
                }
            }
            .padding(.vertical, AppSpacing.lg)
            .frame(maxWidth: .infinity)
        }
    }
}

// MARK: - Previews

#if DEBUG
#Preview("Cards") {
    ScrollView {
        VStack(spacing: AppSpacing.md) {

            TimeCreditCard(
                availableSeconds: 1800,
                totalEarnedSeconds: 3600
            )

            LazyVGrid(
                columns: [GridItem(.flexible()), GridItem(.flexible())],
                spacing: AppSpacing.sm
            ) {
                StatCard(
                    title: "Heute", value: "42", subtitle: "Push-Ups",
                    icon: .figureStrengthTraining, tint: AppColors.primary,
                    trend: .up(percentage: 12)
                )
                StatCard(
                    title: "Woche", value: "287", subtitle: "Push-Ups",
                    icon: .calendarBadgeCheckmark, tint: AppColors.secondary,
                    trend: .down(percentage: 5)
                )
                StatCard(
                    title: "Qualitaet", value: "84%", subtitle: "Durchschnitt",
                    icon: .starFill, tint: AppColors.warning
                )
                StatCard(
                    title: "Streak", value: "7", subtitle: "Tage",
                    icon: .flameFill, tint: AppColors.error, trend: .neutral
                )
            }

            WorkoutSummaryCard(
                pushUpCount: 42, durationSeconds: 480,
                earnedSeconds: 252, qualityScore: 0.82
            )

            EmptyStateCard(
                icon: .figureStrengthTraining,
                title: "Noch keine Workouts",
                message: "Starte dein erstes Workout und verdiene Zeitguthaben!",
                actionTitle: "Workout starten",
                action: {}
            )

            Card {
                VStack(alignment: .leading, spacing: AppSpacing.xs) {
                    Label("Letzte Session", systemImage: AppIcon.clockArrowCirclepath.rawValue)
                        .font(AppTypography.headline)
                        .foregroundStyle(AppColors.textPrimary)
                    Text("42 Push-Ups in 8 Minuten")
                        .font(AppTypography.body)
                        .foregroundStyle(AppColors.textSecondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(AppSpacing.md)
    }
    .background(AppColors.backgroundPrimary)
}
#endif
