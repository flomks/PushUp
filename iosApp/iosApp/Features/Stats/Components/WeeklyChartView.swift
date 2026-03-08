import Charts
import SwiftUI

// MARK: - WeeklyChartView

/// Detailed weekly stats view for the Stats screen.
///
/// Shows a Swift Charts bar chart for the 7 days of the current week,
/// plus summary cards for totals and averages.
///
/// Usage:
/// ```swift
/// WeeklyChartView(
///     bars: viewModel.weeklyBars,
///     totalPushUps: viewModel.weeklyTotalPushUps,
///     averagePushUps: viewModel.weeklyAveragePushUps,
///     totalSessions: viewModel.weeklyTotalSessions,
///     earnedMinutes: viewModel.weeklyEarnedMinutes,
///     isLoading: viewModel.isLoading
/// )
/// ```
struct WeeklyChartView: View {

    let bars: [WeeklyBarData]
    let totalPushUps: Int
    let averagePushUps: Double
    let totalSessions: Int
    let earnedMinutes: Int
    let isLoading: Bool

    private static let summaryColumns = [
        GridItem(.flexible()),
        GridItem(.flexible()),
    ]

    var body: some View {
        VStack(spacing: AppSpacing.md) {
            chartCard
            summaryGrid
        }
    }

    // MARK: - Chart Card

    private var chartCard: some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {

            // Header
            HStack {
                Label("This Week", icon: .chartBar)
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
                chartSkeleton
            } else {
                barChart
            }
        }
        .padding(AppSpacing.md)
        .background(AppColors.backgroundSecondary)
        .clipShape(RoundedRectangle(cornerRadius: AppSpacing.cornerRadiusCard))
        .shadow(color: Color.black.opacity(0.06), radius: 8, x: 0, y: 2)
    }

    // MARK: - Bar Chart (Swift Charts)

    @ViewBuilder
    private var barChart: some View {
        Chart(bars) { bar in
            BarMark(
                x: .value("Day", bar.label),
                y: .value("Push-Ups", bar.pushUps)
            )
            .foregroundStyle(barColor(for: bar))
            .cornerRadius(6)
            .annotation(position: .top, alignment: .center) {
                if bar.pushUps > 0 {
                    Text("\(bar.pushUps)")
                        .font(AppTypography.caption2)
                        .foregroundStyle(
                            bar.isToday ? AppColors.primary : AppColors.textSecondary
                        )
                }
            }
        }
        .chartXAxis {
            AxisMarks(values: .automatic) { value in
                AxisValueLabel {
                    if let label = value.as(String.self) {
                        let isToday = bars.first(where: { $0.label == label })?.isToday ?? false
                        Text(label)
                            .font(AppTypography.caption2)
                            .fontWeight(isToday ? .bold : .regular)
                            .foregroundStyle(isToday ? AppColors.primary : AppColors.textSecondary)
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
        .animation(.spring(duration: 0.6, bounce: 0.15), value: bars.map(\.pushUps))
    }

    private func barColor(for bar: WeeklyBarData) -> AnyShapeStyle {
        if bar.isToday && bar.pushUps > 0 {
            return AnyShapeStyle(
                LinearGradient(
                    colors: [AppColors.primary, AppColors.secondary],
                    startPoint: .bottom,
                    endPoint: .top
                )
            )
        } else if bar.pushUps > 0 {
            return AnyShapeStyle(AppColors.primary.opacity(0.45))
        } else {
            return AnyShapeStyle(AppColors.fill)
        }
    }

    // MARK: - Chart Skeleton

    @ViewBuilder
    private var chartSkeleton: some View {
        HStack(alignment: .bottom, spacing: AppSpacing.xs) {
            ForEach([0.6, 0.3, 0.8, 0.4, 0.7, 0.2, 0.5], id: \.self) { fraction in
                SkeletonWeeklyBar(heightFraction: fraction)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 180)
    }

    // MARK: - Summary Grid

    private var summaryGrid: some View {
        LazyVGrid(columns: Self.summaryColumns, spacing: AppSpacing.sm) {
            if isLoading {
                ForEach(0..<4, id: \.self) { _ in
                    SkeletonStatCard()
                }
            } else {
                StatCard(
                    title: "Total Push-Ups",
                    value: "\(totalPushUps)",
                    subtitle: "This week",
                    icon: .figureStrengthTraining,
                    tint: AppColors.primary
                )
                StatCard(
                    title: "Daily Average",
                    value: String(format: "%.0f", averagePushUps),
                    subtitle: "Active days",
                    icon: .chartBar,
                    tint: AppColors.info
                )
                StatCard(
                    title: "Sessions",
                    value: "\(totalSessions)",
                    subtitle: "This week",
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
            }
        }
    }
}

// MARK: - SkeletonWeeklyBar

private struct SkeletonWeeklyBar: View {

    let heightFraction: Double
    @State private var isAnimating = false

    var body: some View {
        VStack(spacing: AppSpacing.xxs) {
            Spacer()
            RoundedRectangle(cornerRadius: 6)
                .fill(AppColors.fill)
                .frame(height: 180 * heightFraction)
                .opacity(isAnimating ? 0.5 : 1.0)
                .animation(
                    .easeInOut(duration: 0.9).repeatForever(autoreverses: true),
                    value: isAnimating
                )
            RoundedRectangle(cornerRadius: 2)
                .fill(AppColors.fill)
                .frame(width: 24, height: 10)
        }
        .frame(maxWidth: .infinity)
        .onAppear { isAnimating = true }
    }
}

// MARK: - SkeletonStatCard (local reuse)

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

// MARK: - Previews

#if DEBUG
#Preview("WeeklyChartView") {
    let sampleBars: [WeeklyBarData] = {
        let labels = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]
        let pushUps = [35, 0, 52, 18, 42, 0, 0]
        let sessions = [1, 0, 2, 1, 2, 0, 0]
        let earned = [12, 0, 17, 6, 14, 0, 0]
        return labels.enumerated().map { idx, label in
            WeeklyBarData(
                id: idx,
                label: label,
                date: Date(),
                pushUps: pushUps[idx],
                sessions: sessions[idx],
                earnedMinutes: earned[idx],
                isToday: idx == 4
            )
        }
    }()

    ScrollView {
        VStack(spacing: AppSpacing.md) {
            WeeklyChartView(
                bars: sampleBars,
                totalPushUps: 147,
                averagePushUps: 29.4,
                totalSessions: 6,
                earnedMinutes: 49,
                isLoading: false
            )
            WeeklyChartView(
                bars: [],
                totalPushUps: 0,
                averagePushUps: 0,
                totalSessions: 0,
                earnedMinutes: 0,
                isLoading: true
            )
        }
        .padding(AppSpacing.md)
    }
    .background(AppColors.backgroundPrimary)
}
#endif
