import SwiftUI

// MARK: - WeeklyChart

/// Bar chart for the current week using the dark dashboard widget style.
struct WeeklyChart: View {

    let days: [DashboardWeekDay]
    let isLoading: Bool
    /// Week-over-week session change; `nil` hides the badge.
    let weekOverWeekPercent: Int?

    private let barMaxHeight: CGFloat = 80
    private let barMinHeight: CGFloat = 4

    /// Compact letters for Mon…Sun (index matches `WeekdayHelper` / `DashboardWeekDay.id`).
    private static let compactDayLetters = ["M", "T", "W", "T", "F", "S", "S"]

    var body: some View {
        let total = days.map(\.sessions).reduce(0, +)

        VStack(alignment: .leading, spacing: 16) {
            HStack {
                HStack(spacing: 10) {
                    Image(systemName: "chart.line.uptrend.xyaxis")
                        .font(.system(size: 18, weight: .regular))
                        .foregroundStyle(DashboardWidgetChrome.labelSecondary)

                    Text("This Week")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(DashboardWidgetChrome.labelPrimary)
                }

                Spacer()

                if !isLoading, let pct = weekOverWeekPercent {
                    Text(trendLabel(pct))
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(trendColor(pct))
                }
            }

            if isLoading {
                loadingSkeleton
            } else if days.isEmpty || total == 0 {
                emptyChartView
            } else {
                chartBars
            }
        }
        .padding(DashboardWidgetChrome.padding)
        .dashboardWidgetChrome()
    }

    // MARK: - Sub-views

