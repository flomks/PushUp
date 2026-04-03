import SwiftUI
import Shared

struct FriendStatsView: View {

    @StateObject private var detailViewModel: FriendDetailViewModel

    let friendId: String
    let friendName: String

    init(viewModel: FriendsViewModel, friendId: String, friendName: String) {
        self.friendId = friendId
        self.friendName = friendName
        _detailViewModel = StateObject(
            wrappedValue: FriendDetailViewModel(
                friendId: friendId,
                friendName: friendName,
                initialPeriod: viewModel.friendStatsPeriod
            )
        )
    }

    var body: some View {
        ScrollView {
            VStack(spacing: AppSpacing.md) {
                periodPicker
                heroCard

                if let message = detailViewModel.errorMessage, detailViewModel.stats == nil {
                    errorCard(message)
                } else {
                    overviewGrid
                    levelCard
                    calendarSection
                    exerciseLevelsSection
                }
            }
            .padding(.horizontal, AppSpacing.screenHorizontal)
            .padding(.top, AppSpacing.md)
            .padding(.bottom, AppSpacing.screenVerticalBottom)
        }
        .background(AppColors.backgroundPrimary)
        .navigationTitle(friendName.isEmpty ? "Friend" : friendName)
        .navigationBarTitleDisplayMode(.large)
        .task {
            await detailViewModel.loadAll()
        }
        .sheet(isPresented: $detailViewModel.showDayDetail) {
            if let selectedDay = detailViewModel.selectedDay {
                DayDetailView(day: selectedDay)
            }
        }
    }

