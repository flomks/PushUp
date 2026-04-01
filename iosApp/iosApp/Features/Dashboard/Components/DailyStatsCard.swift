import SwiftUI

// MARK: - DailyStatsCard

/// Today's stats in the compact 3-column dashboard widget layout (reference: dark iOS-style cards).
struct DailyStatsCard: View {

    let stats: DashboardDailyStats?
    let isLoading: Bool

    private static let gridColumns = [
        GridItem(.flexible()),
        GridItem(.flexible()),
        GridItem(.flexible()),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 10) {
                Image(systemName: "waveform.path.ecg")
                    .font(.system(size: 18, weight: .regular))
                    .foregroundStyle(DashboardWidgetChrome.labelSecondary)

                Text("Today's Stats")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(DashboardWidgetChrome.labelPrimary)

                Spacer()
            }

            if isLoading {
                loadingSkeleton
            } else if let stats {
                statsRow(stats)
            } else {
                emptyDayView
            }
        }
        .padding(DashboardWidgetChrome.padding)
        .dashboardWidgetChrome()
    }

    // MARK: - Sub-views

    @ViewBuilder
    private func statsRow(_ stats: DashboardDailyStats) -> some View {
        LazyVGrid(columns: Self.gridColumns, spacing: 12) {
            statColumn(label: "Push-ups", value: "\(stats.pushUpCount)")
            statColumn(label: "Workouts", value: "\(stats.sessions)")
            statColumn(label: "Minutes", value: "\(stats.activeMinutes)")
        }
    }

    private func statColumn(label: String, value: String) -> some View {
        VStack(spacing: 6) {
            Text(label)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(DashboardWidgetChrome.labelSecondary)
                .multilineTextAlignment(.center)

            Text(value)
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(DashboardWidgetChrome.labelPrimary)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .frame(maxWidth: .infinity)
        }
        .multilineTextAlignment(.center)
    }

    @ViewBuilder
    private var loadingSkeleton: some View {
        LazyVGrid(columns: Self.gridColumns, spacing: 12) {
            ForEach(0..<3, id: \.self) { _ in
                VStack(spacing: 6) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.white.opacity(0.08))
                        .frame(height: 12)
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.white.opacity(0.12))
                        .frame(height: 28)
                }
                .frame(maxWidth: .infinity)
            }
        }
    }

    @ViewBuilder
    private var emptyDayView: some View {
        HStack(spacing: AppSpacing.sm) {
            Image(systemName: AppIcon.figureStrengthTraining.rawValue)
                .font(.system(size: AppSpacing.iconSizeLarge, weight: .light))
                .foregroundStyle(DashboardWidgetChrome.labelMuted)

            VStack(alignment: .leading, spacing: AppSpacing.xxs) {
                Text("No activity yet today")
                    .font(AppTypography.bodySemibold)
                    .foregroundStyle(DashboardWidgetChrome.labelPrimary)

                Text("Start an activity to earn time credit.")
                    .font(AppTypography.caption1)
                    .foregroundStyle(DashboardWidgetChrome.labelSecondary)
            }

            Spacer()
        }
        .padding(.vertical, AppSpacing.xs)
    }
}

// MARK: - Preview

#if DEBUG
#Preview("DailyStatsCard") {
    ScrollView {
        VStack(spacing: AppSpacing.md) {

            DailyStatsCard(
                stats: DashboardDailyStats(
                    pushUpCount: 87,
                    activeMinutes: 45,
                    sessions: 3,
                    earnedMinutes: 14,
                    averageQuality: 0.84
                ),
                isLoading: false
            )

            DailyStatsCard(stats: nil, isLoading: false)

            DailyStatsCard(stats: nil, isLoading: true)
        }
        .padding(AppSpacing.md)
    }
    .background(DashboardWidgetChrome.pageBackground)
}
#endif
