import SwiftUI

// MARK: - StatsView

/// Dedicated Stats screen with Daily, Weekly, Monthly, and Total tabs.
///
/// **Layout**
/// ```
/// +-----------------------------------+
/// |  Stats                [Export]    |  <- navigation bar
/// |  [Daily | Weekly | Monthly | All] |  <- segmented tab picker
/// |                                   |
/// |  [Tab-specific content]           |  <- scrollable content
/// |                                   |
/// +-----------------------------------+
/// ```
///
/// **Tabs**
/// - Daily   : Color-coded calendar with tap-to-detail
/// - Weekly  : Swift Charts bar chart + summary cards
/// - Monthly : Swift Charts line chart + comparison + summary
/// - Total   : Lifetime stats, streak banner, records, averages
///
/// **Features**
/// - Pull-to-refresh on all tabs
/// - Loading skeleton states
/// - Error alert with retry
/// - Export sheet (CSV/PDF placeholder)
/// - Streak indicator in navigation bar
struct StatsView: View {

    @StateObject private var viewModel = StatsViewModel()

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

            if viewModel.isLoading && viewModel.calendarDays.isEmpty {
                initialLoadingView
            } else {
                mainContent
            }
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
        Picker("Stats Period", selection: $viewModel.selectedTab) {
            ForEach(StatsTab.allCases) { tab in
                Text(tab.label).tag(tab)
            }
        }
        .pickerStyle(.segmented)
    }

    // MARK: - Tab Content

    @ViewBuilder
    private var tabContent: some View {
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

    // MARK: - Initial Loading View

    private var initialLoadingView: some View {
        VStack(spacing: AppSpacing.lg) {
            ProgressView()
                .progressViewStyle(.circular)
                .tint(AppColors.primary)
                .scaleEffect(1.4)

            Text("Loading Stats...")
                .font(AppTypography.subheadline)
                .foregroundStyle(AppColors.textSecondary)
        }
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
        // TODO: Implement PDF export via UIGraphicsPDFRenderer.
        // For now, show a placeholder share sheet.
        let pdfContent = "PDF export coming soon."
        shareContent(pdfContent, filename: "pushup_stats.pdf")
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
        StatsView()
    }
}

#Preview("StatsView - Dark") {
    NavigationStack {
        StatsView()
    }
    .preferredColorScheme(.dark)
}
#endif
