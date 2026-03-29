import SwiftUI

// MARK: - StatsView

/// Dedicated Stats screen with Daily, Weekly, Monthly, Total, Screen Time,
/// and History segments.
///
/// **Layout**
/// ```
/// +-------------------------------------------+
/// |  Stats                          [Export]   |  <- navigation bar
/// |  [Daily][Weekly][Monthly][Total][History]  |  <- scrollable chip picker
/// |                                            |
/// |  [Segment-specific content]                |  <- scrollable content
/// |                                            |
/// +-------------------------------------------+
/// ```
///
/// **Segments**
/// - Daily   : Color-coded calendar with tap-to-detail
/// - Weekly  : Swift Charts bar chart + summary cards
/// - Monthly : Swift Charts line chart + comparison + summary
/// - Total   : Lifetime stats, streak banner, records, averages
/// - Screen  : Screen Time stats
/// - History : Full workout history list (moved here from its own tab so
///             Friends can have a dedicated tab bar position)
///
/// **Features**
/// - Pull-to-refresh on all segments (except History which manages its own)
/// - Loading skeleton states
/// - Error alert with retry
/// - Export sheet (CSV/PDF placeholder)
/// - Streak indicator in navigation bar
struct StatsView: View {

    @ObservedObject var viewModel: StatsViewModel

    /// Controls whether the export action sheet is presented.
    @State private var showExportSheet = false

    private var showError: Binding<Bool> {
        Binding(
            get: { viewModel.errorMessage != nil },
            set: { if !$0 { viewModel.clearError() } }
        )
    }

