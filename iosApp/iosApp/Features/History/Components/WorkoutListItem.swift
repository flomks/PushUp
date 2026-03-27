import SwiftUI

// MARK: - HistoryListItem

/// A single row in the unified workout history list.
///
/// Renders differently based on the activity type:
/// - Push-ups: shows push-up count, duration, earned time, quality stars
/// - Running: shows distance, duration, pace, earned time
///
/// Usage:
/// ```swift
/// HistoryListItem(item: historyItem)
///     .onTapGesture { showDetail(historyItem) }
/// ```
struct HistoryListItem: View {

    let item: HistoryItem

    var body: some View {
        switch item {
        case .pushUp(let session):
            PushUpListItem(session: session)
        case .jogging(let session):
            JoggingListItem(session: session)
        }
    }
}

// MARK: - PushUpListItem

/// A single row for a push-up workout in the history list.
private struct PushUpListItem: View {

    let session: PushUpSession

    var body: some View {
        HStack(spacing: AppSpacing.md) {
            // Left: quality color indicator bar
            qualityBar

            // Center: main content
            VStack(alignment: .leading, spacing: AppSpacing.xxs) {
                topRow
                bottomRow
            }

            Spacer(minLength: 0)

            // Right: push-up count + chevron
            rightColumn
        }
        .padding(.vertical, AppSpacing.sm)
        .padding(.horizontal, AppSpacing.md)
        .background(AppColors.backgroundSecondary)
        .clipShape(RoundedRectangle(cornerRadius: AppSpacing.cornerRadiusCard))
        .shadow(color: Color.black.opacity(0.05), radius: 6, x: 0, y: 2)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityDescription)
        .accessibilityHint("Double tap to view details")
    }

    // MARK: - Quality Bar

    private var qualityBar: some View {
        RoundedRectangle(cornerRadius: 3)
            .fill(AppColors.formScoreColor(session.averageQuality))
            .frame(width: 4, height: 52)
    }

    // MARK: - Top Row: time + stars

    private var topRow: some View {
        HStack(spacing: AppSpacing.xs) {
            HStack(spacing: AppSpacing.xxs) {
                Image(icon: .clock)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(AppColors.textSecondary)

                Text(session.timeString)
                    .font(AppTypography.captionSemibold)
                    .foregroundStyle(AppColors.textSecondary)
            }

            Spacer()

            StarRatingView(count: session.starCount, size: 10)
        }
    }

    // MARK: - Bottom Row: duration + earned

    private var bottomRow: some View {
        HStack(spacing: AppSpacing.sm) {
            metricPill(
                icon: .timer,
                text: session.durationString,
                tint: AppColors.info
            )

            metricPill(
                icon: .boltFill,
                text: "+\(session.earnedMinutes) min",
                tint: AppColors.success
            )
        }
    }

    // MARK: - Right Column: push-up count

    private var rightColumn: some View {
        VStack(alignment: .trailing, spacing: AppSpacing.xxs) {
            Text("\(session.pushUpCount)")
                .font(AppTypography.displayMedium)
                .foregroundStyle(AppColors.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            Text("Push-Ups")
                .font(AppTypography.caption2)
                .foregroundStyle(AppColors.textSecondary)

            Image(icon: .chevronRight)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(AppColors.textTertiary)
        }
    }

    // MARK: - Helpers

    @ViewBuilder
    private func metricPill(icon: AppIcon, text: String, tint: Color) -> some View {
        HStack(spacing: AppSpacing.xxs) {
            Image(systemName: icon.rawValue)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(tint)

            Text(text)
                .font(AppTypography.caption1)
                .foregroundStyle(AppColors.textSecondary)
        }
        .padding(.horizontal, AppSpacing.xs)
        .padding(.vertical, 3)
        .background(tint.opacity(0.10), in: Capsule())
    }

    private var accessibilityDescription: String {
        "\(session.pushUpCount) push-ups at \(session.timeString), " +
        "duration \(session.durationString), " +
        "earned \(session.earnedMinutes) minutes, " +
        "\(session.starCount) out of 5 stars quality"
    }
}

// MARK: - JoggingListItem

/// A single row for a jogging session in the history list.
private struct JoggingListItem: View {

    let session: JoggingSessionItem

