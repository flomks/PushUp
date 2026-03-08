import SwiftUI

// MARK: - DailyCalendarView

/// Calendar view for the Daily stats tab.
///
/// Displays a full month grid with color-coded day cells:
/// - Green fill  : day with workout
/// - Empty/muted : day without workout
/// - Ring border : today
///
/// Tapping a day that has workout data opens a detail sheet.
///
/// Usage:
/// ```swift
/// DailyCalendarView(
///     days: viewModel.calendarDays,
///     displayedMonth: viewModel.displayedMonth,
///     isLoading: viewModel.isLoading,
///     onPreviousMonth: { viewModel.previousMonth() },
///     onNextMonth: { viewModel.nextMonth() },
///     onSelectDay: { viewModel.selectDay($0) }
/// )
/// ```
struct DailyCalendarView: View {

    let days: [DayWorkoutData]
    let displayedMonth: Date
    let isLoading: Bool
    let onPreviousMonth: () -> Void
    let onNextMonth: () -> Void
    let onSelectDay: (DayWorkoutData) -> Void

    // MARK: - Grid

    private static let columns = Array(repeating: GridItem(.flexible(), spacing: 6), count: 7)
    private static let weekdayLabels = ["M", "T", "W", "T", "F", "S", "S"]

    var body: some View {
        VStack(spacing: AppSpacing.md) {
            monthNavigationHeader
            weekdayHeaderRow
            if isLoading {
                calendarSkeleton
            } else {
                calendarGrid
            }
            legendRow
        }
        .padding(AppSpacing.md)
        .background(AppColors.backgroundSecondary)
        .clipShape(RoundedRectangle(cornerRadius: AppSpacing.cornerRadiusCard))
        .shadow(color: Color.black.opacity(0.06), radius: 8, x: 0, y: 2)
    }

    // MARK: - Month Navigation Header

