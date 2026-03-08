import SwiftUI

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

                // Section header
                HStack {
                    VStack(alignment: .leading, spacing: AppSpacing.xxs) {
                        Text("Zeitguthaben")
                            .font(AppTypography.title3)
                            .foregroundStyle(AppColors.textPrimary)

                        Text("Verfuegbare Bildschirmzeit")
                            .font(AppTypography.caption1)
                            .foregroundStyle(AppColors.textSecondary)
                    }

                    Spacer()

                    // Credit status badge
                    creditStatusBadge
                }

                // Progress ring + time display
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

                            Text("verfuegbar")
                                .font(AppTypography.caption1)
                                .foregroundStyle(AppColors.textSecondary)
                        }
                    }
                }
                .padding(.vertical, AppSpacing.xs)

                // Bottom row: total earned
                HStack(spacing: AppSpacing.xs) {
                    Image(systemName: AppIcon.checkmarkCircleFill.rawValue)
                        .foregroundStyle(AppColors.success)
                        .font(.system(size: AppSpacing.iconSizeSmall))

                    Text("Gesamt verdient: \(formattedTotalEarned)")
                        .font(AppTypography.caption1)
                        .foregroundStyle(AppColors.textSecondary)

                    Spacer()

                    if totalEarnedSeconds > 0 {
                        Text(String(format: "%.0f%%", progressFraction * 100) + " verbleibend")
                            .font(AppTypography.caption1)
                            .foregroundStyle(AppColors.textSecondary)
                    }
                }
            }
            .frame(maxWidth: .infinity)
        }
    }

    // MARK: - Private Views

    @ViewBuilder
    private var creditStatusBadge: some View {
        let (label, color) = creditStatus
        HStack(spacing: AppSpacing.xxs) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
            Text(label)
                .font(AppTypography.captionSemibold)
                .foregroundStyle(color)
        }
        .padding(.horizontal, AppSpacing.xs)
        .padding(.vertical, AppSpacing.xxs + 2)
        .background(color.opacity(0.12), in: Capsule())
    }

    // MARK: - Computed Properties

    private var progressFraction: CGFloat {
        guard totalEarnedSeconds > 0 else { return 0 }
        return min(1.0, CGFloat(availableSeconds) / CGFloat(totalEarnedSeconds))
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

    private var creditStatus: (String, Color) {
        let fraction = progressFraction
        switch fraction {
        case 0.6...: return ("Gut gefuellt", AppColors.success)
        case 0.3...: return ("Mittel", AppColors.warning)
        case 0.01...: return ("Niedrig", AppColors.error)
        default:     return ("Leer", AppColors.textSecondary)
        }
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
