import SwiftUI

// MARK: - WorkoutListItem

/// A single row in the workout history list.
///
/// Displays date, time, push-up count, duration, earned time credit,
/// and a star quality rating for a completed `WorkoutSession`.
///
/// Usage:
/// ```swift
/// WorkoutListItem(session: session)
///     .onTapGesture { showDetail(session) }
/// ```
struct WorkoutListItem: View {

    let session: WorkoutSession

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
            // Time
            HStack(spacing: AppSpacing.xxs) {
                Image(systemName: AppIcon.clock.rawValue)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(AppColors.textSecondary)

                Text(session.timeString)
                    .font(AppTypography.captionSemibold)
                    .foregroundStyle(AppColors.textSecondary)
            }

            Spacer()

            // Star rating
            starRating(count: session.starCount)
        }
    }

    // MARK: - Bottom Row: duration + earned

    private var bottomRow: some View {
        HStack(spacing: AppSpacing.sm) {
            // Duration
            metricPill(
                icon: AppIcon.timer.rawValue,
                text: session.durationString,
                tint: AppColors.info
            )

            // Earned time
            metricPill(
                icon: AppIcon.boltFill.rawValue,
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

            Image(systemName: "chevron.right")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(AppColors.textTertiary)
        }
    }

    // MARK: - Helpers

    @ViewBuilder
    private func starRating(count: Int) -> some View {
        HStack(spacing: 2) {
            ForEach(0..<5, id: \.self) { index in
                Image(systemName: index < count ? "star.fill" : "star")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(
                        index < count
                            ? AppColors.secondaryVariant
                            : AppColors.textTertiary
                    )
            }
        }
        .accessibilityLabel("\(count) out of 5 stars")
    }

    @ViewBuilder
    private func metricPill(icon: String, text: String, tint: Color) -> some View {
        HStack(spacing: AppSpacing.xxs) {
            Image(systemName: icon)
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
}

// MARK: - Previews

#if DEBUG
#Preview("WorkoutListItem") {
    let sampleSession = WorkoutSession(
        id: UUID(),
        startDate: Date(),
        pushUpCount: 42,
        durationSeconds: 487,
        earnedMinutes: 5,
        averageQuality: 0.84,
        records: []
    )

    let lowQualitySession = WorkoutSession(
        id: UUID(),
        startDate: Date().addingTimeInterval(-3600),
        pushUpCount: 18,
        durationSeconds: 210,
        earnedMinutes: 2,
        averageQuality: 0.48,
        records: []
    )

    let highQualitySession = WorkoutSession(
        id: UUID(),
        startDate: Date().addingTimeInterval(-7200),
        pushUpCount: 61,
        durationSeconds: 712,
        earnedMinutes: 7,
        averageQuality: 0.94,
        records: []
    )

    ScrollView {
        VStack(spacing: AppSpacing.xs) {
            WorkoutListItem(session: sampleSession)
            WorkoutListItem(session: lowQualitySession)
            WorkoutListItem(session: highQualitySession)
        }
        .padding(AppSpacing.md)
    }
    .background(AppColors.backgroundPrimary)
}
#endif
