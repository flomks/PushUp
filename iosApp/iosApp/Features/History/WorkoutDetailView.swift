import Charts
import SwiftUI

// MARK: - WorkoutDetailView

/// Detail screen for a single completed workout session.
///
/// **Layout**
/// ```
/// +-----------------------------------+
/// |  [Back]  Mon, Mar 8 · 09:42  [X] |  <- navigation bar
/// |                                   |
/// |  [Hero metrics card]              |  <- push-ups, duration, earned, quality
/// |                                   |
/// |  [Form Score Chart]               |  <- line chart of form score over time
/// |                                   |
/// |  [Push-Up Records]                |  <- list of individual reps
/// |    Rep 1  |  0:05  |  ★★★★☆     |
/// |    Rep 2  |  0:12  |  ★★★★★     |
/// |    ...                            |
/// +-----------------------------------+
/// ```
///
/// **Acceptance criteria covered (Task 3.9)**
/// - All PushUpRecords displayed in a scrollable list
/// - Form-score-over-time line chart using Swift Charts
/// - Hero metrics: push-ups, duration, earned time, quality stars
struct WorkoutDetailView: View {

    let session: WorkoutSession

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                AppColors.backgroundPrimary
                    .ignoresSafeArea()

                ScrollView {
                    LazyVStack(spacing: AppSpacing.md) {
                        heroCard
                        formScoreChart
                        recordsList
                    }
                    .padding(.horizontal, AppSpacing.screenHorizontal)
                    .padding(.top, AppSpacing.sm)
                    .padding(.bottom, AppSpacing.screenVerticalBottom)
                }
            }
            .navigationTitle(session.shortDateString)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: AppSpacing.iconSizeMedium))
                            .foregroundStyle(AppColors.textSecondary)
                            .symbolRenderingMode(.hierarchical)
                    }
                    .accessibilityLabel("Close")
                }
            }
        }
    }

    // MARK: - Hero Card

    private var heroCard: some View {
        Card {
            VStack(spacing: AppSpacing.md) {

                // Push-up count hero
                VStack(spacing: AppSpacing.xxs) {
                    Text("\(session.pushUpCount)")
                        .font(AppTypography.displayLarge)
                        .foregroundStyle(AppColors.textPrimary)

                    Text("Push-Ups")
                        .font(AppTypography.subheadline)
                        .foregroundStyle(AppColors.textSecondary)
                }

                Divider()

                // Metrics row
                HStack(spacing: 0) {
                    metricCell(
                        icon: .clock,
                        value: session.durationString,
                        label: "Duration",
                        tint: AppColors.info
                    )

                    metricDivider

                    metricCell(
                        icon: .boltFill,
                        value: "+\(session.earnedMinutes) min",
                        label: "Earned",
                        tint: AppColors.success
                    )

                    metricDivider

                    qualityMetricCell
                }
            }
        }
    }

    // MARK: - Metric Cells

    @ViewBuilder
    private func metricCell(
        icon: AppIcon,
        value: String,
        label: String,
        tint: Color
    ) -> some View {
        VStack(spacing: AppSpacing.xxs) {
            Image(systemName: icon.rawValue)
                .font(.system(size: AppSpacing.iconSizeStandard, weight: .semibold))
                .foregroundStyle(tint)

            Text(value)
                .font(AppTypography.bodySemibold)
                .foregroundStyle(AppColors.textPrimary)

            Text(label)
                .font(AppTypography.caption1)
                .foregroundStyle(AppColors.textSecondary)
        }
        .frame(maxWidth: .infinity)
    }

    private var qualityMetricCell: some View {
        VStack(spacing: AppSpacing.xxs) {
            starRating(count: session.starCount)

            Text(String(format: "%.0f%%", session.averageQuality * 100))
                .font(AppTypography.bodySemibold)
                .foregroundStyle(AppColors.formScoreColor(session.averageQuality))

            Text("Quality")
                .font(AppTypography.caption1)
                .foregroundStyle(AppColors.textSecondary)
        }
        .frame(maxWidth: .infinity)
    }

    private var metricDivider: some View {
        Rectangle()
            .fill(AppColors.separator)
            .frame(width: 1, height: 48)
    }

    @ViewBuilder
    private func starRating(count: Int) -> some View {
        HStack(spacing: 2) {
            ForEach(0..<5, id: \.self) { index in
                Image(systemName: index < count ? "star.fill" : "star")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(
                        index < count
                            ? AppColors.secondaryVariant
                            : AppColors.textTertiary
                    )
            }
        }
        .accessibilityLabel("\(count) out of 5 stars")
    }

    // MARK: - Form Score Chart

    @ViewBuilder
    private var formScoreChart: some View {
        if !session.records.isEmpty {
            VStack(alignment: .leading, spacing: AppSpacing.sm) {

                Label("Form Score Over Time", icon: .chartBar)
                    .font(AppTypography.headline)
                    .foregroundStyle(AppColors.textPrimary)

                Chart(session.records) { record in
                    // Area fill under the line
                    AreaMark(
                        x: .value("Time", record.timeOffset),
                        y: .value("Form Score", record.formScore)
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
                        x: .value("Time", record.timeOffset),
                        y: .value("Form Score", record.formScore)
                    )
                    .foregroundStyle(AppColors.primary)
                    .lineStyle(StrokeStyle(lineWidth: 2))
                    .interpolationMethod(.catmullRom)

                    // Point marks for individual reps
                    PointMark(
                        x: .value("Time", record.timeOffset),
                        y: .value("Form Score", record.formScore)
                    )
                    .foregroundStyle(AppColors.formScoreColor(record.formScore))
                    .symbolSize(30)
                }
                .chartXAxis {
                    AxisMarks(values: .automatic(desiredCount: 5)) { value in
                        AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [4]))
                            .foregroundStyle(AppColors.separator.opacity(0.5))
                        AxisValueLabel {
                            if let seconds = value.as(Double.self) {
                                Text(formatTimeOffset(seconds))
                                    .font(AppTypography.caption2)
                                    .foregroundStyle(AppColors.textSecondary)
                            }
                        }
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .leading, values: [0.0, 0.25, 0.5, 0.75, 1.0]) { value in
                        AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [4]))
                            .foregroundStyle(AppColors.separator.opacity(0.5))
                        AxisValueLabel {
                            if let score = value.as(Double.self) {
                                Text("\(Int(score * 100))%")
                                    .font(AppTypography.caption2)
                                    .foregroundStyle(AppColors.textSecondary)
                            }
                        }
                    }
                }
                .chartYScale(domain: 0...1)
                .chartPlotStyle { plotArea in
                    plotArea.background(AppColors.backgroundPrimary.opacity(0.3))
                }
                .frame(height: 180)
                .animation(.spring(duration: 0.6, bounce: 0.1), value: session.records.count)

                // Legend
                HStack(spacing: AppSpacing.md) {
                    legendItem(color: AppColors.success, label: "Good (75%+)")
                    legendItem(color: AppColors.warning, label: "OK (50-74%)")
                    legendItem(color: AppColors.error, label: "Poor (<50%)")
                }
                .padding(.top, AppSpacing.xxs)
            }
            .padding(AppSpacing.md)
            .background(AppColors.backgroundSecondary)
            .clipShape(RoundedRectangle(cornerRadius: AppSpacing.cornerRadiusCard))
            .shadow(color: Color.black.opacity(0.06), radius: 8, x: 0, y: 2)
        }
    }

    @ViewBuilder
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

    private func formatTimeOffset(_ seconds: Double) -> String {
        let m = Int(seconds) / 60
        let s = Int(seconds) % 60
        return String(format: "%d:%02d", m, s)
    }

    // MARK: - Records List

    @ViewBuilder
    private var recordsList: some View {
        if !session.records.isEmpty {
            VStack(alignment: .leading, spacing: AppSpacing.sm) {

                // Header
                HStack {
                    Label("Push-Up Records", icon: .figureStrengthTraining)
                        .font(AppTypography.headline)
                        .foregroundStyle(AppColors.textPrimary)

                    Spacer()

                    Text("\(session.records.count) reps")
                        .font(AppTypography.captionSemibold)
                        .foregroundStyle(AppColors.primary)
                }

                // Column headers
                recordsColumnHeader

                Divider()

                // Records
                LazyVStack(spacing: 0) {
                    ForEach(session.records) { record in
                        recordRow(record)

                        if record.id != session.records.last?.id {
                            Divider()
                                .padding(.leading, AppSpacing.md)
                        }
                    }
                }
            }
            .padding(AppSpacing.md)
            .background(AppColors.backgroundSecondary)
            .clipShape(RoundedRectangle(cornerRadius: AppSpacing.cornerRadiusCard))
            .shadow(color: Color.black.opacity(0.06), radius: 8, x: 0, y: 2)
        }
    }

    private var recordsColumnHeader: some View {
        HStack {
            Text("Rep")
                .font(AppTypography.caption1)
                .foregroundStyle(AppColors.textSecondary)
                .frame(width: 36, alignment: .leading)

            Spacer()

            Text("Time")
                .font(AppTypography.caption1)
                .foregroundStyle(AppColors.textSecondary)
                .frame(width: 48, alignment: .center)

            Spacer()

            Text("Quality")
                .font(AppTypography.caption1)
                .foregroundStyle(AppColors.textSecondary)
                .frame(width: 80, alignment: .trailing)
        }
        .padding(.horizontal, AppSpacing.xxs)
    }

    @ViewBuilder
    private func recordRow(_ record: PushUpRecord) -> some View {
        HStack {
            // Rep number
            Text("#\(record.repNumber)")
                .font(AppTypography.captionSemibold)
                .foregroundStyle(AppColors.textPrimary)
                .frame(width: 36, alignment: .leading)

            Spacer()

            // Time offset
            Text(formatTimeOffset(record.timeOffset))
                .font(AppTypography.caption1)
                .foregroundStyle(AppColors.textSecondary)
                .monospacedDigit()
                .frame(width: 48, alignment: .center)

            Spacer()

            // Quality bar + percentage
            HStack(spacing: AppSpacing.xs) {
                // Mini quality bar
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(AppColors.fill)
                            .frame(height: 6)

                        RoundedRectangle(cornerRadius: 2)
                            .fill(AppColors.formScoreColor(record.formScore))
                            .frame(width: geo.size.width * record.formScore, height: 6)
                    }
                }
                .frame(width: 40, height: 6)

                Text(String(format: "%.0f%%", record.formScore * 100))
                    .font(AppTypography.captionSemibold)
                    .foregroundStyle(AppColors.formScoreColor(record.formScore))
                    .frame(width: 34, alignment: .trailing)
            }
            .frame(width: 80, alignment: .trailing)
        }
        .padding(.vertical, AppSpacing.xs)
        .padding(.horizontal, AppSpacing.xxs)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "Rep \(record.repNumber), at \(formatTimeOffset(record.timeOffset)), quality \(Int(record.formScore * 100)) percent"
        )
    }
}

