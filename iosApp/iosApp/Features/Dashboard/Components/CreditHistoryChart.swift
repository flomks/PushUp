import Charts
import SwiftUI

// MARK: - CreditHistoryChartEntry

/// A single data point for the credit history chart.
struct CreditHistoryChartEntry: Identifiable {
    let id: String       // ISO date string
    let label: String    // Short day label ("Mon", "Tue", ...)
    let date: Date
    let earnedMinutes: Double
    let spentMinutes: Double
}

// MARK: - CreditHistoryChart

/// Line chart showing daily earned vs spent credit over the past 7 days.
///
/// - Blue line: daily budget (how much time was available)
/// - Orange line: screen time used
///
/// Displayed inside the TimeCreditDetailView sheet.
struct CreditHistoryChart: View {

    let entries: [CreditHistoryChartEntry]
    let isLoading: Bool

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: AppSpacing.sm) {
                headerRow
                Divider()

                if isLoading {
                    chartSkeleton
                } else if entries.isEmpty {
                    emptyState
                } else {
                    chartContent
                    legendRow
                }
            }
        }
    }

    // MARK: - Header

    private var headerRow: some View {
        HStack {
            Label("Weekly Overview", icon: .chartLineUptrendXYAxis)
                .font(AppTypography.headline)
                .foregroundStyle(AppColors.textPrimary)

            Spacer()

            if !isLoading && !entries.isEmpty {
                let totalSpent = entries.reduce(0.0) { $0 + $1.spentMinutes }
                Text(String(format: "%.0f min used", totalSpent))
                    .font(AppTypography.captionSemibold)
                    .foregroundStyle(AppColors.warning)
            }
        }
    }

    // MARK: - Chart

    @ViewBuilder
    private var chartContent: some View {
        Chart {
            ForEach(entries) { entry in
                // Earned line (daily budget)
                LineMark(
                    x: .value("Day", entry.label),
                    y: .value("Minutes", entry.earnedMinutes),
                    series: .value("Type", "Budget")
                )
                .foregroundStyle(AppColors.primary)
                .lineStyle(StrokeStyle(lineWidth: 2.5))
                .symbol {
                    Circle()
                        .fill(AppColors.primary)
                        .frame(width: 7, height: 7)
                }

                // Area fill under earned line
                AreaMark(
                    x: .value("Day", entry.label),
                    y: .value("Minutes", entry.earnedMinutes),
                    series: .value("Type", "Budget")
                )
                .foregroundStyle(
                    LinearGradient(
                        colors: [AppColors.primary.opacity(0.15), AppColors.primary.opacity(0.02)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )

                // Spent line (screen time used)
                LineMark(
                    x: .value("Day", entry.label),
                    y: .value("Minutes", entry.spentMinutes),
                    series: .value("Type", "Used")
                )
                .foregroundStyle(AppColors.warning)
                .lineStyle(StrokeStyle(lineWidth: 2.5))
                .symbol {
                    Circle()
                        .fill(AppColors.warning)
                        .frame(width: 7, height: 7)
                }
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
        .chartYScale(domain: 0 ... maxYValue)
        .frame(height: 180)
        .animation(.spring(duration: 0.6, bounce: 0.15), value: entries.map(\.earnedMinutes))
    }

    private var maxYValue: Double {
        let maxEarned = entries.map(\.earnedMinutes).max() ?? 0
        let maxSpent = entries.map(\.spentMinutes).max() ?? 0
        let maxVal = max(maxEarned, maxSpent)
        // Add 20% headroom, minimum 10 minutes
        return max(10, maxVal * 1.2)
    }

    // MARK: - Legend

    private var legendRow: some View {
        HStack(spacing: AppSpacing.md) {
            legendItem(color: AppColors.primary, label: "Daily Budget")
            legendItem(color: AppColors.warning, label: "Screen Time Used")
        }
    }

    private func legendItem(color: Color, label: String) -> some View {
        HStack(spacing: AppSpacing.xxs) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
            Text(label)
                .font(AppTypography.caption2)
                .foregroundStyle(AppColors.textSecondary)
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: AppSpacing.sm) {
            Image(systemName: AppIcon.chartLineUptrendXYAxis.rawValue)
                .font(.system(size: 32))
                .foregroundStyle(AppColors.textTertiary)

            Text("No history yet")
                .font(AppTypography.subheadline)
                .foregroundStyle(AppColors.textSecondary)

            Text("Credit history will appear here after your first daily reset at 3:00 AM.")
                .font(AppTypography.caption1)
                .foregroundStyle(AppColors.textTertiary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 160)
    }

    // MARK: - Skeleton

    private var chartSkeleton: some View {
        VStack(spacing: AppSpacing.xs) {
            HStack(alignment: .bottom, spacing: AppSpacing.xs) {
                ForEach([0.4, 0.6, 0.3, 0.8, 0.5, 0.7, 0.4], id: \.self) { fraction in
                    RoundedRectangle(cornerRadius: 4)
                        .fill(AppColors.fill)
                        .frame(height: 140 * fraction)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 140)
        }
        .redacted(reason: .placeholder)
    }
}

// MARK: - Preview

#if DEBUG
#Preview("Credit History Chart") {
    let calendar = Calendar.current
    let today = Date()
    let entries: [CreditHistoryChartEntry] = (0..<7).reversed().map { daysAgo in
        let date = calendar.date(byAdding: .day, value: -daysAgo, to: today)!
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE"
        return CreditHistoryChartEntry(
            id: "\(daysAgo)",
            label: formatter.string(from: date),
            date: date,
            earnedMinutes: Double([45, 30, 60, 0, 50, 35, 40][6 - daysAgo]),
            spentMinutes: Double([30, 25, 55, 0, 40, 20, 15][6 - daysAgo])
        )
    }

    ScrollView {
        VStack(spacing: AppSpacing.md) {
            CreditHistoryChart(entries: entries, isLoading: false)
            CreditHistoryChart(entries: [], isLoading: false)
            CreditHistoryChart(entries: [], isLoading: true)
        }
        .padding(AppSpacing.md)
    }
    .background(AppColors.backgroundPrimary)
}
#endif