    private var monthNavigationHeader: some View {
        HStack {
            Button(action: onPreviousMonth) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(AppColors.primary)
                    .frame(width: AppSpacing.minimumTapTarget,
                           height: AppSpacing.minimumTapTarget)
            }
            .buttonStyle(ScaleButtonStyle())

            Spacer()

            Text(StatsViewModel.monthYearString(for: displayedMonth))
                .font(AppTypography.headline)
                .foregroundStyle(AppColors.textPrimary)

            Spacer()

            Button(action: onNextMonth) {
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(isNextMonthDisabled ? AppColors.textTertiary : AppColors.primary)
                    .frame(width: AppSpacing.minimumTapTarget,
                           height: AppSpacing.minimumTapTarget)
            }
            .buttonStyle(ScaleButtonStyle())
            .disabled(isNextMonthDisabled)
        }
    }

    private var isNextMonthDisabled: Bool {
        let calendar = Calendar.current
        return calendar.isDate(displayedMonth, equalTo: Date(), toGranularity: .month)
    }

    // MARK: - Weekday Header Row

    private var weekdayHeaderRow: some View {
        HStack(spacing: 6) {
            ForEach(Self.weekdayLabels, id: \.self) { label in
                Text(label)
                    .font(AppTypography.caption2)
                    .foregroundStyle(AppColors.textSecondary)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    // MARK: - Calendar Grid

    @ViewBuilder
    private var calendarGrid: some View {
        let calendar = Calendar.current
        let leadingBlanks = leadingBlankCount(for: displayedMonth)
        let allCells = buildCells(leadingBlanks: leadingBlanks)

        LazyVGrid(columns: Self.columns, spacing: 6) {
            ForEach(allCells) { cell in
                switch cell.kind {
                case .blank:
                    Color.clear
                        .aspectRatio(1, contentMode: .fit)
                case .day(let dayData):
                    CalendarDayCell(
                        day: dayData,
                        isToday: calendar.isDateInToday(dayData.date)
                    )
                    .onTapGesture {
                        if dayData.hasWorkout {
                            onSelectDay(dayData)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Skeleton

    @ViewBuilder
    private var calendarSkeleton: some View {
        LazyVGrid(columns: Self.columns, spacing: 6) {
            ForEach(0..<35, id: \.self) { _ in
                RoundedRectangle(cornerRadius: 8)
                    .fill(AppColors.fill)
                    .aspectRatio(1, contentMode: .fit)
                    .opacity(Double.random(in: 0.4...0.8))
            }
        }
    }

    // MARK: - Legend

    private var legendRow: some View {
        HStack(spacing: AppSpacing.md) {
            legendItem(color: AppColors.success.opacity(0.8), label: "Workout")
            legendItem(color: AppColors.fill, label: "Rest day")
            Spacer()
        }
    }

    private func legendItem(color: Color, label: String) -> some View {
        HStack(spacing: AppSpacing.xxs) {
            RoundedRectangle(cornerRadius: 4)
                .fill(color)
                .frame(width: 14, height: 14)
            Text(label)
                .font(AppTypography.caption2)
                .foregroundStyle(AppColors.textSecondary)
        }
    }

    // MARK: - Helpers

    /// Number of blank cells before the first day of the month (Mon-based).
    private func leadingBlankCount(for month: Date) -> Int {
        let calendar = Calendar.current
        guard let firstDay = calendar.date(
            from: calendar.dateComponents([.year, .month], from: month)
        ) else { return 0 }
        let weekday = calendar.component(.weekday, from: firstDay)
        // weekday: 1=Sun, 2=Mon...7=Sat -> Mon-based 0-index
        return (weekday + 5) % 7
    }

    private func buildCells(leadingBlanks: Int) -> [CalendarCell] {
        var cells: [CalendarCell] = []
        for _ in 0..<leadingBlanks {
            cells.append(CalendarCell(kind: .blank))
        }
        for day in days {
            cells.append(CalendarCell(kind: .day(day)))
        }
        return cells
    }
}

// MARK: - CalendarCell

private struct CalendarCell: Identifiable {
    let id = UUID()
    enum Kind {
        case blank
        case day(DayWorkoutData)
    }
    let kind: Kind
}

// MARK: - CalendarDayCell

private struct CalendarDayCell: View {

    let day: DayWorkoutData
    let isToday: Bool

    private var dayNumber: String {
        let calendar = Calendar.current
        return "\(calendar.component(.day, from: day.date))"
    }

    var body: some View {
        ZStack {
            // Background fill
            RoundedRectangle(cornerRadius: 8)
                .fill(cellBackground)

            // Today ring
            if isToday {
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(AppColors.primary, lineWidth: 2)
            }

            VStack(spacing: 2) {
                Text(dayNumber)
                    .font(AppTypography.caption2)
                    .fontWeight(isToday ? .bold : .regular)
                    .foregroundStyle(textColor)

                // Intensity dot for workout days
                if day.hasWorkout {
                    Circle()
                        .fill(intensityColor)
                        .frame(width: 4, height: 4)
                }
            }
        }
        .aspectRatio(1, contentMode: .fit)
    }

    private var cellBackground: Color {
        if day.hasWorkout {
            return AppColors.success.opacity(intensityOpacity)
        }
        return AppColors.fill.opacity(0.5)
    }

    private var textColor: Color {
        if isToday { return AppColors.primary }
        if day.hasWorkout { return AppColors.textPrimary }
        return AppColors.textSecondary
    }

    private var intensityOpacity: Double {
        guard day.pushUps > 0 else { return 0 }
        // Scale opacity from 0.25 (low) to 0.85 (high) based on push-up count
        let clamped = min(Double(day.pushUps), 80.0)
        return 0.25 + (clamped / 80.0) * 0.60
    }

    private var intensityColor: Color {
        AppColors.success
    }
}

// MARK: - DayDetailView

/// Sheet shown when the user taps a workout day in the calendar.
struct DayDetailView: View {

    let day: DayWorkoutData
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: AppSpacing.md) {
                    // Date header
                    VStack(spacing: AppSpacing.xxs) {
                        Text(StatsViewModel.shortDateString(for: day.date))
                            .font(AppTypography.title2)
                            .foregroundStyle(AppColors.textPrimary)

                        Text("Workout Summary")
                            .font(AppTypography.subheadline)
                            .foregroundStyle(AppColors.textSecondary)
                    }
                    .padding(.top, AppSpacing.sm)

                    // Stats grid
                    LazyVGrid(
                        columns: [GridItem(.flexible()), GridItem(.flexible())],
                        spacing: AppSpacing.sm
                    ) {
                        StatCard(
                            title: "Push-Ups",
                            value: "\(day.pushUps)",
                            subtitle: "Total",
                            icon: .figureStrengthTraining,
                            tint: AppColors.primary
                        )
                        StatCard(
                            title: "Sessions",
                            value: "\(day.sessions)",
                            subtitle: "Units",
                            icon: .timer,
                            tint: AppColors.secondary
                        )
                        StatCard(
                            title: "Earned",
                            value: "\(day.earnedMinutes) min",
                            subtitle: "Time Credit",
                            icon: .boltFill,
                            tint: AppColors.success
                        )
                        StatCard(
                            title: "Quality",
                            value: String(format: "%.0f%%", day.averageQuality * 100),
                            subtitle: "Average",
                            icon: .starFill,
                            tint: AppColors.formScoreColor(day.averageQuality)
                        )
                    }
                    .padding(.horizontal, AppSpacing.screenHorizontal)
                }
                .padding(.bottom, AppSpacing.screenVerticalBottom)
            }
            .background(AppColors.backgroundPrimary.ignoresSafeArea())
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                        .font(AppTypography.bodySemibold)
                        .foregroundStyle(AppColors.primary)
                }
            }
        }
    }
}

// MARK: - Previews

#if DEBUG
#Preview("DailyCalendarView") {
    let sampleDays: [DayWorkoutData] = {
        let calendar = Calendar.current
        let today = Date()
        guard let monthStart = calendar.date(
            from: calendar.dateComponents([.year, .month], from: today)
        ) else { return [] }
        let pushUps = [35, 0, 52, 18, 42, 0, 0, 28, 45, 0, 61, 33, 0, 0, 40, 22, 55, 0, 38, 0, 0]
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return (0..<21).compactMap { offset in
            guard let date = calendar.date(byAdding: .day, value: offset, to: monthStart) else { return nil }
            let pu = pushUps[offset]
            return DayWorkoutData(
                id: formatter.string(from: date),
                date: date,
                pushUps: pu,
                sessions: pu > 0 ? 1 : 0,
                earnedMinutes: pu / 3,
                averageQuality: pu > 0 ? 0.82 : 0
            )
        }
    }()

    ScrollView {
        DailyCalendarView(
            days: sampleDays,
            displayedMonth: Date(),
            isLoading: false,
            onPreviousMonth: {},
            onNextMonth: {},
            onSelectDay: { _ in }
        )
        .padding(AppSpacing.md)
    }
    .background(AppColors.backgroundPrimary)
}
#endif
