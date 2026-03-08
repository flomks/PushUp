import SwiftUI

// MARK: - DailyStatsCard

/// Card displaying today's aggregated workout statistics in a 2x2 grid
/// of `StatCard` components from the design system.
///
/// Shows push-ups, sessions, earned time, and average quality for the
/// current day. Renders a skeleton loading state when `isLoading` is true.
///
/// Usage:
/// ```swift
/// DailyStatsCard(stats: viewModel.dailyStats, isLoading: viewModel.isLoading)
/// ```
struct DailyStatsCard: View {

    let stats: DashboardDailyStats?
    let isLoading: Bool

    /// Shared 2-column grid layout used by both the real stats and the
    /// skeleton placeholder.
    private static let gridColumns = [
        GridItem(.flexible()),
        GridItem(.flexible()),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {

            // Section header
            HStack {
                Label("Today", icon: .calendarBadgeCheckmark)
                    .font(AppTypography.headline)
                    .foregroundStyle(AppColors.textPrimary)

                Spacer()

                Text(Self.todayDateString)
                    .font(AppTypography.caption1)
                    .foregroundStyle(AppColors.textSecondary)
            }

            if isLoading {
                loadingSkeleton
            } else if let stats {
                statsGrid(stats)
            } else {
                emptyDayView
            }
        }
        .padding(AppSpacing.md)
        .background(AppColors.backgroundSecondary)
        .clipShape(RoundedRectangle(cornerRadius: AppSpacing.cornerRadiusCard))
        .shadow(color: Color.black.opacity(0.06), radius: 8, x: 0, y: 2)
    }

    // MARK: - Sub-views

    @ViewBuilder
    private func statsGrid(_ stats: DashboardDailyStats) -> some View {
        LazyVGrid(columns: Self.gridColumns, spacing: AppSpacing.xs) {
            StatCard(
                title: "Push-Ups",
                value: "\(stats.pushUps)",
                subtitle: "Today",
                icon: .figureStrengthTraining,
                tint: AppColors.primary
            )

            StatCard(
                title: "Sessions",
                value: "\(stats.sessions)",
                subtitle: "Units",
                icon: .timer,
                tint: AppColors.secondary
            )

            StatCard(
                title: "Earned",
                value: "\(stats.earnedMinutes) min",
                subtitle: "Time Credit",
                icon: .boltFill,
                tint: AppColors.success
            )

            StatCard(
                title: "Quality",
                value: String(format: "%.0f%%", stats.averageQuality * 100),
                subtitle: "Average",
                icon: .starFill,
                tint: AppColors.formScoreColor(stats.averageQuality)
            )
        }
    }

    @ViewBuilder
    private var loadingSkeleton: some View {
        LazyVGrid(columns: Self.gridColumns, spacing: AppSpacing.xs) {
            ForEach(0..<4, id: \.self) { _ in
                SkeletonStatCard()
            }
        }
    }

    @ViewBuilder
    private var emptyDayView: some View {
        HStack(spacing: AppSpacing.sm) {
            Image(systemName: AppIcon.figureStrengthTraining.rawValue)
                .font(.system(size: AppSpacing.iconSizeLarge, weight: .light))
                .foregroundStyle(AppColors.textTertiary)

            VStack(alignment: .leading, spacing: AppSpacing.xxs) {
                Text("No workout yet today")
                    .font(AppTypography.bodySemibold)
                    .foregroundStyle(AppColors.textPrimary)

                Text("Start a workout to earn time credit.")
                    .font(AppTypography.caption1)
                    .foregroundStyle(AppColors.textSecondary)
            }

            Spacer()
        }
        .padding(.vertical, AppSpacing.xs)
    }

    // MARK: - Helpers

    /// Cached date string for today. Static so the `DateFormatter` is only
    /// created once per process rather than on every body evaluation.
    private static let todayDateString: String = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        formatter.locale = Locale(identifier: "en_US")
        return formatter.string(from: Date())
    }()
}

// MARK: - SkeletonStatCard

/// Animated placeholder shown while stats are loading.
private struct SkeletonStatCard: View {

    @State private var isAnimating = false

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.xs) {
            RoundedRectangle(cornerRadius: 4)
                .fill(AppColors.fill)
                .frame(width: 60, height: 12)

            RoundedRectangle(cornerRadius: 4)
                .fill(AppColors.fill)
                .frame(width: 80, height: 28)

            RoundedRectangle(cornerRadius: 4)
                .fill(AppColors.fill)
                .frame(width: 50, height: 10)
        }
        .padding(AppSpacing.statCardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppColors.backgroundSecondary)
        .clipShape(RoundedRectangle(cornerRadius: AppSpacing.cornerRadiusCard))
        .shadow(color: Color.black.opacity(0.04), radius: 4, x: 0, y: 1)
        .opacity(isAnimating ? 0.5 : 1.0)
        .animation(
            .easeInOut(duration: 0.9).repeatForever(autoreverses: true),
            value: isAnimating
        )
        .onAppear { isAnimating = true }
    }
}

// MARK: - Preview

#if DEBUG
#Preview("DailyStatsCard") {
    ScrollView {
        VStack(spacing: AppSpacing.md) {

            DailyStatsCard(
                stats: DashboardDailyStats(
                    pushUps: 42,
                    sessions: 2,
                    earnedMinutes: 14,
                    averageQuality: 0.84,
                    bestSession: 28
                ),
                isLoading: false
            )

            DailyStatsCard(stats: nil, isLoading: false)

            DailyStatsCard(stats: nil, isLoading: true)
        }
        .padding(AppSpacing.md)
    }
    .background(AppColors.backgroundPrimary)
}
#endif
