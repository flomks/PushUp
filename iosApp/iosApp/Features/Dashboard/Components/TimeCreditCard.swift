import SwiftUI

// MARK: - CreditLevel

/// Semantic classification of the user's remaining credit balance.
/// Used to drive the status badge color and label.
private enum CreditLevel {
    case full
    case medium
    case low
    case empty

    init(fraction: CGFloat) {
        switch fraction {
        case 0.6...: self = .full
        case 0.3...: self = .medium
        case 0.01...: self = .low
        default: self = .empty
        }
    }

    var label: String {
        switch self {
        case .full:   return "Well stocked"
        case .medium: return "Medium"
        case .low:    return "Low"
        case .empty:  return "Empty"
        }
    }

    var color: Color {
        switch self {
        case .full:   return AppColors.success
        case .medium: return AppColors.warning
        case .low:    return AppColors.error
        case .empty:  return AppColors.textSecondary
        }
    }
}

// MARK: - DashboardTimeCreditCard

/// Hero card for the Dashboard that shows the user's current time-credit
/// balance with a circular progress ring and a large monospaced timer.
///
/// Extends the design-system `TimeCreditCard` concept with a richer header
/// (status badge, subtitle) and spring-animated ring fill.
///
/// Usage:
/// ```swift
/// DashboardTimeCreditCard(
///     availableSeconds: viewModel.availableSeconds,
///     totalEarnedSeconds: viewModel.totalEarnedSeconds,
///     isLoading: viewModel.isLoading
/// )
/// ```
struct DashboardTimeCreditCard: View {

    let availableSeconds: Int
    let dailyEarnedSeconds: Int
    let totalEarnedSeconds: Int
    let isLoading: Bool
    var onTap: (() -> Void)? = nil

    // Ring geometry
    private let ringSize: CGFloat = 180
    private let ringLineWidth: CGFloat = 14

    var body: some View {
        VStack(spacing: AppSpacing.md) {
            headerRow
            progressRing
                .padding(.vertical, AppSpacing.xs)
            footerRow
        }
        .padding(DashboardWidgetChrome.padding)
        .frame(maxWidth: .infinity)
        .dashboardWidgetChrome()
        .contentShape(Rectangle())
        .onTapGesture { onTap?() }
    }

    // MARK: - Header

    private var headerRow: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Available Credit")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(DashboardWidgetChrome.labelSecondary)

