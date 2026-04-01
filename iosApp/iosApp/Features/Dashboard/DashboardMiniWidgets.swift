import SwiftUI

// MARK: - DashboardMiniStatWidget

/// Single-metric dashboard tile using `DashboardWidgetChrome`.
struct DashboardMiniStatWidget: View {

    let title: String
    let systemImage: String
    let value: String
    var subtitle: String? = nil
    var footnote: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Image(systemName: systemImage)
                    .font(.system(size: 18, weight: .regular))
                    .foregroundStyle(DashboardWidgetChrome.labelSecondary)

                Text(title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(DashboardWidgetChrome.labelPrimary)

                Spacer(minLength: 0)
            }

            Text(value)
                .font(.system(size: 34, weight: .semibold))
                .foregroundStyle(DashboardWidgetChrome.labelPrimary)
                .lineLimit(2)
                .minimumScaleFactor(0.55)

            if let subtitle {
                Text(subtitle)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(DashboardWidgetChrome.labelSecondary)
            }

            if let footnote {
                Text(footnote)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(DashboardWidgetChrome.labelMuted)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(DashboardWidgetChrome.padding)
        .dashboardWidgetChrome()
    }
}

// MARK: - DashboardShortcutWidget

/// Tappable row that switches the main tab bar selection.
struct DashboardShortcutWidget: View {

    let title: String
    let systemImage: String
    let tab: Tab
    @Binding var selectedTab: Tab

    var body: some View {
        Button {
            DashboardHaptics.lightImpact()
            selectedTab = tab
        } label: {
            HStack(spacing: 12) {
                Image(systemName: systemImage)
                    .font(.system(size: 18, weight: .regular))
                    .foregroundStyle(DashboardWidgetChrome.labelSecondary)
                    .frame(width: 28, alignment: .center)

                Text(title)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(DashboardWidgetChrome.labelPrimary)

                Spacer(minLength: 0)

                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(DashboardWidgetChrome.labelMuted)
            }
            .padding(DashboardWidgetChrome.padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .dashboardWidgetChrome()
    }
}

// MARK: - Formatting (dashboard mini-widgets)

enum DashboardMetricFormatting {

    static func distanceLabel(meters: Int) -> String {
        let m = max(0, meters)
        if m >= 1000 {
            return String(format: "%.2f km", Double(m) / 1000.0)
        }
        return "\(m) m"
    }

    static func minutesFromSeconds(_ seconds: Int) -> String {
        let s = max(0, seconds)
        let m = s / 60
        if m >= 120 {
            let h = m / 60
            let rem = m % 60
            return rem > 0 ? "\(h)h \(rem)m" : "\(h)h"
        }
        return "\(m) min"
    }

    static func hoursMinutesFromSeconds(_ seconds: Int) -> String {
        let s = max(0, seconds)
        let h = s / 3600
        let m = (s % 3600) / 60
        if h > 0 {
            return m > 0 ? "\(h)h \(m)m" : "\(h)h"
        }
        return m > 0 ? "\(m) min" : "< 1 min"
    }

    static func percentString(_ fraction: Double) -> String {
        guard fraction > 0 else { return "—" }
        return String(format: "%.0f%%", min(100, fraction * 100))
    }
}
