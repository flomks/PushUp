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

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {

            // Section header
            HStack {
                Label("Heute", icon: .calendarBadgeCheckmark)
                    .font(AppTypography.headline)
                    .foregroundStyle(AppColors.textPrimary)

                Spacer()

                Text(todayDateString)
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
        LazyVGrid(
            columns: [GridItem(.flexible()), GridItem(.flexible())],
            spacing: AppSpacing.xs
        ) {
            StatCard(
                title: "Push-Ups",
                value: "\(stats.pushUps)",
                subtitle: "Heute",
                icon: .figureStrengthTraining,
                tint: AppColors.primary
            )

            StatCard(
                title: "Sessions",
                value: "\(stats.sessions)",
                subtitle: "Einheiten",
                icon: .timer,
                tint: AppColors.secondary
            )

            StatCard(
                title: "Verdient",
                value: "\(stats.earnedMinutes) Min",
                subtitle: "Zeitguthaben",
                icon: .boltFill,
                tint: AppColors.success
            )

            StatCard(
                title: "Qualitaet",
                value: String(format: "%.0f%%", stats.averageQuality * 100),
                subtitle: "Durchschnitt",
                icon: .starFill,
                tint: AppColors.formScoreColor(stats.averageQuality)
            )
        }
    }

    @ViewBuilder
    private var loadingSkeleton: some View {
        LazyVGrid(
            columns: [GridItem(.flexible()), GridItem(.flexible())],
            spacing: AppSpacing.xs
        ) {
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
                Text("Noch kein Workout heute")
                    .font(AppTypography.bodySemibold)
                    .foregroundStyle(AppColors.textPrimary)

                Text("Starte ein Workout, um Zeitguthaben zu verdienen.")
                    .font(AppTypography.caption1)
                    .foregroundStyle(AppColors.textSecondary)
            }

            Spacer()
        }
        .padding(.vertical, AppSpacing.xs)
    }

    // MARK: - Helpers

    private var todayDateString: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "d. MMM"
        formatter.locale = Locale(identifier: "de_DE")
        return formatter.string(from: Date())
    }
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