                creditStatusBadge
            }

            Spacer()

            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.white.opacity(0.05))
                    .frame(width: 44, height: 44)

                Image(systemName: AppIcon.clock.rawValue)
                    .font(.system(size: 20, weight: .regular))
                    .foregroundStyle(Color.white.opacity(0.6))
            }
        }
    }

    // MARK: - Progress Ring

    private var progressRing: some View {
        ZStack {
            // Track ring
            Circle()
                .stroke(Color.white.opacity(0.1), lineWidth: ringLineWidth)
                .frame(width: ringSize, height: ringSize)

            // Progress arc
            Circle()
                .trim(from: 0, to: progressFraction)
                .stroke(
                    Color.white.opacity(0.85),
                    style: StrokeStyle(
                        lineWidth: ringLineWidth,
                        lineCap: .round
                    )
                )
                .frame(width: ringSize, height: ringSize)
                .rotationEffect(.degrees(-90))
                .animation(.spring(duration: 0.8, bounce: 0.2), value: progressFraction)

            // Center content
            if isLoading {
                ProgressView()
                    .progressViewStyle(.circular)
                    .tint(.white)
                    .scaleEffect(1.4)
            } else {
                VStack(spacing: AppSpacing.xxs) {
                    Text(formattedTime)
                        .font(AppTypography.monoDisplay)
                        .foregroundStyle(DashboardWidgetChrome.labelPrimary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                        .contentTransition(.numericText())
                        .animation(.easeInOut(duration: 0.4), value: availableSeconds)

                    Text("available")
                        .font(AppTypography.caption1)
                        .foregroundStyle(DashboardWidgetChrome.labelSecondary)
                }
            }
        }
    }

    // MARK: - Footer

    @ViewBuilder
    private var footerRow: some View {
        if dailyEarnedSeconds > 0 {
            HStack(spacing: AppSpacing.xs) {
                Image(systemName: AppIcon.checkmarkCircleFill.rawValue)
                    .foregroundStyle(AppColors.success)
                    .font(.system(size: AppSpacing.iconSizeSmall))

                Text("Today's budget: \(formattedDailyBudget)")
                    .font(AppTypography.caption1)
                    .foregroundStyle(DashboardWidgetChrome.labelSecondary)

                Spacer()

                if onTap != nil {
                    Text("Details")
                        .font(AppTypography.captionSemibold)
                        .foregroundStyle(Color.white.opacity(0.85))

                    Image(systemName: AppIcon.chevronRight.rawValue)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Color.white.opacity(0.85))
                } else {
                    Text(String(format: "%.0f%%", progressFraction * 100) + " remaining")
                        .font(AppTypography.caption1)
                        .foregroundStyle(DashboardWidgetChrome.labelSecondary)
                }
            }
        } else {
            HStack(spacing: AppSpacing.xs) {
                Image(systemName: AppIcon.figureStrengthTraining.rawValue)
                    .foregroundStyle(DashboardWidgetChrome.labelMuted)
                    .font(.system(size: AppSpacing.iconSizeSmall))

                Text("Complete a workout to earn time credit")
                    .font(AppTypography.caption1)
                    .foregroundStyle(DashboardWidgetChrome.labelMuted)

                Spacer()

                if onTap != nil {
                    Image(systemName: AppIcon.chevronRight.rawValue)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(DashboardWidgetChrome.labelMuted)
                }
            }
        }
    }

    // MARK: - Status Badge

    private var creditStatusBadge: some View {
        let level = CreditLevel(fraction: progressFraction)
        return HStack(spacing: AppSpacing.xxs) {
            Circle()
                .fill(level.color)
                .frame(width: 8, height: 8)
            Text(level.label)
                .font(AppTypography.captionSemibold)
                .foregroundStyle(level.color)
        }
        .padding(.horizontal, AppSpacing.xs)
        .padding(.vertical, AppSpacing.xxs + 2)
        .background(level.color.opacity(0.12), in: Capsule())
    }

    // MARK: - Computed Properties

    private var progressFraction: CGFloat {
        guard dailyEarnedSeconds > 0 else { return 0 }
        return min(1.0, CGFloat(max(0, availableSeconds)) / CGFloat(dailyEarnedSeconds))
    }

    private var formattedTime: String {
        let clamped = max(0, availableSeconds)
        let h = clamped / 3600
        let m = (clamped % 3600) / 60
        let s = clamped % 60
        return String(format: "%02d:%02d:%02d", h, m, s)
    }

    /// Formats the daily budget as "X min" or "X min YYs" (seconds only when non-zero).
    private var formattedDailyBudget: String {
        let clamped = max(0, dailyEarnedSeconds)
        let totalMinutes = clamped / 60
        let remainingSeconds = clamped % 60

        if totalMinutes >= 60 {
            let h = totalMinutes / 60
            let m = totalMinutes % 60
            if remainingSeconds > 0 {
                return m > 0 ? "\(h)h \(m)m \(remainingSeconds)s" : "\(h)h \(remainingSeconds)s"
            }
            return m > 0 ? "\(h)h \(m)m" : "\(h)h"
        }

        if remainingSeconds > 0 {
            return "\(totalMinutes) min \(String(format: "%02d", remainingSeconds))s"
        }
        return "\(totalMinutes) min"
    }
}

// MARK: - Preview

#if DEBUG
#Preview("DashboardTimeCreditCard") {
    ScrollView {
        VStack(spacing: AppSpacing.md) {
            DashboardTimeCreditCard(
                availableSeconds: 5400,
                dailyEarnedSeconds: 9000,
                totalEarnedSeconds: 36000,
                isLoading: false
            )

            DashboardTimeCreditCard(
                availableSeconds: 900,
                dailyEarnedSeconds: 9000,
                totalEarnedSeconds: 36000,
                isLoading: false
            )

            DashboardTimeCreditCard(
                availableSeconds: 0,
                dailyEarnedSeconds: 0,
                totalEarnedSeconds: 0,
                isLoading: false
            )

            DashboardTimeCreditCard(
                availableSeconds: 0,
                dailyEarnedSeconds: 0,
                totalEarnedSeconds: 0,
                isLoading: true
            )
        }
        .padding(AppSpacing.md)
    }
    .background(DashboardWidgetChrome.pageBackground)
}
#endif