    var body: some View {
        ZStack {
            AppColors.backgroundPrimary
                .ignoresSafeArea()

            mainContent
        }
        .navigationTitle("Stats")
        .navigationBarTitleDisplayMode(.large)
        .toolbar { toolbarContent }
        .task { await viewModel.loadData() }
        .alert("Error", isPresented: showError) {
            Button("Try Again") {
                Task { await viewModel.loadData() }
            }
            Button("OK", role: .cancel) {}
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
        .sheet(isPresented: $viewModel.showDayDetail) {
            if let day = viewModel.selectedDay {
                DayDetailView(day: day)
                    .presentationDetents([.medium, .large])
                    .presentationDragIndicator(.visible)
            }
        }
        .confirmationDialog(
            "Export Stats",
            isPresented: $showExportSheet,
            titleVisibility: .visible
        ) {
            Button("Export as CSV") { exportCSV() }
            Button("Export as PDF") { exportPDF() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Choose a format to export your statistics.")
        }
    }

    // MARK: - Main Content

    private var mainContent: some View {
        VStack(spacing: 0) {
            tabPicker
                .padding(.horizontal, AppSpacing.screenHorizontal)
                .padding(.top, AppSpacing.xs)
                .padding(.bottom, AppSpacing.sm)
                .background(AppColors.backgroundPrimary)

            tabContent
        }
    }

    // MARK: - Tab Picker

    private var tabPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: AppSpacing.xs) {
                ForEach(StatsTab.allCases) { tab in
                    tabChip(tab)
                }
            }
            .padding(.horizontal, AppSpacing.xxs)
        }
    }

    private func tabChip(_ tab: StatsTab) -> some View {
        let isSelected = viewModel.selectedTab == tab
        return Button {
            viewModel.selectedTab = tab
        } label: {
            Text(tab.label)
                .font(AppTypography.captionSemibold)
                .foregroundStyle(isSelected ? AppColors.textOnPrimary : AppColors.textPrimary)
                .padding(.horizontal, AppSpacing.sm)
                .padding(.vertical, AppSpacing.xxs + 2)
                .background(
                    isSelected ? AppColors.primary : AppColors.backgroundTertiary,
                    in: Capsule()
                )
        }
        .buttonStyle(.plain)
        .animation(.easeInOut(duration: 0.15), value: isSelected)
    }

    // MARK: - Tab Content

    @ViewBuilder
    private var tabContent: some View {
        if viewModel.selectedTab == .history {
            // History has its own scroll + filter layout; render it directly
            // without wrapping in another ScrollView.
            HistoryView()
        } else {
            ScrollView {
                LazyVStack(spacing: AppSpacing.md) {
                    switch viewModel.selectedTab {
                    case .daily:
                        dailyContent
                    case .weekly:
                        weeklyContent
                    case .monthly:
                        monthlyContent
                    case .total:
                        totalContent
                    case .screenTime:
                        screenTimeContent
                    case .history:
                        EmptyView() // handled above
                    }
                }
                .padding(.horizontal, AppSpacing.screenHorizontal)
                .padding(.top, AppSpacing.sm)
                .padding(.bottom, AppSpacing.screenVerticalBottom)
            }
            .refreshable {
                await viewModel.refresh()
            }
        }
    }

    // MARK: - Daily Content

    @ViewBuilder
    private var dailyContent: some View {
        DailyCalendarView(
            days: viewModel.calendarDays,
            displayedMonth: viewModel.displayedMonth,
            isLoading: viewModel.isLoading,
            onPreviousMonth: { viewModel.previousMonth() },
            onNextMonth: { viewModel.nextMonth() },
            onSelectDay: { viewModel.selectDay($0) }
        )

        // Hint card
        if !viewModel.isLoading {
            Card(hasShadow: false) {
                HStack(spacing: AppSpacing.sm) {
                    Image(systemName: AppIcon.infoCircle.rawValue)
                        .font(.system(size: AppSpacing.iconSizeSmall))
                        .foregroundStyle(AppColors.info)

                    Text("Tap a green day to see detailed workout stats.")
                        .font(AppTypography.caption1)
                        .foregroundStyle(AppColors.textSecondary)

                    Spacer()
                }
            }
        }
    }

    // MARK: - Weekly Content

    @ViewBuilder
    private var weeklyContent: some View {
        WeeklyChartView(
            bars: viewModel.weeklyBars,
            totalPushUps: viewModel.weeklyTotalPushUps,
            averagePushUps: viewModel.weeklyAveragePushUps,
            totalSessions: viewModel.weeklyTotalSessions,
            earnedMinutes: viewModel.weeklyEarnedMinutes,
            isLoading: viewModel.isLoading
        )
    }

    // MARK: - Monthly Content

    @ViewBuilder
    private var monthlyContent: some View {
        MonthlyChartView(
            weeks: viewModel.monthlyWeeks,
            totalPushUps: viewModel.monthlyTotalPushUps,
            totalSessions: viewModel.monthlyTotalSessions,
            earnedMinutes: viewModel.monthlyEarnedMinutes,
            comparison: viewModel.monthComparison,
            isLoading: viewModel.isLoading
        )
    }

    // MARK: - Total Content

    @ViewBuilder
    private var totalContent: some View {
        TotalStatsView(
            stats: viewModel.totalStats,
            isLoading: viewModel.isLoading
        )
    }

    // MARK: - Screen Time Content

    @ViewBuilder
    private var screenTimeContent: some View {
        // Embed the ScreenTimeStatsView content inline (without its own NavigationStack)
        ScreenTimeStatsInlineView()
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        // Streak indicator (leading)
        ToolbarItem(placement: .navigationBarLeading) {
            if !viewModel.isLoading, let stats = viewModel.totalStats,
               stats.currentStreakDays > 0 {
                streakBadge(days: stats.currentStreakDays)
            }
        }

        // Refresh indicator + Export button (trailing)
        ToolbarItemGroup(placement: .navigationBarTrailing) {
            if viewModel.isRefreshing {
                ProgressView()
                    .progressViewStyle(.circular)
                    .tint(AppColors.primary)
            }

            Button {
                showExportSheet = true
            } label: {
                Image(systemName: AppIcon.squareAndArrowUp.rawValue)
                    .font(.system(size: AppSpacing.iconSizeSmall, weight: .semibold))
                    .foregroundStyle(AppColors.primary)
            }
            .accessibilityLabel("Export Stats")
        }
    }

    private func streakBadge(days: Int) -> some View {
        HStack(spacing: AppSpacing.xxs) {
            Image(systemName: AppIcon.flameFill.rawValue)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(AppColors.secondary)

            Text("\(days)")
                .font(AppTypography.captionSemibold)
                .foregroundStyle(AppColors.textPrimary)
        }
        .padding(.horizontal, AppSpacing.xs)
        .padding(.vertical, AppSpacing.xxs)
        .background(AppColors.secondary.opacity(0.12), in: Capsule())
    }

    // MARK: - Export Actions

    private func exportCSV() {
        // TODO: Implement CSV export via KMP shared module or local generation.
        // For now, show a placeholder share sheet.
        let csvContent = generateCSVContent()
        shareContent(csvContent, filename: "pushup_stats.csv")
    }

    private func exportPDF() {
        // PDF export requires UIGraphicsPDFRenderer integration.
        // For now, fall back to CSV export with a user-facing note.
        viewModel.errorMessage = "PDF export is not yet available. Use CSV export instead."
    }

    private func generateCSVContent() -> String {
        var lines = ["Date,Push-Ups,Sessions,Earned Minutes,Quality"]
        for day in viewModel.calendarDays where day.hasWorkout {
            // Use the stable ISO date id ("yyyy-MM-dd") for unambiguous CSV output.
            let quality = String(format: "%.0f", day.averageQuality * 100)
            lines.append("\(day.id),\(day.pushUps),\(day.sessions),\(day.earnedMinutes),\(quality)")
        }
        return lines.joined(separator: "\n")
    }

    private func shareContent(_ content: String, filename: String) {
        guard let windowScene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first,
              let rootVC = windowScene.windows.first?.rootViewController else { return }

        // Use a unique temp file to avoid stale-cache issues with repeated exports.
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("stats_export", isDirectory: true)
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        let tempURL = tempDir.appendingPathComponent(filename)

        do {
            try content.write(to: tempURL, atomically: true, encoding: .utf8)
        } catch {
            // Surface the error to the user instead of silently failing.
            viewModel.errorMessage = "Could not prepare export file."
            return
        }

        let activityVC = UIActivityViewController(
            activityItems: [tempURL],
            applicationActivities: nil
        )

        // iPad requires a popover source; without this the app crashes on iPad.
        if let popover = activityVC.popoverPresentationController {
            popover.sourceView = rootVC.view
            popover.sourceRect = CGRect(
                x: rootVC.view.bounds.midX,
                y: rootVC.view.bounds.midY,
                width: 0, height: 0
            )
            popover.permittedArrowDirections = []
        }

        rootVC.present(activityVC, animated: true)
    }
}

// MARK: - Previews

#if DEBUG
#Preview("StatsView - Loaded") {
    NavigationStack {
        StatsView(viewModel: StatsViewModel())
    }
}

#Preview("StatsView - Dark") {
    NavigationStack {
        StatsView(viewModel: StatsViewModel())
    }
    .preferredColorScheme(.dark)
}
#endif
