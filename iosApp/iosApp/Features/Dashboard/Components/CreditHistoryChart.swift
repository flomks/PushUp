import Charts
import SwiftUI

// MARK: - CreditHistoryChartEntry

/// A single data point for the credit history chart.
struct CreditHistoryChartEntry: Identifiable {
    let id: String
    let label: String
    let date: Date
    let earnedMinutes: Double
    let spentMinutes: Double
}

// MARK: - CreditHistoryChart

/// Line chart showing daily earned vs spent credit over the past 7 days.
struct CreditHistoryChart: View {

    let entries: [CreditHistoryChartEntry]
    let isLoading: Bool

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: AppSpacing.sm) {
                // Header
                HStack {
                    Label("Weekly Overview", icon: .chartLineUptrendXYAxis)
                        .font(AppTypography.headline)
                        .foregroundStyle(AppColors.textPrimary)
                    Spacer()
                }

                Divider()

                if isLoading {
                    skeletonContent
                } else if entries.isEmpty {
                    emptyContent
                } else {
                    chartBody
                    legendContent
                }
            }
        }
    }

    // MARK: - Chart Body

    private var chartBody: some View {
        Chart {
            ForEach(entries) { entry in
                BarMark(
                    x: .value("Day", entry.label),
                    y: .value("Budget", entry.earnedMinutes)
                )
                .foregroundStyle(AppColors.primary.opacity(0.3))
                .cornerRadius(4)
            }
            ForEach(entries) { entry in
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
    }

    // MARK: - Legend

    private var legendContent: some View {
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

    // MARK: - Empty State

    private var emptyContent: some View {
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
    }

    // MARK: - Skeleton

    private var skeletonContent: some View {
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
    }
}
