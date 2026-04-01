import SwiftUI

// MARK: - DashboardWidgetChrome

/// Visual style for dashboard widgets, aligned with the dark iOS-style mock
/// (`bg-white/5`, `border-white/10`, pure black page background).
enum DashboardWidgetChrome {

    /// Page background behind widgets (#000000).
    static let pageBackground = Color.black

    /// Primary labels and values on widget surfaces.
    static let labelPrimary = Color.white

    /// Secondary copy (≈ white at 40% — matches reference `text-white/40`).
    static let labelSecondary = Color.white.opacity(0.4)

    /// Muted axis / day letters (≈ white at 30%).
    static let labelMuted = Color.white.opacity(0.3)

    /// Positive trend / success accent (iOS green ~#34C759).
    static let accentPositive = Color(red: 0.204, green: 0.78, blue: 0.349)

    /// Bar fill for weekly chart (≈ white at 80%).
    static let barFill = Color.white.opacity(0.8)

    /// Inactive / empty bar track.
    static let barTrack = Color.white.opacity(0.12)

    static let cornerRadius: CGFloat = AppSpacing.cornerRadiusLarge
    static let padding: CGFloat = 20
}

extension View {

    /// Rounded surface: translucent fill + hairline border (no drop shadow).
    func dashboardWidgetChrome(cornerRadius: CGFloat = DashboardWidgetChrome.cornerRadius) -> some View {
        self
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(Color.white.opacity(0.05))
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.1), lineWidth: 1)
            )
    }
}
