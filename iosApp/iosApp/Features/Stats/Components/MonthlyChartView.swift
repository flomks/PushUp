import Charts
import SwiftUI

// MARK: - MonthlyChartView

/// Detailed monthly stats view for the Stats screen.
///
/// Shows a Swift Charts line chart (trend over weeks) plus summary cards
/// and a month-over-month comparison badge.
///
/// Usage:
/// ```swift
/// MonthlyChartView(
///     weeks: viewModel.monthlyWeeks,
///     totalPushUps: viewModel.monthlyTotalPushUps,
///     totalSessions: viewModel.monthlyTotalSessions,
///     earnedMinutes: viewModel.monthlyEarnedMinutes,
///     comparison: viewModel.monthComparison,
///     isLoading: viewModel.isLoading
/// )
/// ```
struct MonthlyChartView: View {

    let weeks: [MonthlyWeekData]
    let totalPushUps: Int
    let totalSessions: Int
    let earnedMinutes: Int
    let comparison: MonthComparison?
    let isLoading: Bool

    private static let summaryColumns = [
        GridItem(.flexible()),
        GridItem(.flexible()),
    ]

    var body: some View {
        VStack(spacing: AppSpacing.md) {
            lineChartCard
            if let comparison, !isLoading {
                comparisonCard(comparison)
            }
            summaryGrid
        }
    }

    // MARK: - Line Chart Card