    private var periodPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: AppSpacing.xs) {
                ForEach(FriendStatsPeriod.allCases) { period in
                    let isSelected = detailViewModel.period == period
                    Button {
                        Task { await detailViewModel.changePeriod(period) }
                    } label: {
                        Text(period.label)
                            .font(AppTypography.captionSemibold)
                            .foregroundStyle(isSelected ? AppColors.textOnPrimary : AppColors.textPrimary)
                            .padding(.horizontal, AppSpacing.sm)
                            .padding(.vertical, AppSpacing.xxs + 2)
                            .background(isSelected ? AppColors.primary : AppColors.backgroundTertiary, in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 2)
        }
    }

    private var heroCard: some View {
        ZStack(alignment: .bottomLeading) {
            RoundedRectangle(cornerRadius: AppSpacing.cornerRadiusLarge + 4)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.11, green: 0.16, blue: 0.30),
                            Color(red: 0.15, green: 0.44, blue: 0.63),
                            Color(red: 0.95, green: 0.44, blue: 0.24)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay(alignment: .topTrailing) {
                    Circle()
                        .fill(Color.white.opacity(0.10))
                        .frame(width: 180, height: 180)
                        .offset(x: 44, y: -44)
                }

            VStack(alignment: .leading, spacing: AppSpacing.md) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: AppSpacing.xxs) {
                        Text("FRIEND PROFILE")
                            .font(.system(size: 12, weight: .bold, design: .rounded))
                            .foregroundStyle(Color.white.opacity(0.72))
                            .tracking(2)

                        Text(friendName)
                            .font(.system(size: 30, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                            .lineLimit(2)
                    }

                    Spacer(minLength: 12)

                    ZStack {
                        Circle()
                            .fill(Color.white.opacity(0.14))
                            .frame(width: 62, height: 62)

                        Text(FriendItem.makeInitials(friendName))
                            .font(.system(size: 22, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                    }
                }

                Text(detailViewModel.subtitleText)
                    .font(AppTypography.body)
                    .foregroundStyle(Color.white.opacity(0.84))

                HStack(spacing: AppSpacing.sm) {
                    heroMetric(title: "Activity", value: detailViewModel.stats.map { "\($0.activityPoints)" } ?? "--")
                    heroMetric(title: "Streak", value: detailViewModel.stats.map { "\($0.currentStreak)d" } ?? "--")
                    heroMetric(title: "Level", value: detailViewModel.levelInfo.map { "Lv \($0.level)" } ?? "Lv --")
                }
            }
            .padding(AppSpacing.xl)
        }
        .overlay {
            if detailViewModel.isLoading && detailViewModel.stats == nil {
                ProgressView()
                    .tint(.white)
            }
        }
    }

    private var overviewGrid: some View {
        let stats = detailViewModel.stats
        let averageQuality = stats?.averageQuality
        let activityScoreValue = stats.map { "\($0.activityPoints)" } ?? "--"
        let sessionsValue = stats.map { "\($0.totalSessions)" } ?? "--"
        let earnedTimeValue = stats.map { formatDuration(seconds: $0.totalEarnedSeconds) } ?? "--"
        let normalizedQuality = averageQuality.map(Double.init)
        let formQualityValue = normalizedQuality.map { "\(Int(($0 * 100.0).rounded()))%" } ?? "--"
        let formQualityTint = normalizedQuality.map { quality in
            AppColors.formScoreColor(quality)
        } ?? AppColors.textSecondary

        return LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: AppSpacing.sm) {
            metricCard(title: "Activity Score", value: activityScoreValue, icon: "bolt.fill", tint: AppColors.primary)
            metricCard(title: "Sessions", value: sessionsValue, icon: "figure.mixed.cardio", tint: AppColors.info)
            metricCard(title: "Earned Time", value: earnedTimeValue, icon: "clock.fill", tint: AppColors.secondary)
            metricCard(title: "Form Quality", value: formQualityValue, icon: "checkmark.seal.fill", tint: formQualityTint)
        }
    }

    private var levelCard: some View {
        Card {
            VStack(alignment: .leading, spacing: AppSpacing.md) {
                sectionHeader("Level Overview", subtitle: "Account progression and current tier")

                if let level = detailViewModel.levelInfo {
                    HStack(alignment: .center, spacing: AppSpacing.md) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Level \(level.level)")
                                .font(AppTypography.title3)
                                .foregroundStyle(AppColors.textPrimary)
                            Text("\(level.totalXp) XP total")
                                .font(AppTypography.caption1)
                                .foregroundStyle(AppColors.textSecondary)
                        }

                        Spacer()

                        Text("\(Int((level.levelProgress * 100).rounded()))%")
                            .font(.system(size: 28, weight: .bold, design: .rounded))
                            .foregroundStyle(AppColors.primary)
                    }

                    ExerciseLevelProgressBar(progress: level.levelProgress, tint: AppColors.primary)

                    Text("\(level.xpIntoLevel) / \(level.xpRequiredForNextLevel) XP in current level")
                        .font(AppTypography.caption1)
                        .foregroundStyle(AppColors.textSecondary)
                } else {
                    Text("No level data available yet.")
                        .font(AppTypography.body)
                        .foregroundStyle(AppColors.textSecondary)
                }
            }
        }
    }

    private var calendarSection: some View {
        Card(padding: 0, hasShadow: true) {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    sectionHeader("Activity Calendar", subtitle: "Monthly rhythm across all workout types")
                    Spacer()
                }
                .padding(.horizontal, AppSpacing.cardPadding)
                .padding(.top, AppSpacing.cardPadding)

                if detailViewModel.isLoadingCalendar && detailViewModel.calendarDays.isEmpty {
                    VStack(spacing: AppSpacing.md) {
                        ProgressView()
                        Text("Loading monthly activity...")
                            .font(AppTypography.caption1)
                            .foregroundStyle(AppColors.textSecondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(AppSpacing.lg)
                } else {
                    DailyCalendarView(
                        days: detailViewModel.calendarDays,
                        displayedMonth: detailViewModel.displayedMonth,
                        isLoading: detailViewModel.isLoadingCalendar,
                        onPreviousMonth: { Task { await detailViewModel.previousMonth() } },
                        onNextMonth: { Task { await detailViewModel.nextMonth() } },
                        onSelectDay: { detailViewModel.selectDay($0) }
                    )
                    .padding(AppSpacing.sm)
                }
            }
        }
    }

    private var exerciseLevelsSection: some View {
        Card {
            VStack(alignment: .leading, spacing: AppSpacing.md) {
                sectionHeader("Category Levels", subtitle: "Progress inside each activity type")

                if detailViewModel.exerciseLevels.isEmpty {
                    Text("No category levels available yet.")
                        .font(AppTypography.body)
                        .foregroundStyle(AppColors.textSecondary)
                } else {
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: AppSpacing.sm) {
                        ForEach(detailViewModel.exerciseLevels) { info in
                            ExerciseLevelCell(info: info)
                        }
                    }
                }
            }
        }
    }

    private func metricCard(title: String, value: String, icon: String, tint: Color) -> some View {
        Card {
            VStack(alignment: .leading, spacing: AppSpacing.xs) {
                Image(systemName: icon)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(tint)
                Text(value)
                    .font(AppTypography.displayMedium)
                    .foregroundStyle(AppColors.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                Text(title)
                    .font(AppTypography.caption1)
                    .foregroundStyle(AppColors.textSecondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func sectionHeader(_ title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.xxs) {
            Text(title)
                .font(AppTypography.headline)
                .foregroundStyle(AppColors.textPrimary)
            Text(subtitle)
                .font(AppTypography.caption1)
                .foregroundStyle(AppColors.textSecondary)
        }
    }

    private func heroMetric(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
            Text(title)
                .font(AppTypography.caption1)
                .foregroundStyle(Color.white.opacity(0.74))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, AppSpacing.sm)
        .padding(.vertical, AppSpacing.xs)
        .background(Color.white.opacity(0.12), in: RoundedRectangle(cornerRadius: AppSpacing.cornerRadiusButton))
    }

    private func errorCard(_ message: String) -> some View {
        Card {
            VStack(spacing: AppSpacing.md) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 28))
                    .foregroundStyle(AppColors.error)
                Text(message)
                    .font(AppTypography.body)
                    .foregroundStyle(AppColors.textSecondary)
                    .multilineTextAlignment(.center)
                Button("Retry") {
                    Task { await detailViewModel.loadAll(force: true) }
                }
                .buttonStyle(.borderedProminent)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, AppSpacing.md)
        }
    }
}

