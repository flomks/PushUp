import SwiftUI

// MARK: - TotalStatsView

/// Lifetime aggregate statistics view for the Stats screen.
///
/// Displays:
/// - Prominent streak banner (fire icon + days)
/// - Hero total push-ups counter
/// - Records section (best session, best day, best week)
/// - Averages section
/// - Activity overview
///
/// Usage:
/// ```swift
/// TotalStatsView(stats: viewModel.totalStats, isLoading: viewModel.isLoading)
/// ```
struct TotalStatsView: View {

    let stats: TotalStatsData?
    let isLoading: Bool

    private static let twoColumns = [
        GridItem(.flexible()),
        GridItem(.flexible()),
    ]

    var body: some View {
        VStack(spacing: AppSpacing.md) {
            if isLoading {
                loadingContent
            } else if let stats {
                loadedContent(stats)
            } else {
                emptyContent
            }
        }
    }

    // MARK: - Loaded Content

    @ViewBuilder
    private func loadedContent(_ stats: TotalStatsData) -> some View {
        streakBanner(stats)
        heroCard(stats)
        recordsSection(stats)
        averagesSection(stats)
        activitySection(stats)
    }

    // MARK: - Streak Banner

    private func streakBanner(_ stats: TotalStatsData) -> some View {
        Card(padding: AppSpacing.md) {
            HStack(spacing: AppSpacing.md) {
                // Fire icon with glow effect
                ZStack {
                    Circle()
                        .fill(AppColors.secondary.opacity(0.15))
                        .frame(width: 56, height: 56)

                    Image(systemName: AppIcon.flameFill.rawValue)
                        .font(.system(size: 28, weight: .bold))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [AppColors.secondary, AppColors.warning],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                }

                VStack(alignment: .leading, spacing: AppSpacing.xxs) {
                    HStack(alignment: .firstTextBaseline, spacing: AppSpacing.xxs) {
                        Text("\(stats.currentStreakDays)")
                            .font(AppTypography.displayMedium)
                            .foregroundStyle(AppColors.textPrimary)

                        Text("day streak")
                            .font(AppTypography.subheadlineSemibold)
                            .foregroundStyle(AppColors.textSecondary)
                    }

                    Text("Keep it up! You're on fire.")
                        .font(AppTypography.caption1)
                        .foregroundStyle(AppColors.textSecondary)
                }

                Spacer()

                // Longest streak badge
                VStack(spacing: AppSpacing.xxs) {
                    Text("\(stats.longestStreakDays)")
                        .font(AppTypography.title3)
                        .foregroundStyle(AppColors.secondary)

                    Text("Best")
                        .font(AppTypography.caption2)
                        .foregroundStyle(AppColors.textSecondary)
                }
                .padding(.horizontal, AppSpacing.sm)
                .padding(.vertical, AppSpacing.xs)
                .background(AppColors.secondary.opacity(0.1), in: RoundedRectangle(cornerRadius: AppSpacing.cornerRadiusChip))
            }
        }
    }

    // MARK: - Hero Card

    private func heroCard(_ stats: TotalStatsData) -> some View {
        Card(padding: AppSpacing.lg) {
            VStack(spacing: AppSpacing.sm) {
                Text("Total Push-Ups")
                    .font(AppTypography.subheadline)
                    .foregroundStyle(AppColors.textSecondary)

                Text("\(stats.totalPushUps)")
                    .font(AppTypography.displayLarge)
                    .foregroundStyle(AppColors.textPrimary)
                    .contentTransition(.numericText())

                HStack(spacing: AppSpacing.xl) {
                    heroMetric(
                        value: "\(stats.totalSessions)",
                        label: "Sessions",
                        icon: .timer,
                        tint: AppColors.secondary
                    )
                    heroMetric(
                        value: "\(stats.totalEarnedMinutes) min",
                        label: "Earned",
                        icon: .boltFill,
                        tint: AppColors.success
                    )
                    heroMetric(
                        value: "\(stats.activeDays)",
                        label: "Active Days",
                        icon: .calendarBadgeCheckmark,
                        tint: AppColors.info
                    )
                }
            }
            .frame(maxWidth: .infinity)
        }
    }