    private var lineChartCard: some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {

            // Header
            HStack {
                Label("Monthly Trend", icon: .chartBar)
                    .font(AppTypography.headline)
                    .foregroundStyle(AppColors.textPrimary)

                Spacer()

                if !isLoading, totalPushUps > 0 {
                    Text("\(totalPushUps) Push-Ups")
                        .font(AppTypography.captionSemibold)
                        .foregroundStyle(AppColors.primary)
                }
            }

            if isLoading {
                lineChartSkeleton
            } else {
                lineChart
            }
        }
        .padding(AppSpacing.md)
        .background(AppColors.backgroundSecondary)
        .clipShape(RoundedRectangle(cornerRadius: AppSpacing.cornerRadiusCard))
        .shadow(color: Color.black.opacity(0.06), radius: 8, x: 0, y: 2)
    }

    // MARK: - Line Chart (Swift Charts)

    @ViewBuilder
    private var lineChart: some View {
        Chart(weeks) { week in
            // Area fill under the line
            AreaMark(
                x: .value("Week", week.label),
                y: .value("Push-Ups", week.totalPushUps)
            )
            .foregroundStyle(
                LinearGradient(
                    colors: [AppColors.primary.opacity(0.25), AppColors.primary.opacity(0.02)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .interpolationMethod(.catmullRom)

            // Line
            LineMark(
                x: .value("Week", week.label),
                y: .value("Push-Ups", week.totalPushUps)
            )
            .foregroundStyle(
                LinearGradient(
                    colors: [AppColors.primary, AppColors.secondary],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .lineStyle(StrokeStyle(lineWidth: 2.5))
            .interpolationMethod(.catmullRom)

            // Data point dots
            PointMark(
                x: .value("Week", week.label),
                y: .value("Push-Ups", week.totalPushUps)
            )
            .foregroundStyle(AppColors.primary)
            .symbolSize(36)
            .annotation(position: .top, alignment: .center) {
                Text("\(week.totalPushUps)")
                    .font(AppTypography.caption2)
                    .foregroundStyle(AppColors.textSecondary)
                    .padding(.bottom, 2)
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
                    .foregroundStyle(AppColors.separator.opacity(0.5))
                AxisValueLabel {
                    if let intVal = value.as(Int.self) {
                        Text("\(intVal)")
                            .font(AppTypography.caption2)
                            .foregroundStyle(AppColors.textSecondary)
                    }
                }
            }
        }
        .chartPlotStyle { plotArea in
            plotArea.background(AppColors.backgroundPrimary.opacity(0.3))
        }
        .frame(height: 180)
        .animation(.spring(duration: 0.7, bounce: 0.1), value: weeks.map(\.totalPushUps))
    }

    // MARK: - Line Chart Skeleton

    @ViewBuilder
    private var lineChartSkeleton: some View {
        RoundedRectangle(cornerRadius: AppSpacing.cornerRadiusCard)
            .fill(AppColors.fill)
            .frame(height: 180)
            .overlay(
                SkeletonLineOverlay()
            )
    }

    // MARK: - Comparison Card

    private func comparisonCard(_ comparison: MonthComparison) -> some View {
        Card {
            HStack(spacing: AppSpacing.md) {
                // Icon
                ZStack {
                    Circle()
                        .fill(comparison.isImprovement
                              ? AppColors.success.opacity(0.15)
                              : AppColors.error.opacity(0.15))
                        .frame(width: 44, height: 44)

                    Image(systemName: comparison.isImprovement
                          ? AppIcon.arrowUpRight.rawValue
                          : AppIcon.arrowDownRight.rawValue)
                        .font(.system(size: AppSpacing.iconSizeStandard, weight: .bold))
                        .foregroundStyle(comparison.isImprovement ? AppColors.success : AppColors.error)
                }

                VStack(alignment: .leading, spacing: AppSpacing.xxs) {
                    Text("vs. Last Month")
                        .font(AppTypography.caption1)
                        .foregroundStyle(AppColors.textSecondary)

                    HStack(alignment: .firstTextBaseline, spacing: AppSpacing.xxs) {
                        let prefix = comparison.isImprovement ? "+" : ""
                        let changeColor = comparison.isImprovement ? AppColors.success : AppColors.error

                        Text("\(prefix)\(comparison.changePercent)%")
                            .font(AppTypography.bodySemibold)
                            .foregroundStyle(changeColor)

                        Text(comparison.isImprovement ? "improvement" : "decrease")
                            .font(AppTypography.caption1)
                            .foregroundStyle(AppColors.textSecondary)
                    }
                }

                Spacer()

                VStack(alignment: .trailing, spacing: AppSpacing.xxs) {
                    Text("\(comparison.currentMonthPushUps)")
                        .font(AppTypography.displayMedium)
                        .foregroundStyle(AppColors.textPrimary)
                    Text("this month")
                        .font(AppTypography.caption2)
                        .foregroundStyle(AppColors.textSecondary)
                }
            }
        }
    }

    // MARK: - Summary Grid

    private var summaryGrid: some View {
        LazyVGrid(columns: Self.summaryColumns, spacing: AppSpacing.sm) {
            if isLoading {
                ForEach(0..<4, id: \.self) { _ in
                    MonthlySkeletonCard()
                }
            } else {
                StatCard(
                    title: "Total Push-Ups",
                    value: "\(totalPushUps)",
                    subtitle: "This month",
                    icon: .figureStrengthTraining,
                    tint: AppColors.primary
                )
                StatCard(
                    title: "Sessions",
                    value: "\(totalSessions)",
                    subtitle: "This month",
                    icon: .timer,
                    tint: AppColors.secondary
                )
                StatCard(
                    title: "Earned",
                    value: "\(earnedMinutes) min",
                    subtitle: "Time Credit",
                    icon: .boltFill,
                    tint: AppColors.success
                )
                StatCard(
                    title: "Weekly Avg",
                    value: weeks.isEmpty ? "0"
                        : "\(totalPushUps / max(1, weeks.count))",
                    subtitle: "Push-Ups",
                    icon: .chartBar,
                    tint: AppColors.info
                )
            }
        }
    }
}

// MARK: - SkeletonLineOverlay

private struct SkeletonLineOverlay: View {

    @State private var isAnimating = false

    var body: some View {
        GeometryReader { geo in
            Path { path in
                let w = geo.size.width
                let h = geo.size.height
                let points: [CGPoint] = [
                    CGPoint(x: w * 0.0, y: h * 0.7),
                    CGPoint(x: w * 0.25, y: h * 0.4),
                    CGPoint(x: w * 0.5, y: h * 0.55),
                    CGPoint(x: w * 0.75, y: h * 0.25),
                    CGPoint(x: w * 1.0, y: h * 0.45),
                ]
                path.move(to: points[0])
                for point in points.dropFirst() {
                    path.addLine(to: point)
                }
            }
            .stroke(AppColors.fill, style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
            .opacity(isAnimating ? 0.4 : 0.8)
            .animation(
                .easeInOut(duration: 1.0).repeatForever(autoreverses: true),
                value: isAnimating
            )
        }
        .onAppear { isAnimating = true }
    }
}

// MARK: - MonthlySkeletonCard

private struct MonthlySkeletonCard: View {

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

// MARK: - Previews

#if DEBUG
#Preview("MonthlyChartView") {
    let sampleWeeks: [MonthlyWeekData] = [
        MonthlyWeekData(id: 0, label: "W1", weekStart: Date(), totalPushUps: 87, totalSessions: 3, totalEarnedMinutes: 29),
        MonthlyWeekData(id: 1, label: "W2", weekStart: Date(), totalPushUps: 147, totalSessions: 5, totalEarnedMinutes: 49),
        MonthlyWeekData(id: 2, label: "W3", weekStart: Date(), totalPushUps: 112, totalSessions: 4, totalEarnedMinutes: 37),
        MonthlyWeekData(id: 3, label: "W4", weekStart: Date(), totalPushUps: 98, totalSessions: 3, totalEarnedMinutes: 33),
    ]

    ScrollView {
        VStack(spacing: AppSpacing.md) {
            MonthlyChartView(
                weeks: sampleWeeks,
                totalPushUps: 444,
                totalSessions: 15,
                earnedMinutes: 148,
                comparison: MonthComparison(
                    currentMonthPushUps: 444,
                    previousMonthPushUps: 312
                ),
                isLoading: false
            )
            MonthlyChartView(
                weeks: [],
                totalPushUps: 0,
                totalSessions: 0,
                earnedMinutes: 0,
                comparison: nil,
                isLoading: true
            )
        }
        .padding(AppSpacing.md)
    }
    .background(AppColors.backgroundPrimary)
}
#endif
