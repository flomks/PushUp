import SwiftUI

// MARK: - TimeCreditDetailView

/// Sheet view showing a detailed breakdown of the user's current time credit.
///
/// Displays:
/// - Current available balance (hero)
/// - How the balance is composed (carry-over from yesterday + today's workouts)
/// - How much has been spent today
/// - Daily reset info (next reset time)
///
/// Presented as a sheet when the user taps the TimeCreditCard on the Dashboard.
struct TimeCreditDetailView: View {

    let availableSeconds: Int
    let dailyEarnedSeconds: Int
    let dailySpentSeconds: Int
    let todayWorkoutEarned: Int
    let carryOverSeconds: Int
    let totalEarnedSeconds: Int

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: AppSpacing.lg) {
                    heroSection
                    breakdownSection
                    spentSection
                    resetInfoSection
                    allTimeSection
                }
                .padding(.horizontal, AppSpacing.screenHorizontal)
                .padding(.top, AppSpacing.sm)
                .padding(.bottom, AppSpacing.screenVerticalBottom)
            }
            .background(AppColors.backgroundPrimary)
            .navigationTitle("Time Credit")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                        .font(AppTypography.bodySemibold)
                }
            }
        }
    }

    // MARK: - Hero Section

    private var heroSection: some View {
        Card(padding: AppSpacing.lg) {
            VStack(spacing: AppSpacing.sm) {
                Text("Available Now")
                    .font(AppTypography.caption1)
                    .foregroundStyle(AppColors.textSecondary)

                Text(formatTime(availableSeconds))
                    .font(AppTypography.monoDisplay)
                    .foregroundStyle(AppColors.textPrimary)
                    .contentTransition(.numericText())

                if dailyEarnedSeconds > 0 {
                    progressBar
                }
            }
            .frame(maxWidth: .infinity)
        }
    }

    private var progressBar: some View {
        let fraction = dailyEarnedSeconds > 0
            ? CGFloat(max(0, availableSeconds)) / CGFloat(dailyEarnedSeconds)
            : 0.0

        return VStack(spacing: AppSpacing.xxs) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(AppColors.fill)
                        .frame(height: 8)

                    RoundedRectangle(cornerRadius: 4)
                        .fill(
                            LinearGradient(
                                colors: [AppColors.primary, AppColors.secondary],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: geo.size.width * min(1.0, fraction), height: 8)
                        .animation(.spring(duration: 0.6), value: fraction)
                }
            }
            .frame(height: 8)

            HStack {
                Text(String(format: "%.0f%% remaining", min(100, fraction * 100)))
                    .font(AppTypography.caption2)
                    .foregroundStyle(AppColors.textTertiary)
                Spacer()
                Text("of \(formatTimeShort(dailyEarnedSeconds)) daily budget")
                    .font(AppTypography.caption2)
                    .foregroundStyle(AppColors.textTertiary)
            }
        }
    }

    // MARK: - Breakdown Section

    private var breakdownSection: some View {
        Card {
            VStack(alignment: .leading, spacing: AppSpacing.sm) {
                Label("Credit Sources", icon: .arrowDownCircleFill)
                    .font(AppTypography.headline)
                    .foregroundStyle(AppColors.textPrimary)

                Divider()

                if carryOverSeconds > 0 {
                    breakdownRow(
                        icon: .clockArrowCirclepath,
                        label: "Carry-over from yesterday",
                        value: formatTimeShort(carryOverSeconds),
                        tint: AppColors.info,
                        detail: "20% of unused + 100% of late-night credits"
                    )
                }

                if todayWorkoutEarned > 0 {
                    breakdownRow(
                        icon: .figureStrengthTraining,
                        label: "Today's workouts",
                        value: formatTimeShort(todayWorkoutEarned),
                        tint: AppColors.success,
                        detail: nil
                    )
                }

                if carryOverSeconds == 0 && todayWorkoutEarned == 0 {
                    HStack(spacing: AppSpacing.xs) {
                        Image(systemName: AppIcon.infoCircle.rawValue)
                            .foregroundStyle(AppColors.textTertiary)
                            .font(.system(size: AppSpacing.iconSizeStandard))

                        Text("No credits earned yet today. Complete a workout to earn screen time!")
                            .font(AppTypography.callout)
                            .foregroundStyle(AppColors.textSecondary)
                    }
                    .padding(.vertical, AppSpacing.xxs)
                }

                Divider()

                // Total daily budget
                HStack {
                    Text("Daily Budget")
                        .font(AppTypography.bodySemibold)
                        .foregroundStyle(AppColors.textPrimary)
                    Spacer()
                    Text(formatTimeShort(dailyEarnedSeconds))
                        .font(AppTypography.bodySemibold)
                        .foregroundStyle(AppColors.primary)
                }
            }
        }
    }

    @ViewBuilder
    private func breakdownRow(
        icon: AppIcon,
        label: String,
        value: String,
        tint: Color,
        detail: String?
    ) -> some View {
        HStack(alignment: .top, spacing: AppSpacing.sm) {
            Image(systemName: icon.rawValue)
                .foregroundStyle(tint)
                .font(.system(size: AppSpacing.iconSizeStandard, weight: .semibold))
                .frame(width: 24)

            VStack(alignment: .leading, spacing: AppSpacing.xxs) {
                HStack {
                    Text(label)
                        .font(AppTypography.callout)
                        .foregroundStyle(AppColors.textPrimary)
                    Spacer()
                    Text(value)
                        .font(AppTypography.bodySemibold)
                        .foregroundStyle(tint)
                }

                if let detail {
                    Text(detail)
                        .font(AppTypography.caption1)
                        .foregroundStyle(AppColors.textTertiary)
                }
            }
        }
        .padding(.vertical, AppSpacing.xxs)
    }

    // MARK: - Spent Section

    private var spentSection: some View {
        Card {
            VStack(alignment: .leading, spacing: AppSpacing.sm) {
                Label("Screen Time Used", icon: .hourglassFill)
                    .font(AppTypography.headline)
                    .foregroundStyle(AppColors.textPrimary)

                Divider()

                HStack(spacing: AppSpacing.sm) {
                    Image(systemName: AppIcon.clock.rawValue)
                        .foregroundStyle(dailySpentSeconds > 0 ? AppColors.warning : AppColors.textTertiary)
                        .font(.system(size: AppSpacing.iconSizeStandard, weight: .semibold))
                        .frame(width: 24)

                    VStack(alignment: .leading, spacing: AppSpacing.xxs) {
                        Text("Used today")
                            .font(AppTypography.callout)
                            .foregroundStyle(AppColors.textPrimary)

                        if dailySpentSeconds > 0 {
                            Text("Deducted from your daily budget")
                                .font(AppTypography.caption1)
                                .foregroundStyle(AppColors.textTertiary)
                        } else {
                            Text("No screen time used yet today")
                                .font(AppTypography.caption1)
                                .foregroundStyle(AppColors.textTertiary)
                        }
                    }

                    Spacer()

                    Text(dailySpentSeconds > 0 ? "-\(formatTimeShort(dailySpentSeconds))" : "0 min")
                        .font(AppTypography.bodySemibold)
                        .foregroundStyle(dailySpentSeconds > 0 ? AppColors.warning : AppColors.textTertiary)
                }
            }
        }
    }

    // MARK: - Reset Info Section

    private var resetInfoSection: some View {
        Card {
            HStack(spacing: AppSpacing.sm) {
                Image(systemName: AppIcon.clockArrowForward.rawValue)
                    .foregroundStyle(AppColors.info)
                    .font(.system(size: AppSpacing.iconSizeStandard, weight: .semibold))
                    .frame(width: 24)

                VStack(alignment: .leading, spacing: AppSpacing.xxs) {
                    Text("Daily Reset")
                        .font(AppTypography.callout)
                        .foregroundStyle(AppColors.textPrimary)

                    Text("Credits reset at 3:00 AM. Up to 20% of unused time carries over to the next day. Credits earned between 2-3 AM carry over at 100%.")
                        .font(AppTypography.caption1)
                        .foregroundStyle(AppColors.textSecondary)
                }

                Spacer()
            }
        }
    }

    // MARK: - All-Time Section

    private var allTimeSection: some View {
        Card {
            VStack(alignment: .leading, spacing: AppSpacing.sm) {
                Label("All-Time Stats", icon: .chartBarFill)
                    .font(AppTypography.headline)
                    .foregroundStyle(AppColors.textPrimary)

                Divider()

                HStack {
                    VStack(spacing: AppSpacing.xxs) {
                        Text(formatTimeShort(totalEarnedSeconds))
                            .font(AppTypography.bodySemibold)
                            .foregroundStyle(AppColors.success)
                        Text("Total Earned")
                            .font(AppTypography.caption1)
                            .foregroundStyle(AppColors.textSecondary)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
    }

    // MARK: - Formatting Helpers

    private func formatTime(_ seconds: Int) -> String {
        let clamped = max(0, seconds)
        let h = clamped / 3600
        let m = (clamped % 3600) / 60
        let s = clamped % 60
        return String(format: "%02d:%02d:%02d", h, m, s)
    }

    private func formatTimeShort(_ seconds: Int) -> String {
        let clamped = max(0, seconds)
        let minutes = clamped / 60
        if minutes >= 60 {
            let h = minutes / 60
            let m = minutes % 60
            return m > 0 ? "\(h)h \(m)m" : "\(h)h"
        }
        if minutes == 0 && clamped > 0 {
            return "\(clamped)s"
        }
        return "\(minutes) min"
    }
}

// MARK: - Preview

#if DEBUG
#Preview("Time Credit Detail") {
    TimeCreditDetailView(
        availableSeconds: 2700,
        dailyEarnedSeconds: 5400,
        dailySpentSeconds: 2700,
        todayWorkoutEarned: 3600,
        carryOverSeconds: 1800,
        totalEarnedSeconds: 36000
    )
}

#Preview("Time Credit Detail - Empty") {
    TimeCreditDetailView(
        availableSeconds: 0,
        dailyEarnedSeconds: 0,
        dailySpentSeconds: 0,
        todayWorkoutEarned: 0,
        carryOverSeconds: 0,
        totalEarnedSeconds: 0
    )
}
#endif
