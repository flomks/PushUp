import Charts
import Shared
import SwiftUI

// MARK: - WorkoutDetailView

/// Detail screen for a single completed workout session.
///
/// Loads push-up records from the local SQLite database on appear via
/// `DataBridge.fetchRecordsForSession`. The hero metrics card is shown
/// immediately (data comes from the `WorkoutSession` struct); the chart
/// and records list appear once the records have loaded.
///
/// **Layout**
/// ```
/// +-----------------------------------+
/// |  [Back]  Mon, Mar 8 - 09:42  [X]  |  <- navigation bar
/// |                                    |
/// |  [Hero metrics card]               |  <- push-ups, duration, earned, quality
/// |                                    |
/// |  [Form Score Chart]                |  <- line chart of form score over time
/// |                                    |
/// |  [Push-Up Records]                 |  <- list of individual reps
/// |    Rep 1  |  0:05  |  85%         |
/// |    Rep 2  |  0:12  |  92%         |
/// |    ...                             |
/// +-----------------------------------+
/// ```
struct WorkoutDetailView: View {

    let session: PushUpSession

    @Environment(\.dismiss) private var dismiss

    /// Push-up records loaded from the local DB on appear.
    @State private var records: [DetailPushUpRecord] = []

    /// Whether records are currently being loaded.
    @State private var isLoadingRecords: Bool = true

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
            .navigationTitle("\(session.shortDateString) - \(session.timeString)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        dismiss()
                    } label: {
                        Image(icon: .xmarkCircleFill)
                            .font(.system(size: AppSpacing.iconSizeMedium))
                            .foregroundStyle(AppColors.textSecondary)
                            .symbolRenderingMode(.hierarchical)
                    }
                    .accessibilityLabel("Close")
                    .accessibilityIdentifier("detail_close_button")
                }
            }
            .task { loadRecords() }
        }
        .accessibilityIdentifier("workout_detail_screen")
    }

    // MARK: - Load Records

    private func loadRecords() {
        let sessionIdString = session.id.uuidString.lowercased()
        DataBridge.shared.fetchRecordsForSession(sessionId: sessionIdString) { kmpRecords in
            let startEpoch = session.startDate.timeIntervalSince1970
            let mapped: [DetailPushUpRecord] = kmpRecords.enumerated().map { index, record in
                let recordEpoch = Double(record.timestamp.epochSeconds)
                let offset = max(0, recordEpoch - startEpoch)
                return DetailPushUpRecord(
                    id: UUID(uuidString: record.id) ?? UUID(),
                    repNumber: index + 1,
                    timeOffset: offset,
                    formScore: Double(record.formScore),
                    depthScore: Double(record.depthScore)
                )
            }
            self.records = mapped
            self.isLoadingRecords = false
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
        .accessibilityIdentifier("detail_hero_card")
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
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label): \(value)")
    }

    private var qualityMetricCell: some View {
        VStack(spacing: AppSpacing.xxs) {
            StarRatingView(count: session.starCount, size: 12)

            Text(String(format: "%.0f%%", session.averageQuality * 100))
                .font(AppTypography.bodySemibold)
                .foregroundStyle(AppColors.formScoreColor(session.averageQuality))

            Text("Quality")
                .font(AppTypography.caption1)
                .foregroundStyle(AppColors.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Quality: \(session.starCount) out of 5 stars, \(Int(session.averageQuality * 100)) percent")
    }

    private var metricDivider: some View {
        Rectangle()
            .fill(AppColors.separator)
            .frame(width: 1, height: 48)
    }

    // MARK: - Form Score Chart

    @ViewBuilder
    private var formScoreChart: some View {
        if isLoadingRecords {
            // Loading indicator while records are being fetched
            VStack(spacing: AppSpacing.sm) {
                ProgressView()
                    .progressViewStyle(.circular)
                    .tint(AppColors.primary)
                Text("Loading records...")
                    .font(AppTypography.caption1)
                    .foregroundStyle(AppColors.textSecondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, AppSpacing.xl)
        } else if !records.isEmpty {
            VStack(alignment: .leading, spacing: AppSpacing.sm) {

                Label("Form Score Over Time", icon: .chartBar)
                    .font(AppTypography.headline)
                    .foregroundStyle(AppColors.textPrimary)

                Chart(records) { record in
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
                                Text(Self.formatTimeOffset(seconds))
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
                .animation(.spring(duration: 0.6, bounce: 0.1), value: records.count)

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
            .accessibilityIdentifier("detail_form_score_chart")
        } else {
            // No records available -- show a summary instead
            VStack(spacing: AppSpacing.sm) {
                Image(icon: .chartBar)
                    .font(.system(size: 32, weight: .semibold))
                    .foregroundStyle(AppColors.textTertiary)
                    .symbolRenderingMode(.hierarchical)

                Text("No detailed rep data available for this session.")
                    .font(AppTypography.subheadline)
                    .foregroundStyle(AppColors.textSecondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, AppSpacing.xl)
            .padding(.horizontal, AppSpacing.md)
            .background(AppColors.backgroundSecondary)
            .clipShape(RoundedRectangle(cornerRadius: AppSpacing.cornerRadiusCard))
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

    /// Formats a time offset in seconds as "M:SS".
    private static func formatTimeOffset(_ seconds: Double) -> String {
        let m = Int(seconds) / 60
        let s = Int(seconds) % 60
        return String(format: "%d:%02d", m, s)
    }

    // MARK: - Records List

    @ViewBuilder
    private var recordsList: some View {
        if !records.isEmpty {
            VStack(alignment: .leading, spacing: AppSpacing.sm) {

                // Header
                HStack {
                    Label("Push-Up Records", icon: .figureStrengthTraining)
                        .font(AppTypography.headline)
                        .foregroundStyle(AppColors.textPrimary)

                    Spacer()

                    Text("\(records.count) reps")
                        .font(AppTypography.captionSemibold)
                        .foregroundStyle(AppColors.primary)
                }

                // Column headers
                recordsColumnHeader

                Divider()

                // Records
                LazyVStack(spacing: 0) {
                    ForEach(records) { record in
                        recordRow(record)

                        if record.id != records.last?.id {
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
            .accessibilityIdentifier("detail_records_list")
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
    private func recordRow(_ record: DetailPushUpRecord) -> some View {
        HStack {
            // Rep number
            Text("#\(record.repNumber)")
                .font(AppTypography.captionSemibold)
                .foregroundStyle(AppColors.textPrimary)
                .frame(width: 36, alignment: .leading)

            Spacer()

            // Time offset
            Text(Self.formatTimeOffset(record.timeOffset))
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
            "Rep \(record.repNumber), at \(Self.formatTimeOffset(record.timeOffset)), quality \(Int(record.formScore * 100)) percent"
        )
    }
}

// MARK: - DetailPushUpRecord

/// View-layer model for a single push-up record in the detail view.
/// Separate from the HistoryViewModel's `PushUpRecord` to avoid coupling.
struct DetailPushUpRecord: Identifiable {
    let id: UUID
    let repNumber: Int
    let timeOffset: TimeInterval
    let formScore: Double
    let depthScore: Double
}

// MARK: - Previews

#if DEBUG
#Preview("WorkoutDetailView") {
    let session = PushUpSession(
        id: UUID(),
        startDate: Date().addingTimeInterval(-3600),
        pushUpCount: 42,
        durationSeconds: 487,
        earnedMinutes: 5,
        averageQuality: 0.84,
        records: []
    )

    WorkoutDetailView(session: session)
}

#Preview("WorkoutDetailView - Dark") {
    let session = PushUpSession(
        id: UUID(),
        startDate: Date(),
        pushUpCount: 28,
        durationSeconds: 312,
        earnedMinutes: 3,
        averageQuality: 0.72,
        records: []
    )

    WorkoutDetailView(session: session)
        .preferredColorScheme(.dark)
}
#endif
