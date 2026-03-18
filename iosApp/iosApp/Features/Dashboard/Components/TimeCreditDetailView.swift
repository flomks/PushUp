import Charts
import SwiftUI
import Shared

// MARK: - CreditHistoryChartEntry

/// A single data point for the credit history chart.
struct CreditHistoryChartEntry: Identifiable {
    let id: String
    let label: String
    let date: Date
    let earnedMinutes: Double
    let spentMinutes: Double
}

// MARK: - TimeCreditDetailView

/// Sheet view showing a detailed breakdown of the user's current time credit.
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
    @State private var isLoadingHistory: Bool = true

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: AppSpacing.lg) {
                    heroSection
                    breakdownSection
                    spentSection
                    historyChartSection
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
            .task { loadHistory() }
        }
    }

    // MARK: - History Loading

    private func loadHistory() {
        guard !userId.isEmpty else {
            isLoadingHistory = false
            return
        }

        let calendar: Calendar = Calendar.current
        let today: Date = Date()
        let sevenDaysAgo: Date = calendar.date(byAdding: .day, value: -6, to: today)!

        let isoFormatter: DateFormatter = DateFormatter()
        isoFormatter.dateFormat = "yyyy-MM-dd"
        let fromStr: String = isoFormatter.string(from: sevenDaysAgo)
        let toStr: String = isoFormatter.string(from: today)

        let dayFormatter: DateFormatter = DateFormatter()
        dayFormatter.dateFormat = "EEE"

        // Today's live data from the current credit balance (not from snapshots,
        // since today's snapshot hasn't been written yet).
        let todayEarnedMin: Double = Double(dailyEarnedSeconds) / 60.0
        let todaySpentMin: Double = Double(dailySpentSeconds) / 60.0
        let todayKey: String = isoFormatter.string(from: today)

        DataBridge.shared.fetchCreditHistory(userId: userId, from: fromStr, to: toStr) { rawEntries in
            var entryMap: [String: (earned: Double, spent: Double)] = [:]
            for rawEntry in rawEntries {
                entryMap[rawEntry.date] = (
                    earned: Double(rawEntry.earnedSeconds) / 60.0,
                    spent: Double(rawEntry.spentSeconds) / 60.0
                )
            }

            // Override today with live data (snapshot for today doesn't exist yet).
            entryMap[todayKey] = (earned: todayEarnedMin, spent: todaySpentMin)

            var result: [CreditHistoryChartEntry] = []
            var hasAnyData: Bool = false
            for daysAgo in (0...6).reversed() {
                let d: Date = calendar.date(byAdding: .day, value: -daysAgo, to: today)!
                let key: String = isoFormatter.string(from: d)
                let vals = entryMap[key]
                let earned: Double = vals?.earned ?? 0
                let spent: Double = vals?.spent ?? 0
                if earned > 0 || spent > 0 {
                    hasAnyData = true
                }
                result.append(CreditHistoryChartEntry(
                    id: key,
                    label: dayFormatter.string(from: d),
                    date: d,
                    earnedMinutes: earned,
                    spentMinutes: spent
                ))
            }

            // Only show entries if there's actual data; otherwise leave empty
            // so the "No history yet" state is shown.
            self.historyEntries = hasAnyData ? result : []
            self.isLoadingHistory = false
        }
    }

    // MARK: - History Chart Section

    private var historyChartSection: some View {
        Card {
            VStack(alignment: .leading, spacing: AppSpacing.sm) {
                HStack {
                    Label("Weekly Overview", icon: .chartLineUptrendXYAxis)
                        .font(AppTypography.headline)
                        .foregroundStyle(AppColors.textPrimary)
                    Spacer()
                }

                Divider()

                if isLoadingHistory {
                    HStack(alignment: .bottom, spacing: AppSpacing.xs) {
                        ForEach(0..<7, id: \.self) { i in
                            RoundedRectangle(cornerRadius: 4)
                                .fill(AppColors.fill)
                                .frame(height: CGFloat([56, 84, 42, 112, 70, 98, 56][i]))
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 140)
                    .redacted(reason: .placeholder)
                } else if historyEntries.isEmpty {
                    VStack(spacing: AppSpacing.sm) {
                        Image(systemName: AppIcon.chartLineUptrendXYAxis.rawValue)
                            .font(.system(size: 32))
                            .foregroundStyle(AppColors.textTertiary)
                        Text("No history yet")
                            .font(AppTypography.subheadline)
                            .foregroundStyle(AppColors.textSecondary)
                        Text("Credit history will appear after your first daily reset at 3:00 AM.")
                            .font(AppTypography.caption1)
                            .foregroundStyle(AppColors.textTertiary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 160)
                } else {
                    Chart {
                        ForEach(historyEntries) { entry in
                            BarMark(
                                x: .value("Day", entry.label),
                                y: .value("Budget", entry.earnedMinutes)
                            )
                            .foregroundStyle(AppColors.primary.opacity(0.3))
                            .cornerRadius(4)
                        }
                        ForEach(historyEntries) { entry in
                            BarMark(
                                x: .value("Day", entry.label),
                                y: .value("Used", entry.spentMinutes)
                            )
                            .foregroundStyle(AppColors.warning.opacity(0.7))
                            .cornerRadius(4)
                        }
                    }
                    .chartXAxis {
                        AxisMarks(values: .automatic) { value in
                            AxisValueLabel {
                                if let label = value.as(String.self) {
                                    Text(label)
                                        .font(AppTypography.caption2)
                                        .foregroundStyle(AppColors.textSecondary)
                                }
                            }
                        }
                    }
                    .chartYAxis {
                        AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) { value in
                            AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [4]))
                                .foregroundStyle(AppColors.fill)
                            AxisValueLabel {
                                if let intVal = value.as(Int.self) {
                                    Text("\(intVal)m")
                                        .font(AppTypography.caption2)
                                        .foregroundStyle(AppColors.textSecondary)
                                }
                            }
                        }
                    }
                    .chartPlotStyle { plotArea in
                        plotArea.background(AppColors.backgroundPrimary.opacity(0.3))
                    }
                    .chartLegend(.hidden)
                    .frame(height: 180)

                    // Legend
                    HStack(spacing: AppSpacing.md) {
                        HStack(spacing: AppSpacing.xxs) {
                            RoundedRectangle(cornerRadius: 2)
                                .fill(AppColors.primary.opacity(0.3))
                                .frame(width: 12, height: 12)
                            Text("Daily Budget")
                                .font(AppTypography.caption2)
                                .foregroundStyle(AppColors.textSecondary)
                        }
                        HStack(spacing: AppSpacing.xxs) {
                            RoundedRectangle(cornerRadius: 2)
                                .fill(AppColors.warning.opacity(0.7))
                                .frame(width: 12, height: 12)
                            Text("Screen Time")
                                .font(AppTypography.caption2)
                                .foregroundStyle(AppColors.textSecondary)
                        }
                    }
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
#Preview("Time Credit Detail") {
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
#endif