// MARK: - Previews

#if DEBUG
#Preview("WorkoutDetailView") {
    let records: [PushUpRecord] = (1...42).map { i in
        PushUpRecord(
            id: UUID(),
            repNumber: i,
            timeOffset: Double(i) * 11.5 + Double.random(in: -2...2),
            formScore: min(1.0, max(0.0, 0.84 + Double.random(in: -0.15...0.15)))
        )
    }

    let session = WorkoutSession(
        id: UUID(),
        startDate: Date().addingTimeInterval(-3600),
        pushUpCount: 42,
        durationSeconds: 487,
        earnedMinutes: 5,
        averageQuality: 0.84,
        records: records
    )

    WorkoutDetailView(session: session)
}

#Preview("WorkoutDetailView - Dark") {
    let records: [PushUpRecord] = (1...28).map { i in
        PushUpRecord(
            id: UUID(),
            repNumber: i,
            timeOffset: Double(i) * 9.0,
            formScore: min(1.0, max(0.0, 0.72 + Double.random(in: -0.2...0.2)))
        )
    }

    let session = WorkoutSession(
        id: UUID(),
        startDate: Date(),
        pushUpCount: 28,
        durationSeconds: 312,
        earnedMinutes: 3,
        averageQuality: 0.72,
        records: records
    )

    WorkoutDetailView(session: session)
        .preferredColorScheme(.dark)
}
#endif
