import SwiftUI

// MARK: - Card

/// A general-purpose container card with a rounded rectangle background.
///
/// Use `Card` to group related content visually. It applies the standard
/// card background, corner radius, and shadow from the design system.
///
/// Usage:
/// ```swift
/// Card {
///     VStack(alignment: .leading, spacing: AppSpacing.xs) {
///         Text("Letzte Session")
///             .font(AppTypography.headline)
///         Text("42 Push-Ups in 8 Minuten")
///             .font(AppTypography.body)
///     }
/// }
///
/// // With custom padding
/// Card(padding: AppSpacing.lg) {
///     Text("Mehr Platz")
/// }
/// ```
public struct Card<Content: View>: View {

    // MARK: Properties

    private let padding: CGFloat
    private let cornerRadius: CGFloat
    private let shadowEnabled: Bool
    private let content: Content

    // MARK: Init

    public init(
        padding: CGFloat = AppSpacing.cardPadding,
        cornerRadius: CGFloat = AppSpacing.cornerRadiusCard,
        shadowEnabled: Bool = true,
        @ViewBuilder content: () -> Content
    ) {
        self.padding = padding
        self.cornerRadius = cornerRadius
        self.shadowEnabled = shadowEnabled
        self.content = content()
    }

    // MARK: Body

    public var body: some View {
        content
            .padding(padding)
            .background(AppColors.backgroundSecondaryInline)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
            .shadow(
                color: shadowEnabled ? Color.black.opacity(0.06) : .clear,
                radius: 8,
                x: 0,
                y: 2
            )
    }
}

// MARK: - StatCard

/// A compact card for displaying a single metric with a label, value, and
/// optional icon and trend indicator.
///
/// Usage:
/// ```swift
/// StatCard(
///     title: "Heute",
///     value: "42",
///     subtitle: "Push-Ups",
///     icon: "figure.strengthtraining.traditional",
///     tint: AppColors.primaryInline
/// )
///
/// // With trend
/// StatCard(
///     title: "Woche",
///     value: "287",
///     subtitle: "Push-Ups",
///     icon: "calendar.badge.checkmark",
///     trend: .up(percentage: 12)
/// )
/// ```
public struct StatCard: View {

    // MARK: - Trend

    public enum Trend {
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
            case .up:      return AppColors.successInline
            case .down:    return AppColors.errorInline
            case .neutral: return AppColors.textSecondaryInline
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
    private let icon: String?
    private let tint: Color
    private let trend: Trend?

    // MARK: Init

    public init(
        title: String,
        value: String,
        subtitle: String? = nil,
        icon: String? = nil,
        tint: Color = AppColors.primaryInline,
        trend: Trend? = nil
    ) {
        self.title = title
        self.value = value
        self.subtitle = subtitle
        self.icon = icon
        self.tint = tint
        self.trend = trend
    }

    // MARK: Body

    public var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.xs) {

            // Header row: icon + title + optional trend
            HStack(alignment: .center) {
                if let icon {
                    Image(systemName: icon)
                        .font(.system(size: AppSpacing.iconSizeSmall, weight: .semibold))
                        .foregroundStyle(tint)
                }

                Text(title)
                    .font(AppTypography.caption1)
                    .foregroundStyle(AppColors.textSecondaryInline)

                Spacer()

                if let trend {
                    trendBadge(trend)
                }
            }

            // Value
            Text(value)
                .font(AppTypography.displayMedium)
                .foregroundStyle(AppColors.textPrimaryInline)
                .lineLimit(1)
                .minimumScaleFactor(0.6)

            // Subtitle
            if let subtitle {
                Text(subtitle)
                    .font(AppTypography.caption1)
                    .foregroundStyle(AppColors.textSecondaryInline)
            }
        }
        .statCardPadding()
        .background(AppColors.backgroundSecondaryInline)
        .clipShape(RoundedRectangle(cornerRadius: AppSpacing.cornerRadiusCard))
        .shadow(color: Color.black.opacity(0.05), radius: 6, x: 0, y: 2)
    }

    // MARK: Private

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

/// A prominent card for displaying the current time-credit balance.
///
/// Shows the available time in HH:MM:SS format with a circular progress ring.
///
/// Usage:
/// ```swift
/// TimeCreditCard(
///     availableSeconds: 1800,
///     totalEarnedSeconds: 3600,
///     isLoading: false
/// )
/// ```
public struct TimeCreditCard: View {

    // MARK: Properties

    private let availableSeconds: Int
    private let totalEarnedSeconds: Int
    private let isLoading: Bool

    // MARK: Init

    public init(
        availableSeconds: Int,
        totalEarnedSeconds: Int,
        isLoading: Bool = false
    ) {
        self.availableSeconds = availableSeconds
        self.totalEarnedSeconds = totalEarnedSeconds
        self.isLoading = isLoading
    }

    // MARK: Body