    private func heroMetric(
        value: String,
        label: String,
        icon: AppIcon,
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
                .font(AppTypography.caption2)
                .foregroundStyle(AppColors.textSecondary)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Records Section

    private func recordsSection(_ stats: TotalStatsData) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            sectionHeader(title: "Records", icon: .starFill, tint: AppColors.warning)

            LazyVGrid(columns: Self.twoColumns, spacing: AppSpacing.sm) {
                StatCard(
                    title: "Best Session",
                    value: "\(stats.bestSingleSession)",
                    subtitle: "Push-Ups",
                    icon: .figureStrengthTraining,
                    tint: AppColors.primary
                )
                StatCard(
                    title: "Best Day",
                    value: "\(stats.bestDay)",
                    subtitle: "Push-Ups",
                    icon: .calendarBadgeCheckmark,
                    tint: AppColors.secondary
                )
                StatCard(
                    title: "Best Week",
                    value: "\(stats.bestWeek)",
                    subtitle: "Push-Ups",
                    icon: .chartBar,
                    tint: AppColors.info
                )
                StatCard(
                    title: "Longest Streak",
                    value: "\(stats.longestStreakDays) days",
                    subtitle: "Consecutive",
                    icon: .flameFill,
                    tint: AppColors.warning
                )
            }
        }
    }

    // MARK: - Averages Section

    private func averagesSection(_ stats: TotalStatsData) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            sectionHeader(title: "Averages", icon: .chartBar, tint: AppColors.info)

            LazyVGrid(columns: Self.twoColumns, spacing: AppSpacing.sm) {
                StatCard(
                    title: "Per Session",
                    value: String(format: "%.0f", stats.averagePushUpsPerSession),
                    subtitle: "Push-Ups",
                    icon: .figureStrengthTraining,
                    tint: AppColors.primary
                )
                StatCard(
                    title: "Session Length",
                    value: StatsViewModel.formatDuration(stats.averageSessionDurationSeconds),
                    subtitle: "Duration",
                    icon: .clock,
                    tint: AppColors.secondary
                )
                StatCard(
                    title: "Form Quality",
                    value: String(format: "%.0f%%", stats.averageQuality * 100),
                    subtitle: "Average",
                    icon: .starFill,
                    tint: AppColors.formScoreColor(stats.averageQuality)
                )
                StatCard(
                    title: "Active Days",
                    value: "\(stats.activeDays)",
                    subtitle: "Total",
                    icon: .calendarBadgeCheckmark,
                    tint: AppColors.info
                )
            }
        }
    }

    // MARK: - Activity Section

    private func activitySection(_ stats: TotalStatsData) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            sectionHeader(title: "Activity", icon: .boltFill, tint: AppColors.success)

            Card {
                VStack(spacing: AppSpacing.sm) {
                    activityRow(
                        label: "Total Time Earned",
                        value: "\(stats.totalEarnedMinutes) min",
                        icon: .boltFill,
                        tint: AppColors.success
                    )
                    Divider()
                    activityRow(
                        label: "Total Sessions",
                        value: "\(stats.totalSessions)",
                        icon: .timer,
                        tint: AppColors.secondary
                    )
                    Divider()
                    activityRow(
                        label: "Active Days",
                        value: "\(stats.activeDays)",
                        icon: .calendarBadgeCheckmark,
                        tint: AppColors.info
                    )
                    Divider()
                    activityRow(
                        label: "Current Streak",
                        value: "\(stats.currentStreakDays) days",
                        icon: .flameFill,
                        tint: AppColors.warning
                    )
                }
            }
        }
    }

    private func activityRow(
        label: String,
        value: String,
        icon: AppIcon,
        tint: Color
    ) -> some View {
        HStack {
            Image(systemName: icon.rawValue)
                .font(.system(size: AppSpacing.iconSizeSmall, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: AppSpacing.iconSizeStandard)

            Text(label)
                .font(AppTypography.body)
                .foregroundStyle(AppColors.textPrimary)

            Spacer()

            Text(value)
                .font(AppTypography.bodySemibold)
                .foregroundStyle(AppColors.textPrimary)
        }
    }

    // MARK: - Section Header

    private func sectionHeader(title: String, icon: AppIcon, tint: Color) -> some View {
        HStack(spacing: AppSpacing.xs) {
            Image(systemName: icon.rawValue)
                .font(.system(size: AppSpacing.iconSizeSmall, weight: .semibold))
                .foregroundStyle(tint)

            Text(title)
                .font(AppTypography.headline)
                .foregroundStyle(AppColors.textPrimary)
        }
    }

    // MARK: - Loading Content

    @ViewBuilder
    private var loadingContent: some View {
        // Streak banner skeleton
        RoundedRectangle(cornerRadius: AppSpacing.cornerRadiusCard)
            .fill(AppColors.fill)
            .frame(height: 80)
            .shimmer()

        // Hero card skeleton
        RoundedRectangle(cornerRadius: AppSpacing.cornerRadiusCard)
            .fill(AppColors.fill)
            .frame(height: 140)
            .shimmer()

        // Grid skeletons
        LazyVGrid(columns: Self.twoColumns, spacing: AppSpacing.sm) {
            ForEach(0..<4, id: \.self) { _ in
                RoundedRectangle(cornerRadius: AppSpacing.cornerRadiusCard)
                    .fill(AppColors.fill)
                    .frame(height: 80)
                    .shimmer()
            }
        }
    }

    // MARK: - Empty Content

    private var emptyContent: some View {
        EmptyStateCard(
            icon: .chartBarFill,
            title: "No stats yet",
            message: "Complete your first workout to see your lifetime statistics here."
        )
    }
}

// MARK: - Shimmer Modifier

private extension View {
    func shimmer() -> some View {
        modifier(ShimmerModifier())
    }
}

private struct ShimmerModifier: ViewModifier {
    @State private var isAnimating = false

    func body(content: Content) -> some View {
        content
            .opacity(isAnimating ? 0.5 : 1.0)
            .animation(
                .easeInOut(duration: 0.9).repeatForever(autoreverses: true),
                value: isAnimating
            )
            .onAppear { isAnimating = true }
    }
}

// MARK: - Previews

#if DEBUG
#Preview("TotalStatsView") {
    let sampleStats = TotalStatsData(
        totalPushUps: 2_847,
        totalSessions: 94,
        totalEarnedMinutes: 948,
        longestStreakDays: 14,
        currentStreakDays: 7,
        averagePushUpsPerSession: 30.3,
        averageSessionDurationSeconds: 7 * 60 + 12,
        bestSingleSession: 68,
        bestDay: 112,
        bestWeek: 287,
        activeDays: 61,
        averageQuality: 0.81
    )

    ScrollView {
        VStack(spacing: AppSpacing.md) {
            TotalStatsView(stats: sampleStats, isLoading: false)
            Divider()
            TotalStatsView(stats: nil, isLoading: true)
        }
        .padding(AppSpacing.md)
    }
    .background(AppColors.backgroundPrimary)
}
#endif
