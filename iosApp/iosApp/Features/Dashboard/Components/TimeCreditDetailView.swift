import SwiftUI
import Shared

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
    let carryOverPercentSeconds: Int
    let carryOverLateNightSeconds: Int
    let totalEarnedSeconds: Int
    let totalSpentSeconds: Int
    let userId: String

    @Environment(\.dismiss) private var dismiss
    @State private var historyEntries: [CreditHistoryChartEntry] = []
    @State private var isLoadingHistory = true

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: AppSpacing.lg) {
                    heroSection
                    breakdownSection
                    spentSection
                    CreditHistoryChart(entries: historyEntries, isLoading: isLoadingHistory)
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
            .task { await loadHistory() }
        }
    }

    // MARK: - History Loading

    private func loadHistory() async {
        guard !userId.isEmpty else {
            isLoadingHistory = false
            return
        }

        let calendar = Calendar.current
        let today = Date()
        // Fetch the last 7 days of snapshots.
        let sevenDaysAgo = calendar.date(byAdding: .day, value: -6, to: today)!

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        let fromStr = formatter.string(from: sevenDaysAgo)
        let toStr = formatter.string(from: today)

        let dayFormatter = DateFormatter()
        dayFormatter.dateFormat = "EEE"

        DataBridge.shared.fetchCreditHistory(userId: userId, from: fromStr, to: toStr) { (rawEntries: [CreditHistoryEntry]) in
            // Build chart entries for all 7 days, filling gaps with zeros.
            var entryMap: [String: (earned: Double, spent: Double)] = [:]
            for rawEntry in rawEntries {
                let dateKey: String = rawEntry.date
                let earned: Double = Double(rawEntry.earnedSeconds) / 60.0
                let spent: Double = Double(rawEntry.spentSeconds) / 60.0
                entryMap[dateKey] = (earned: earned, spent: spent)
            }

            var chartEntries: [CreditHistoryChartEntry] = []
            for daysAgo in (0...6).reversed() {
                let date: Date = calendar.date(byAdding: .day, value: -daysAgo, to: today)!
                let dateStr: String = formatter.string(from: date)
                let values = entryMap[dateStr]
                let entry = CreditHistoryChartEntry(
                    id: dateStr,
                    label: dayFormatter.string(from: date),
                    date: date,
                    earnedMinutes: values?.earned ?? 0,
                    spentMinutes: values?.spent ?? 0
                )
                chartEntries.append(entry)
            }

            self.historyEntries = chartEntries
            self.isLoadingHistory = false
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

                if carryOverPercentSeconds > 0 {
                    breakdownRow(
                        icon: .clockArrowCirclepath,
                        label: "Carry-over (20%)",
                        value: formatTimeShort(carryOverPercentSeconds),
                        tint: AppColors.info,
                        detail: "20% of unused time from yesterday"
                    )
                }

                if carryOverLateNightSeconds > 0 {
                    breakdownRow(
                        icon: .moonFill,
                        label: "Late-night bonus",
                        value: formatTimeShort(carryOverLateNightSeconds),
                        tint: AppColors.primaryVariant,
                        detail: "100% carry-over for workouts between 2-3 AM"
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

                if carryOverPercentSeconds == 0 && carryOverLateNightSeconds == 0 && todayWorkoutEarned == 0 {
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

                    Divider().frame(height: 36)

                    VStack(spacing: AppSpacing.xxs) {
                        Text(formatTimeShort(totalSpentSeconds))
                            .font(AppTypography.bodySemibold)
                            .foregroundStyle(AppColors.warning)
                        Text("Total Used")
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
#Preview("Time Credit Detail - Full") {
    TimeCreditDetailView(
        availableSeconds: 2700,
        dailyEarnedSeconds: 5400,
        dailySpentSeconds: 2700,
        todayWorkoutEarned: 3600,
        carryOverPercentSeconds: 600,
        carryOverLateNightSeconds: 1200,
        totalEarnedSeconds: 36000,
        totalSpentSeconds: 28800,
        userId: "preview-user"
    )
}

#Preview("Time Credit Detail - No Late Night") {
    TimeCreditDetailView(
        availableSeconds: 1800,
        dailyEarnedSeconds: 3600,
        dailySpentSeconds: 1800,
        todayWorkoutEarned: 3000,
        carryOverPercentSeconds: 600,
        carryOverLateNightSeconds: 0,
        totalEarnedSeconds: 18000,
        totalSpentSeconds: 14400,
        userId: "preview-user"
    )
}

#Preview("Time Credit Detail - Empty") {
    TimeCreditDetailView(
        availableSeconds: 0,
        dailyEarnedSeconds: 0,
        dailySpentSeconds: 0,
        todayWorkoutEarned: 0,
        carryOverPercentSeconds: 0,
        carryOverLateNightSeconds: 0,
        totalEarnedSeconds: 0,
        totalSpentSeconds: 0,
        userId: "preview-user"
    )
}
#endif