@MainActor
private final class FriendDetailViewModel: ObservableObject {

    let friendId: String
    let friendName: String

    @Published var period: FriendStatsPeriod
    @Published var displayedMonth: Date = Date()
    @Published private(set) var stats: FriendActivityStats?
    @Published private(set) var levelInfo: LevelInfo?
    @Published private(set) var exerciseLevels: [ExerciseLevelInfo] = []
    @Published private(set) var calendarDays: [DayWorkoutData] = []
    @Published private(set) var errorMessage: String?
    @Published private(set) var isLoading: Bool = false
    @Published private(set) var isLoadingCalendar: Bool = false
    @Published var selectedDay: DayWorkoutData?
    @Published var showDayDetail: Bool = false

    init(friendId: String, friendName: String, initialPeriod: FriendStatsPeriod) {
        self.friendId = friendId
        self.friendName = friendName
        self.period = initialPeriod
    }

    var subtitleText: String {
        if let stats {
            return "\(stats.totalSessions) sessions in \(period.label.lowercased()), \(formatDuration(seconds: stats.totalEarnedSeconds)) earned."
        }
        return "Inspect activity, consistency, and category progression."
    }

    func loadAll(force: Bool = false) async {
        if isLoading && !force { return }
        isLoading = true
        errorMessage = nil

        async let statsTask = loadStats()
        async let levelTask = loadLevels()
        async let calendarTask = loadCalendar()

        _ = await (statsTask, levelTask, calendarTask)
        isLoading = false
    }