    @ViewBuilder
    private var chartBars: some View {
        let maxValue = days.map(\.sessions).max() ?? 1

        HStack(alignment: .bottom, spacing: 8) {
            ForEach(days) { day in
                DayBar(
                    day: day,
                    maxSessions: maxValue,
                    barMaxHeight: barMaxHeight,
                    barMinHeight: barMinHeight,
                    letter: Self.compactDayLetters[min(day.id, Self.compactDayLetters.count - 1)]
                )
            }
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private var loadingSkeleton: some View {
        HStack(alignment: .bottom, spacing: 8) {
            ForEach(0..<7, id: \.self) { idx in
                SkeletonBar(
                    heightFraction: Self.skeletonHeights[idx],
                    barMaxHeight: barMaxHeight,
                    letter: Self.compactDayLetters[idx]
                )
            }
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private var emptyChartView: some View {
        HStack(alignment: .bottom, spacing: 8) {
            ForEach(days.isEmpty ? Self.defaultEmptyDays : days) { day in
                EmptyDayBar(
                    letter: Self.compactDayLetters[min(day.id, Self.compactDayLetters.count - 1)],
                    isToday: day.isToday
                )
            }
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Helpers

    private func trendLabel(_ pct: Int) -> String {
        if pct > 0 { return "+\(pct)%" }
        if pct < 0 { return "\(pct)%" }
        return "0%"
    }

    private func trendColor(_ pct: Int) -> Color {
        if pct > 0 { return DashboardWidgetChrome.accentPositive }
        if pct < 0 { return Color(red: 1, green: 0.45, blue: 0.42) }
        return DashboardWidgetChrome.labelSecondary
    }

    private static let skeletonHeights: [CGFloat] = [0.6, 0.3, 0.8, 0.4, 0.7, 0.2, 0.5]

    private static let defaultEmptyDays: [DashboardWeekDay] = {
        let todayIdx = WeekdayHelper.todayIndex()
        return WeekdayHelper.dayLabels.enumerated().map { idx, label in
            DashboardWeekDay(id: idx, label: label, sessions: 0, isToday: idx == todayIdx)
        }
    }()
}

// MARK: - DayBar

private struct DayBar: View {

    let day: DashboardWeekDay
    let maxSessions: Int
    let barMaxHeight: CGFloat
    let barMinHeight: CGFloat
    let letter: String

    @State private var appeared = false

    private var heightFraction: CGFloat {
        guard maxSessions > 0, day.sessions > 0 else { return 0 }
        return CGFloat(day.sessions) / CGFloat(maxSessions)
    }

    private var barHeight: CGFloat {
        guard day.sessions > 0 else { return barMinHeight }
        return max(barMinHeight, barMaxHeight * heightFraction)
    }

    var body: some View {
        let displayHeight = appeared ? barHeight : barMinHeight
        let fill = day.sessions > 0 ? DashboardWidgetChrome.barFill : DashboardWidgetChrome.barTrack

        VStack(spacing: 8) {
            ZStack(alignment: .bottom) {
                Color.clear
                    .frame(height: barMaxHeight)

                Capsule()
                    .fill(fill)
                    .frame(height: displayHeight)
                    .animation(
                        .spring(duration: 0.6, bounce: 0.2).delay(Double(day.id) * 0.05),
                        value: appeared
                    )
            }
            .frame(maxWidth: .infinity)

            Text(letter)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(day.isToday ? DashboardWidgetChrome.labelSecondary : DashboardWidgetChrome.labelMuted)
        }
        .frame(maxWidth: .infinity)
        .onAppear { appeared = true }
    }
}

// MARK: - EmptyDayBar

private struct EmptyDayBar: View {

    let letter: String
    let isToday: Bool

    private let barMaxHeight: CGFloat = 80

    var body: some View {
        VStack(spacing: 8) {
            ZStack(alignment: .bottom) {
                Capsule()
                    .fill(DashboardWidgetChrome.barTrack)
                    .frame(height: barMaxHeight)

                Capsule()
                    .fill(isToday ? Color.white.opacity(0.2) : DashboardWidgetChrome.barTrack)
                    .frame(height: 4)
            }
            .frame(maxWidth: .infinity)

            Text(letter)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(isToday ? DashboardWidgetChrome.labelSecondary : DashboardWidgetChrome.labelMuted)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - SkeletonBar

private struct SkeletonBar: View {

    let heightFraction: CGFloat
    let barMaxHeight: CGFloat
    let letter: String
    @State private var isAnimating = false

    var body: some View {
        VStack(spacing: 8) {
            ZStack(alignment: .bottom) {
                Capsule()
                    .fill(Color.white.opacity(0.08))
                    .frame(height: barMaxHeight)

                Capsule()
                    .fill(Color.white.opacity(0.15))
                    .frame(height: barMaxHeight * heightFraction)
                    .opacity(isAnimating ? 0.5 : 1.0)
                    .animation(
                        .easeInOut(duration: 0.9).repeatForever(autoreverses: true),
                        value: isAnimating
                    )
            }
            .frame(maxWidth: .infinity)

            Text(letter)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(DashboardWidgetChrome.labelMuted)
        }
        .frame(maxWidth: .infinity)
        .onAppear { isAnimating = true }
    }
}

// MARK: - Preview

#if DEBUG
#Preview("WeeklyChart") {
    let sampleDays: [DashboardWeekDay] = [
        DashboardWeekDay(id: 0, label: "Mon", sessions: 1, isToday: false),
        DashboardWeekDay(id: 1, label: "Tue", sessions: 0, isToday: false),
        DashboardWeekDay(id: 2, label: "Wed", sessions: 2, isToday: false),
        DashboardWeekDay(id: 3, label: "Thu", sessions: 1, isToday: false),
        DashboardWeekDay(id: 4, label: "Fri", sessions: 2, isToday: true),
        DashboardWeekDay(id: 5, label: "Sat", sessions: 0, isToday: false),
        DashboardWeekDay(id: 6, label: "Sun", sessions: 0, isToday: false),
    ]

    ScrollView {
        VStack(spacing: AppSpacing.md) {
            WeeklyChart(days: sampleDays, isLoading: false, weekOverWeekPercent: 12)
            WeeklyChart(days: [], isLoading: false, weekOverWeekPercent: nil)
            WeeklyChart(days: [], isLoading: true, weekOverWeekPercent: -8)
        }
        .padding(AppSpacing.md)
    }
    .background(DashboardWidgetChrome.pageBackground)
}
#endif
