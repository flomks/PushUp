import SwiftUI

// MARK: - WeeklyChart

/// Bar chart showing push-up counts for each day of the current week.
///
/// Each bar is proportionally scaled to the week's maximum. Today's bar
/// is highlighted with the primary gradient. Days with no activity show
/// a subtle empty bar. The chart is purely SwiftUI -- no Charts framework
/// dependency required.
///
/// Usage:
/// ```swift
/// WeeklyChart(days: viewModel.weekDays, isLoading: viewModel.isLoading)
/// ```
struct WeeklyChart: View {

    let days: [DashboardWeekDay]
    let isLoading: Bool

    private let barMaxHeight: CGFloat = 80
    private let barMinHeight: CGFloat = 4

    var body: some View {
        let total = days.map(\.pushUps).reduce(0, +)

        VStack(alignment: .leading, spacing: AppSpacing.sm) {

            // Section header
            HStack {
                Label("This Week", icon: .chartBar)
                    .font(AppTypography.headline)
                    .foregroundStyle(AppColors.textPrimary)

                Spacer()

                if !isLoading, total > 0 {
                    Text("\(total) Push-Ups")
                        .font(AppTypography.captionSemibold)
                        .foregroundStyle(AppColors.primary)
                }
            }

            if isLoading {
                loadingSkeleton
            } else if days.isEmpty || total == 0 {
                emptyChartView
            } else {
                chartBars
            }
        }
        .padding(AppSpacing.md)
        .background(AppColors.backgroundSecondary)
        .clipShape(RoundedRectangle(cornerRadius: AppSpacing.cornerRadiusCard))
        .shadow(color: Color.black.opacity(0.06), radius: 8, x: 0, y: 2)
    }

    // MARK: - Sub-views