    func changePeriod(_ newPeriod: FriendStatsPeriod) async {
        guard newPeriod != period else { return }
        period = newPeriod
        await loadStats()
    }

    func previousMonth() async {
        displayedMonth = Calendar.current.date(byAdding: .month, value: -1, to: displayedMonth) ?? displayedMonth
        await loadCalendar()
    }

    func nextMonth() async {
        let candidate = Calendar.current.date(byAdding: .month, value: 1, to: displayedMonth) ?? displayedMonth
        if Calendar.current.isDate(candidate, equalTo: Date(), toGranularity: .month) || candidate < Date() {
            displayedMonth = candidate
            await loadCalendar()
        }
    }

    func selectDay(_ day: DayWorkoutData) {
        guard day.hasWorkout else { return }
        selectedDay = day
        showDayDetail = true
    }

    private func loadStats() async {
        await withCheckedContinuation { continuation in
            FriendsBridge.shared.getFriendStats(
                friendId: friendId,
                period: period.rawValue,
                onResult: { [weak self] result in
                    self?.stats = result
                    continuation.resume()
                },
                onError: { [weak self] error in
                    self?.errorMessage = error
                    continuation.resume()
                }
            )
        }
    }

    private func loadLevels() async {
        await withCheckedContinuation { continuation in
            FriendsBridge.shared.getFriendLevelDetails(
                friendId: friendId,
                onResult: { [weak self] details in
                    self?.levelInfo = LevelInfo(
                        level: Int(details.level),
                        totalXp: Int64(details.totalXp),
                        xpIntoLevel: Int64(details.xpIntoLevel),
                        xpRequiredForNextLevel: Int64(details.xpRequiredForNextLevel),
                        levelProgress: details.levelProgress
                    )
                    self?.exerciseLevels = details.exerciseLevels.map {
                        ExerciseLevelInfo(
                            exerciseTypeId: $0.exerciseTypeId,
                            level: Int($0.level),
                            totalXp: Int64($0.totalXp),
                            xpIntoLevel: Int64($0.xpIntoLevel),
                            xpRequiredForNextLevel: Int64($0.xpRequiredForNextLevel),
                            levelProgress: $0.levelProgress
                        )
                    }
                    continuation.resume()
                },
                onError: { [weak self] error in
                    self?.errorMessage = error
                    continuation.resume()
                }
            )
        }
    }

    private func loadCalendar() async {
        isLoadingCalendar = true
        let calendar = Calendar.current
        let month = calendar.component(.month, from: displayedMonth)
        let year = calendar.component(.year, from: displayedMonth)

        await withCheckedContinuation { continuation in
            FriendsBridge.shared.getFriendMonthlyActivity(
                friendId: friendId,
                month: Int32(month),
                year: Int32(year),
                onResult: { [weak self] summary in
                    self?.calendarDays = summary.days.compactMap { day in
                        guard let date = Self.isoDateFormatter.date(from: day.date) else { return nil }
                        return DayWorkoutData(
                            id: day.date,
                            date: date,
                            activityPoints: Int(day.activityPoints),
                            sessions: Int(day.totalSessions),
                            earnedMinutes: Int(day.totalEarnedSeconds / 60),
                            averageQuality: 0
                        )
                    }
                    self?.isLoadingCalendar = false
                    continuation.resume()
                },
                onError: { [weak self] error in
                    self?.errorMessage = error
                    self?.isLoadingCalendar = false
                    continuation.resume()
                }
            )
        }
    }

    private static let isoDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter
    }()
}

private func formatDuration(seconds: Int64) -> String {
    let minutes = seconds / 60
    guard minutes >= 60 else { return "\(minutes) min" }
    let hours = minutes / 60
    let remaining = minutes % 60
    return remaining == 0 ? "\(hours)h" : "\(hours)h \(remaining)m"
}