    public var body: some View {
        Card(padding: AppSpacing.lg) {
            VStack(spacing: AppSpacing.md) {

                // Title
                Text("Zeitguthaben")
                    .font(AppTypography.headline)
                    .foregroundStyle(AppColors.textSecondaryInline)

                // Progress ring + time display
                ZStack {
                    // Background ring
                    Circle()
                        .stroke(AppColors.fillInline, lineWidth: 12)
                        .frame(width: 160, height: 160)

                    // Progress ring
                    Circle()
                        .trim(from: 0, to: progressFraction)
                        .stroke(
                            LinearGradient(
                                colors: [AppColors.primaryInline, AppColors.secondaryInline],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            style: StrokeStyle(lineWidth: 12, lineCap: .round)
                        )
                        .frame(width: 160, height: 160)
                        .rotationEffect(.degrees(-90))
                        .animation(.easeInOut(duration: 0.6), value: progressFraction)

                    // Time label
                    if isLoading {
                        ProgressView()
                            .progressViewStyle(.circular)
                            .tint(AppColors.primaryInline)
                    } else {
                        VStack(spacing: AppSpacing.xxs) {
                            Text(formattedTime)
                                .font(AppTypography.monoDisplay)
                                .foregroundStyle(AppColors.textPrimaryInline)
                                .lineLimit(1)
                                .minimumScaleFactor(0.7)

                            Text("verfuegbar")
                                .font(AppTypography.caption1)
                                .foregroundStyle(AppColors.textSecondaryInline)
                        }
                    }
                }

                // Earned total
                HStack(spacing: AppSpacing.xxs) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(AppColors.successInline)
                        .font(.system(size: AppSpacing.iconSizeSmall))

                    Text("Gesamt verdient: \(formattedTotalEarned)")
                        .font(AppTypography.caption1)
                        .foregroundStyle(AppColors.textSecondaryInline)
                }
            }
            .frame(maxWidth: .infinity)
        }
    }

    // MARK: Private

    private var progressFraction: CGFloat {
        guard totalEarnedSeconds > 0 else { return 0 }
        return CGFloat(availableSeconds) / CGFloat(totalEarnedSeconds)
    }

    private var formattedTime: String {
        let hours   = availableSeconds / 3600
        let minutes = (availableSeconds % 3600) / 60
        let seconds = availableSeconds % 60
        return String(format: "%02d:%02d:%02d", hours, minutes, seconds)
    }

    private var formattedTotalEarned: String {
        let minutes = totalEarnedSeconds / 60
        return "\(minutes) Min"
    }
}

// MARK: - WorkoutSummaryCard

/// A card summarising a completed workout session.
///
/// Usage:
/// ```swift
/// WorkoutSummaryCard(
///     pushUpCount: 42,
///     durationSeconds: 480,
///     earnedSeconds: 252,
///     qualityScore: 0.82
/// )
/// ```
public struct WorkoutSummaryCard: View {

    // MARK: Properties

    private let pushUpCount: Int
    private let durationSeconds: Int
    private let earnedSeconds: Int
    private let qualityScore: Double

    // MARK: Init

    public init(
        pushUpCount: Int,
        durationSeconds: Int,
        earnedSeconds: Int,
        qualityScore: Double
    ) {
        self.pushUpCount = pushUpCount
        self.durationSeconds = durationSeconds
        self.earnedSeconds = earnedSeconds
        self.qualityScore = qualityScore
    }

    // MARK: Body

    public var body: some View {
        Card {
            VStack(spacing: AppSpacing.md) {

                // Push-up count hero
                VStack(spacing: AppSpacing.xxs) {
                    Text("\(pushUpCount)")
                        .font(AppTypography.displayLarge)
                        .foregroundStyle(AppColors.textPrimaryInline)

                    Text("Push-Ups")
                        .font(AppTypography.subheadline)
                        .foregroundStyle(AppColors.textSecondaryInline)
                }

                Divider()

                // Metrics row
                HStack {
                    metricItem(
                        icon: "clock",
                        value: formattedDuration,
                        label: "Dauer",
                        tint: AppColors.infoInline
                    )

                    Divider().frame(height: 40)

                    metricItem(
                        icon: "bolt.fill",
                        value: "+\(earnedSeconds / 60) Min",
                        label: "Verdient",
                        tint: AppColors.successInline
                    )

                    Divider().frame(height: 40)

                    metricItem(
                        icon: "star.fill",
                        value: String(format: "%.0f%%", qualityScore * 100),
                        label: "Qualitaet",
                        tint: qualityColor
                    )
                }
            }
        }
    }

    // MARK: Private

    @ViewBuilder
    private func metricItem(
        icon: String,
        value: String,
        label: String,
        tint: Color
    ) -> some View {
        VStack(spacing: AppSpacing.xxs) {
            Image(systemName: icon)
                .font(.system(size: AppSpacing.iconSizeStandard, weight: .semibold))
                .foregroundStyle(tint)

            Text(value)
                .font(AppTypography.bodySemibold)
                .foregroundStyle(AppColors.textPrimaryInline)

            Text(label)
                .font(AppTypography.caption1)
                .foregroundStyle(AppColors.textSecondaryInline)
        }
        .frame(maxWidth: .infinity)
    }

