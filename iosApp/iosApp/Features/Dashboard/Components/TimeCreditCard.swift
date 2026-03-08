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
    let totalEarnedSeconds: Int
    let isLoading: Bool

    // Ring geometry
    private let ringSize: CGFloat = 180
    private let ringLineWidth: CGFloat = 14

    var body: some View {
        Card(padding: AppSpacing.lg) {
            VStack(spacing: AppSpacing.md) {
                headerRow
                progressRing
                    .padding(.vertical, AppSpacing.xs)
                footerRow
            }
            .frame(maxWidth: .infinity)
        }
    }

    // MARK: - Header

    private var headerRow: some View {
        HStack {
            VStack(alignment: .leading, spacing: AppSpacing.xxs) {
                Text("Time Credit")
                    .font(AppTypography.title3)
                    .foregroundStyle(AppColors.textPrimary)

                Text("Available Screen Time")
                    .font(AppTypography.caption1)
                    .foregroundStyle(AppColors.textSecondary)
            }

            Spacer()

            creditStatusBadge
        }
    }

    // MARK: - Progress Ring

    private var progressRing: some View {
        ZStack {
            // Track ring
            Circle()
                .stroke(AppColors.fill, lineWidth: ringLineWidth)
                .frame(width: ringSize, height: ringSize)

            // Progress arc
            Circle()
                .trim(from: 0, to: progressFraction)
                .stroke(
                    LinearGradient(
                        colors: [AppColors.primary, AppColors.secondary],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
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
                    .tint(AppColors.primary)
                    .scaleEffect(1.4)
            } else {
                VStack(spacing: AppSpacing.xxs) {
                    Text(formattedTime)
                        .font(AppTypography.monoDisplay)
                        .foregroundStyle(AppColors.textPrimary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                        .contentTransition(.numericText())
                        .animation(.easeInOut(duration: 0.4), value: availableSeconds)

                    Text("available")
                        .font(AppTypography.caption1)
                        .foregroundStyle(AppColors.textSecondary)
                }
            }
        }
    }

    // MARK: - Footer

    private var footerRow: some View {
        HStack(spacing: AppSpacing.xs) {
            Image(systemName: AppIcon.checkmarkCircleFill.rawValue)
                .foregroundStyle(AppColors.success)
                .font(.system(size: AppSpacing.iconSizeSmall))

            Text("Total earned: \(formattedTotalEarned)")
                .font(AppTypography.caption1)
                .foregroundStyle(AppColors.textSecondary)

            Spacer()

            if totalEarnedSeconds > 0 {
                Text(String(format: "%.0f%%", progressFraction * 100) + " remaining")
                    .font(AppTypography.caption1)
                    .foregroundStyle(AppColors.textSecondary)
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
        guard totalEarnedSeconds > 0 else { return 0 }
        return min(1.0, CGFloat(max(0, availableSeconds)) / CGFloat(totalEarnedSeconds))
    }

    private var formattedTime: String {
        let clamped = max(0, availableSeconds)
        let h = clamped / 3600
        let m = (clamped % 3600) / 60
        let s = clamped % 60
        return String(format: "%02d:%02d:%02d", h, m, s)
    }

    private var formattedTotalEarned: String {
        let minutes = totalEarnedSeconds / 60
        if minutes >= 60 {
            let h = minutes / 60
            let m = minutes % 60
            return m > 0 ? "\(h)h \(m)m" : "\(h)h"
        }
        return "\(minutes) Min"
    }
}

// MARK: - Preview

#if DEBUG
#Preview("DashboardTimeCreditCard") {
    ScrollView {
        VStack(spacing: AppSpacing.md) {
            DashboardTimeCreditCard(
                availableSeconds: 5400,
                totalEarnedSeconds: 9000,
                isLoading: false
            )

            DashboardTimeCreditCard(
                availableSeconds: 900,
                totalEarnedSeconds: 9000,
                isLoading: false
            )

            DashboardTimeCreditCard(
                availableSeconds: 0,
                totalEarnedSeconds: 0,
                isLoading: false
            )

            DashboardTimeCreditCard(
                availableSeconds: 0,
                totalEarnedSeconds: 0,
                isLoading: true
            )
        }
        .padding(AppSpacing.md)
    }
    .background(AppColors.backgroundPrimary)
}
#endif