    var body: some View {
        HStack(spacing: AppSpacing.md) {
            // Left: blue running indicator bar
            runningBar

            // Center: main content
            VStack(alignment: .leading, spacing: AppSpacing.xxs) {
                topRow
                bottomRow
            }

            Spacer(minLength: 0)

            // Right: distance + chevron
            rightColumn
        }
        .padding(.vertical, AppSpacing.sm)
        .padding(.horizontal, AppSpacing.md)
        .background(AppColors.backgroundSecondary)
        .clipShape(RoundedRectangle(cornerRadius: AppSpacing.cornerRadiusCard))
        .shadow(color: Color.black.opacity(0.05), radius: 6, x: 0, y: 2)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityDescription)
        .accessibilityHint("Double tap to view route details")
    }

    // MARK: - Running Bar

    private var runningBar: some View {
        RoundedRectangle(cornerRadius: 3)
            .fill(AppColors.info)
            .frame(width: 4, height: 52)
    }

    // MARK: - Top Row: time + running icon

    private var topRow: some View {
        HStack(spacing: AppSpacing.xs) {
            HStack(spacing: AppSpacing.xxs) {
                Image(icon: .clock)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(AppColors.textSecondary)

                Text(session.timeString)
                    .font(AppTypography.captionSemibold)
                    .foregroundStyle(AppColors.textSecondary)
            }

            Spacer()

            HStack(spacing: AppSpacing.xxs) {
                Image(icon: .figureRun)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(AppColors.info)

                Text("Running")
                    .font(AppTypography.captionSemibold)
                    .foregroundStyle(AppColors.info)
            }
        }
    }

    // MARK: - Bottom Row: duration + pace + earned

    private var bottomRow: some View {
        HStack(spacing: AppSpacing.sm) {
            metricPill(
                icon: .timer,
                text: session.durationString,
                tint: AppColors.info
            )

            metricPill(
                icon: .figureRun,
                text: "\(session.formattedPace) /km",
                tint: AppColors.primary
            )

            metricPill(
                icon: .boltFill,
                text: "+\(session.earnedMinutes) min",
                tint: AppColors.success
            )
        }
    }

    // MARK: - Right Column: distance

    private var rightColumn: some View {
        VStack(alignment: .trailing, spacing: AppSpacing.xxs) {
            Text(session.distanceString)
                .font(AppTypography.displayMedium)
                .foregroundStyle(AppColors.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.5)

            Text("Distance")
                .font(AppTypography.caption2)
                .foregroundStyle(AppColors.textSecondary)

            Image(icon: .chevronRight)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(AppColors.textTertiary)
        }
    }

    // MARK: - Helpers

    @ViewBuilder
    private func metricPill(icon: AppIcon, text: String, tint: Color) -> some View {
        HStack(spacing: AppSpacing.xxs) {
            Image(systemName: icon.rawValue)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(tint)

            Text(text)
                .font(AppTypography.caption1)
                .foregroundStyle(AppColors.textSecondary)
        }
        .padding(.horizontal, AppSpacing.xs)
        .padding(.vertical, 3)
        .background(tint.opacity(0.10), in: Capsule())
    }

    private var accessibilityDescription: String {
        "\(session.distanceString) run at \(session.timeString), " +
        "duration \(session.durationString), " +
        "pace \(session.formattedPace) per kilometer, " +
        "earned \(session.earnedMinutes) minutes"
    }
}

// MARK: - StarRatingView

/// Reusable star rating display used across History list items and detail views.
///
/// Shows 5 stars, with `count` filled and the rest empty.
///
/// Usage:
/// ```swift
/// StarRatingView(count: 4, size: 12)
/// ```
struct StarRatingView: View {

    /// Number of filled stars (0-5).
    let count: Int

    /// Point size for each star icon.
    let size: CGFloat

    var body: some View {
        HStack(spacing: 2) {
            ForEach(0..<5, id: \.self) { index in
                Image(systemName: index < count
                    ? AppIcon.starFill.rawValue
                    : AppIcon.star.rawValue
                )
                .font(.system(size: size, weight: .semibold))
                .foregroundStyle(
                    index < count
                        ? AppColors.secondaryVariant
                        : AppColors.textTertiary
                )
            }
        }
        .accessibilityLabel("\(count) out of 5 stars")
    }
}

// MARK: - Previews

#if DEBUG
#Preview("HistoryListItem - Push-Up") {
    let sampleSession = PushUpSession(
        id: UUID(),
        startDate: Date(),
        pushUpCount: 42,
        durationSeconds: 487,
        earnedMinutes: 5,
        averageQuality: 0.84,
        records: []
    )

    ScrollView {
        VStack(spacing: AppSpacing.xs) {
            HistoryListItem(item: .pushUp(sampleSession))
        }
        .padding(AppSpacing.md)
    }
    .background(AppColors.backgroundPrimary)
}

#Preview("HistoryListItem - Jogging") {
    let sampleSession = JoggingSessionItem(
        id: UUID(),
        kmpSessionId: UUID().uuidString,
        startDate: Date(),
        distanceMeters: 5230,
        durationSeconds: 1845,
        avgPaceSecondsPerKm: 352,
        caloriesBurned: 420,
        earnedMinutes: 8,
        activeDurationSeconds: 1700,
        pauseDurationSeconds: 145,
        activeDistanceMeters: 5100,
        pauseDistanceMeters: 130,
        pauseCount: 1
    )

    ScrollView {
        VStack(spacing: AppSpacing.xs) {
            HistoryListItem(item: .jogging(sampleSession))
        }
        .padding(AppSpacing.md)
    }
    .background(AppColors.backgroundPrimary)
}
#endif