    private var formattedDuration: String {
        let minutes = durationSeconds / 60
        let seconds = durationSeconds % 60
        return String(format: "%d:%02d", minutes, seconds)
    }

    private var qualityColor: Color {
        AppColors.formScoreColor(qualityScore)
    }
}

// MARK: - EmptyStateCard

/// A card shown when a list or section has no data yet.
///
/// Usage:
/// ```swift
/// EmptyStateCard(
///     icon: "figure.strengthtraining.traditional",
///     title: "Noch keine Workouts",
///     message: "Starte dein erstes Workout und verdiene Zeitguthaben!",
///     actionTitle: "Workout starten",
///     action: { startWorkout() }
/// )
/// ```
public struct EmptyStateCard: View {

    // MARK: Properties

    private let icon: String
    private let title: String
    private let message: String
    private let actionTitle: String?
    private let action: (() -> Void)?

    // MARK: Init

    public init(
        icon: String,
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

    // MARK: Body

    public var body: some View {
        Card {
            VStack(spacing: AppSpacing.md) {
                Image(systemName: icon)
                    .font(.system(size: AppSpacing.iconSizeXL, weight: .light))
                    .foregroundStyle(AppColors.textTertiaryInline)

                VStack(spacing: AppSpacing.xs) {
                    Text(title)
                        .font(AppTypography.headline)
                        .foregroundStyle(AppColors.textPrimaryInline)
                        .multilineTextAlignment(.center)

                    Text(message)
                        .font(AppTypography.body)
                        .foregroundStyle(AppColors.textSecondaryInline)
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

            Text("TimeCreditCard")
                .font(AppTypography.caption1)
                .foregroundStyle(AppColors.textSecondaryInline)
                .frame(maxWidth: .infinity, alignment: .leading)

            TimeCreditCard(
                availableSeconds: 1800,
                totalEarnedSeconds: 3600
            )

            Text("StatCards")
                .font(AppTypography.caption1)
                .foregroundStyle(AppColors.textSecondaryInline)
                .frame(maxWidth: .infinity, alignment: .leading)

            LazyVGrid(
                columns: [GridItem(.flexible()), GridItem(.flexible())],
                spacing: AppSpacing.sm
            ) {
                StatCard(
                    title: "Heute",
                    value: "42",
                    subtitle: "Push-Ups",
                    icon: "figure.strengthtraining.traditional",
                    tint: AppColors.primaryInline,
                    trend: .up(percentage: 12)
                )

                StatCard(
                    title: "Woche",
                    value: "287",
                    subtitle: "Push-Ups",
                    icon: "calendar.badge.checkmark",
                    tint: AppColors.secondaryInline,
                    trend: .down(percentage: 5)
                )

                StatCard(
                    title: "Qualitaet",
                    value: "84%",
                    subtitle: "Durchschnitt",
                    icon: "star.fill",
                    tint: AppColors.warningInline
                )

                StatCard(
                    title: "Streak",
                    value: "7",
                    subtitle: "Tage",
                    icon: "flame.fill",
                    tint: AppColors.errorInline,
                    trend: .neutral
                )
            }

            Text("WorkoutSummaryCard")
                .font(AppTypography.caption1)
                .foregroundStyle(AppColors.textSecondaryInline)
                .frame(maxWidth: .infinity, alignment: .leading)

            WorkoutSummaryCard(
                pushUpCount: 42,
                durationSeconds: 480,
                earnedSeconds: 252,
                qualityScore: 0.82
            )

            Text("EmptyStateCard")
                .font(AppTypography.caption1)
                .foregroundStyle(AppColors.textSecondaryInline)
                .frame(maxWidth: .infinity, alignment: .leading)

            EmptyStateCard(
                icon: "figure.strengthtraining.traditional",
                title: "Noch keine Workouts",
                message: "Starte dein erstes Workout und verdiene Zeitguthaben!",
                actionTitle: "Workout starten",
                action: {}
            )

            Text("Generic Card")
                .font(AppTypography.caption1)
                .foregroundStyle(AppColors.textSecondaryInline)
                .frame(maxWidth: .infinity, alignment: .leading)

            Card {
                VStack(alignment: .leading, spacing: AppSpacing.xs) {
                    Label("Letzte Session", systemImage: "clock.arrow.circlepath")
                        .font(AppTypography.headline)
                        .foregroundStyle(AppColors.textPrimaryInline)

                    Text("42 Push-Ups in 8 Minuten")
                        .font(AppTypography.body)
                        .foregroundStyle(AppColors.textSecondaryInline)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(AppSpacing.md)
    }
    .background(AppColors.backgroundPrimaryInline)
}
#endif