    @ViewBuilder
    private var chartBars: some View {
        let maxValue = days.map(\.pushUps).max() ?? 1

        HStack(alignment: .bottom, spacing: AppSpacing.xs) {
            ForEach(days) { day in
                DayBar(
                    day: day,
                    maxPushUps: maxValue,
                    barMaxHeight: barMaxHeight,
                    barMinHeight: barMinHeight
                )
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, AppSpacing.xs)
    }

    @ViewBuilder
    private var loadingSkeleton: some View {
        HStack(alignment: .bottom, spacing: AppSpacing.xs) {
            ForEach(0..<7, id: \.self) { idx in
                SkeletonBar(
                    heightFraction: Self.skeletonHeights[idx],
                    barMaxHeight: barMaxHeight
                )
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, AppSpacing.xs)
    }

    @ViewBuilder
    private var emptyChartView: some View {
        HStack(alignment: .bottom, spacing: AppSpacing.xs) {
            ForEach(days.isEmpty ? Self.defaultEmptyDays : days) { day in
                EmptyDayBar(label: day.label, isToday: day.isToday)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, AppSpacing.xs)
    }

    // MARK: - Constants

    private static let skeletonHeights: [CGFloat] = [0.6, 0.3, 0.8, 0.4, 0.7, 0.2, 0.5]

    /// Pre-built empty days array using the shared `WeekdayHelper`.
    /// Static to avoid recreating on every body evaluation.
    private static let defaultEmptyDays: [DashboardWeekDay] = {
        let todayIdx = WeekdayHelper.todayIndex()
        return WeekdayHelper.dayLabels.enumerated().map { idx, label in
            DashboardWeekDay(id: idx, label: label, pushUps: 0, isToday: idx == todayIdx)
        }
    }()
}

// MARK: - DayBar

private struct DayBar: View {

    let day: DashboardWeekDay
    let maxPushUps: Int
    let barMaxHeight: CGFloat
    let barMinHeight: CGFloat

    @State private var appeared = false

    private var heightFraction: CGFloat {
        guard maxPushUps > 0, day.pushUps > 0 else { return 0 }
        return CGFloat(day.pushUps) / CGFloat(maxPushUps)
    }

    private var barHeight: CGFloat {
        guard day.pushUps > 0 else { return barMinHeight }
        return max(barMinHeight, barMaxHeight * heightFraction)
    }

    var body: some View {
        VStack(spacing: AppSpacing.xxs) {
            // Push-up count label
            if day.isToday || day.pushUps > 0 {
                Text(day.pushUps > 0 ? "\(day.pushUps)" : "")
                    .font(AppTypography.caption2)
                    .foregroundStyle(day.isToday ? AppColors.primary : AppColors.textSecondary)
                    .frame(height: 14)
            } else {
                Spacer().frame(height: 14)
            }

            // Bar
            RoundedRectangle(cornerRadius: 4)
                .fill(barFill)
                .frame(height: appeared ? barHeight : barMinHeight)
                .animation(
                    .spring(duration: 0.6, bounce: 0.2).delay(Double(day.id) * 0.05),
                    value: appeared
                )

            // Day label
            Text(day.label)
                .font(AppTypography.caption2)
                .foregroundStyle(day.isToday ? AppColors.primary : AppColors.textSecondary)
                .fontWeight(day.isToday ? .semibold : .regular)
        }
        .frame(maxWidth: .infinity)
        .onAppear { appeared = true }
    }

    private var barFill: AnyShapeStyle {
        if day.isToday && day.pushUps > 0 {
            return AnyShapeStyle(
                LinearGradient(
                    colors: [AppColors.primary, AppColors.secondary],
                    startPoint: .bottom,
                    endPoint: .top
                )
            )
        } else if day.pushUps > 0 {
            return AnyShapeStyle(AppColors.primary.opacity(0.35))
        } else {
            return AnyShapeStyle(AppColors.fill)
        }
    }
}

// MARK: - EmptyDayBar

private struct EmptyDayBar: View {

    let label: String
    let isToday: Bool

    var body: some View {
        VStack(spacing: AppSpacing.xxs) {
            Spacer().frame(height: 14)

            RoundedRectangle(cornerRadius: 4)
                .fill(isToday ? AppColors.primary.opacity(0.2) : AppColors.fill)
                .frame(height: 4)
                .overlay(
                    isToday
                        ? RoundedRectangle(cornerRadius: 4)
                            .strokeBorder(AppColors.primary.opacity(0.4), lineWidth: 1)
                        : nil
                )

            Text(label)
                .font(AppTypography.caption2)
                .foregroundStyle(isToday ? AppColors.primary : AppColors.textSecondary)
                .fontWeight(isToday ? .semibold : .regular)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - SkeletonBar

private struct SkeletonBar: View {

    let heightFraction: CGFloat
    let barMaxHeight: CGFloat
    @State private var isAnimating = false

    var body: some View {
        VStack(spacing: AppSpacing.xxs) {
            Spacer().frame(height: 14)

            RoundedRectangle(cornerRadius: 4)
                .fill(AppColors.fill)
                .frame(height: barMaxHeight * heightFraction)
                .opacity(isAnimating ? 0.5 : 1.0)
                .animation(
                    .easeInOut(duration: 0.9).repeatForever(autoreverses: true),
                    value: isAnimating
                )

            RoundedRectangle(cornerRadius: 2)
                .fill(AppColors.fill)
                .frame(width: 20, height: 10)
                .opacity(isAnimating ? 0.5 : 1.0)
        }
        .frame(maxWidth: .infinity)
        .onAppear { isAnimating = true }
    }
}

// MARK: - Preview

#if DEBUG
#Preview("WeeklyChart") {
    let sampleDays: [DashboardWeekDay] = [
        DashboardWeekDay(id: 0, label: "Mo", pushUps: 35, isToday: false),
        DashboardWeekDay(id: 1, label: "Di", pushUps: 0,  isToday: false),
        DashboardWeekDay(id: 2, label: "Mi", pushUps: 52, isToday: false),
        DashboardWeekDay(id: 3, label: "Do", pushUps: 18, isToday: false),
        DashboardWeekDay(id: 4, label: "Fr", pushUps: 42, isToday: true),
        DashboardWeekDay(id: 5, label: "Sa", pushUps: 0,  isToday: false),
        DashboardWeekDay(id: 6, label: "So", pushUps: 0,  isToday: false),
    ]

    ScrollView {
        VStack(spacing: AppSpacing.md) {
            WeeklyChart(days: sampleDays, isLoading: false)
            WeeklyChart(days: [], isLoading: false)
            WeeklyChart(days: [], isLoading: true)
        }
        .padding(AppSpacing.md)
    }
    .background(AppColors.backgroundPrimary)
}
#endif
