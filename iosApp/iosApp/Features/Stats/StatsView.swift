import SwiftUI

// MARK: - StatsView

private enum StatsSection: String, CaseIterable, Identifiable {
    case exercises
    case screenTime
    case history

    var id: String { rawValue }

    var title: String {
        switch self {
        case .exercises:  return "Exercises"
        case .screenTime: return "Screen Time"
        case .history:    return "History"
        }
    }

    var subtitle: String {
        switch self {
        case .exercises:  return "Calendar, trends, streaks, and workout totals."
        case .screenTime: return "Usage, blocking, and daily consumption patterns."
        case .history:    return "Every finished session in one dedicated stream."
        }
    }

    var icon: AppIcon {
        switch self {
        case .exercises:  return .figureStrengthTraining
        case .screenTime: return .hourglassFill
        case .history:    return .listBulletRectangle
        }
    }

    var tint: Color {
        switch self {
        case .exercises:  return AppColors.info
        case .screenTime: return AppColors.secondary
        case .history:    return DashboardWidgetChrome.accentPositive
        }
    }

    var orbitOffset: CGSize {
        switch self {
        case .exercises:  return CGSize(width: -112, height: 66)
        case .screenTime: return CGSize(width: 112, height: 54)
        case .history:    return CGSize(width: 0, height: -94)
        }
    }
}

/// Dedicated Stats hub with separated areas for exercise analytics,
/// screen-time analytics, and workout history.
///
/// **Layout**
/// ```
/// +-------------------------------------------+
/// |  Stats                          [Export]   |  <- navigation bar
/// |  [Radial section selector / pills]         |  <- top-level navigation
/// |                                            |
/// |  [Section-specific content]                |  <- focused content
/// |                                            |
/// +-------------------------------------------+
/// ```
///
/// **Sections**
/// - Exercises  : Daily / Weekly / Monthly / Total workout analytics
/// - Screen Time: Usage and blocking analytics
/// - History    : Full workout history list
///
/// **Features**
/// - Top-level area separation to avoid mixing domains
/// - Pull-to-refresh for analytics content
/// - Error alert with retry
/// - Export sheet for exercise analytics
/// - Streak indicator in navigation bar
struct StatsView: View {

    @ObservedObject var viewModel: StatsViewModel

    /// Controls whether the export action sheet is presented.
    @State private var showExportSheet = false
    @State private var selectedSection: StatsSection = .exercises

    private var showError: Binding<Bool> {
        Binding(
            get: { viewModel.errorMessage != nil },
            set: { if !$0 { viewModel.clearError() } }
        )
    }

    var body: some View {
        ZStack {
            DashboardWidgetChrome.pageBackground
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
            sectionNavigator
                .padding(.horizontal, AppSpacing.screenHorizontal)
                .padding(.top, AppSpacing.sm)
                .padding(.bottom, AppSpacing.lg)

            if selectedSection == .history {
                HistoryView()
            } else {
                ScrollView {
                    LazyVStack(spacing: AppSpacing.lg) {
                        sectionContent
                    }
                    .padding(.horizontal, AppSpacing.screenHorizontal)
                    .padding(.bottom, AppSpacing.screenVerticalBottom)
                }
            }
        }
        .refreshable {
            await viewModel.refresh()
        }
    }

    // MARK: - Section Navigator

    private var sectionNavigator: some View {
        Card(padding: AppSpacing.lg, cornerRadius: AppSpacing.cornerRadiusLarge, hasShadow: false) {
            VStack(alignment: .leading, spacing: AppSpacing.lg) {
                VStack(alignment: .leading, spacing: AppSpacing.xs) {
                    Text("Choose a lane")
                        .font(AppTypography.captionSemibold)
                        .foregroundStyle(DashboardWidgetChrome.labelSecondary)
                        .textCase(.uppercase)

                    Text(selectedSection.title)
                        .font(AppTypography.title2)
                        .foregroundStyle(DashboardWidgetChrome.labelPrimary)

                    Text(selectedSection.subtitle)
                        .font(AppTypography.body)
                        .foregroundStyle(DashboardWidgetChrome.labelSecondary)
                }

                radialSelector
                    .frame(maxWidth: .infinity)
                    .frame(height: 258)

                sectionPills
            }
        }
    }

    private var radialSelector: some View {
        ZStack {
            Circle()
                .stroke(Color.white.opacity(0.06), lineWidth: 1)
                .frame(width: 208, height: 208)

            Circle()
                .stroke(Color.white.opacity(0.04), style: StrokeStyle(lineWidth: 18, dash: [4, 12]))
                .frame(width: 154, height: 154)

            Circle()
                .fill(selectedSection.tint.opacity(0.16))
                .blur(radius: 26)
                .frame(width: 156, height: 156)

            centralSelectionCard

            ForEach(StatsSection.allCases) { section in
                orbitButton(for: section)
                    .offset(section.orbitOffset)
            }
        }
    }

    private var centralSelectionCard: some View {
        VStack(spacing: AppSpacing.sm) {
            ZStack {
                Circle()
                    .fill(selectedSection.tint.opacity(0.18))
                    .frame(width: 68, height: 68)

                Image(icon: selectedSection.icon)
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundStyle(selectedSection.tint)
            }

            VStack(spacing: AppSpacing.xxs) {
                Text(selectedSection.title)
                    .font(AppTypography.headline)
                    .foregroundStyle(DashboardWidgetChrome.labelPrimary)

                Text(selectedSection == .exercises ? viewModel.selectedTab.label : "Focused View")
                    .font(AppTypography.caption1)
                    .foregroundStyle(DashboardWidgetChrome.labelSecondary)
            }
        }
        .frame(width: 158, height: 158)
        .background(
            RoundedRectangle(cornerRadius: 36, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.10),
                            selectedSection.tint.opacity(0.08)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 36, style: .continuous)
                .stroke(Color.white.opacity(0.10), lineWidth: 1)
        )
    }

    private func orbitButton(for section: StatsSection) -> some View {
        let isSelected = selectedSection == section
        return Button {
            withAnimation(.spring(response: 0.34, dampingFraction: 0.82)) {
                selectedSection = section
            }
        } label: {
            VStack(spacing: AppSpacing.xxs) {
                Image(icon: section.icon)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(isSelected ? AppColors.textOnPrimary : section.tint)
                    .frame(width: 46, height: 46)
                    .background(isSelected ? AnyShapeStyle(section.tint) : AnyShapeStyle(Color.white.opacity(0.06)), in: Circle())
                    .overlay(
                        Circle()
                            .stroke(Color.white.opacity(isSelected ? 0.0 : 0.10), lineWidth: 1)
                    )

                Text(section.title)
                    .font(AppTypography.caption2)
                    .foregroundStyle(DashboardWidgetChrome.labelSecondary)
            }
        }
        .buttonStyle(.plain)
        .scaleEffect(isSelected ? 1.06 : 1.0)
    }

    private var sectionPills: some View {
        HStack(spacing: AppSpacing.xs) {
            ForEach(StatsSection.allCases) { section in
                Button {
                    withAnimation(.easeInOut(duration: 0.18)) {
                        selectedSection = section
                    }
                } label: {
                    HStack(spacing: AppSpacing.xs) {
                        Image(icon: section.icon)
                            .font(.system(size: 13, weight: .semibold))
                        Text(section.title)
                            .font(AppTypography.captionSemibold)
                    }
                    .foregroundStyle(selectedSection == section ? AppColors.textOnPrimary : section.tint)
                    .padding(.horizontal, AppSpacing.sm)
                    .padding(.vertical, AppSpacing.xs)
                    .background(
                        selectedSection == section ? section.tint : Color.white.opacity(0.05),
                        in: Capsule()
                    )
                    .overlay(
                        Capsule()
                            .stroke(Color.white.opacity(selectedSection == section ? 0.0 : 0.08), lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Section Content

    @ViewBuilder
    private var sectionContent: some View {
        switch selectedSection {
        case .exercises:
            exercisesContent
        case .screenTime:
            screenTimeSectionContent
        case .history:
            EmptyView()
        }
    }

    private var exercisesContent: some View {
        VStack(spacing: AppSpacing.md) {
            exercisePeriodPicker

            switch viewModel.selectedTab {
            case .daily:
                dailyContent
            case .weekly:
                weeklyContent
            case .monthly:
                monthlyContent
            case .total:
                totalContent
            case .screenTime, .history:
                dailyContent
            }
        }
    }

    private var exercisePeriodPicker: some View {
        Card(hasShadow: false) {
            VStack(alignment: .leading, spacing: AppSpacing.sm) {
                Text("Exercise Lens")
                    .font(AppTypography.captionSemibold)
                    .foregroundStyle(DashboardWidgetChrome.labelSecondary)
                    .textCase(.uppercase)

                HStack(spacing: AppSpacing.xs) {
                    ForEach([StatsTab.daily, .weekly, .monthly, .total]) { tab in
                        exercisePeriodChip(tab)
                    }
                }
            }
        }
    }

    private func exercisePeriodChip(_ tab: StatsTab) -> some View {
        let isSelected = viewModel.selectedTab == tab
        return Button {
            withAnimation(.easeInOut(duration: 0.18)) {
                viewModel.selectedTab = tab
            }
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(tab.label)
                    .font(AppTypography.captionSemibold)
                Text(periodSubtitle(for: tab))
                    .font(AppTypography.caption2)
                    .lineLimit(1)
            }
            .foregroundStyle(isSelected ? AppColors.textOnPrimary : DashboardWidgetChrome.labelSecondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, AppSpacing.sm)
            .padding(.vertical, AppSpacing.sm)
            .background(
                isSelected ? AppColors.info : Color.white.opacity(0.05),
                in: RoundedRectangle(cornerRadius: AppSpacing.cornerRadiusButton, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: AppSpacing.cornerRadiusButton, style: .continuous)
                    .stroke(Color.white.opacity(isSelected ? 0.0 : 0.08), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private func periodSubtitle(for tab: StatsTab) -> String {
        switch tab {
        case .daily:      return "Heatmap"
        case .weekly:     return "7-day rhythm"
        case .monthly:    return "Trend arc"
        case .total:      return "Lifetime"
        case .screenTime: return ""
        case .history:    return ""
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

                    Text("Tap an active day to see detailed activity stats.")
                        .font(AppTypography.caption1)
                        .foregroundStyle(DashboardWidgetChrome.labelSecondary)

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
            totalActivityPoints: viewModel.weeklyTotalActivityPoints,
            averageActivityPoints: viewModel.weeklyAverageActivityPoints,
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
            totalActivityPoints: viewModel.monthlyTotalActivityPoints,
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
    private var screenTimeSectionContent: some View {
        VStack(spacing: AppSpacing.md) {
            Card(hasShadow: false) {
                HStack(alignment: .top, spacing: AppSpacing.sm) {
                    ZStack {
                        Circle()
                            .fill(AppColors.secondary.opacity(0.16))
                            .frame(width: 42, height: 42)

                        Image(icon: .hourglassFill)
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(AppColors.secondary)
                    }

                    VStack(alignment: .leading, spacing: AppSpacing.xxs) {
                        Text("Screen Time stays separate from workout performance.")
                            .font(AppTypography.bodySemibold)
                            .foregroundStyle(DashboardWidgetChrome.labelPrimary)

                        Text("That way the page feels cleaner and you always know whether you're looking at training output or phone usage.")
                            .font(AppTypography.caption1)
                            .foregroundStyle(DashboardWidgetChrome.labelSecondary)
                    }

                    Spacer()
                }
            }

            ScreenTimeStatsInlineView()
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
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(AppColors.primary)
                    .frame(width: 38, height: 38)
                    .background(Color.white.opacity(0.06), in: Circle())
                    .overlay(
                        Circle()
                            .stroke(Color.white.opacity(0.08), lineWidth: 1)
                    )
            }
            .buttonStyle(ScaleButtonStyle())
            .accessibilityLabel("Export Stats")
            .disabled(selectedSection != .exercises)
        }
    }

    private func streakBadge(days: Int) -> some View {
        HStack(spacing: AppSpacing.xxs) {
            Image(systemName: AppIcon.flameFill.rawValue)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(AppColors.secondary)

            Text("\(days)")
                .font(AppTypography.captionSemibold)
                .foregroundStyle(DashboardWidgetChrome.labelPrimary)
        }
        .padding(.horizontal, AppSpacing.xs)
        .padding(.vertical, AppSpacing.xxs)
        .background(Color.white.opacity(0.06), in: Capsule())
        .overlay(
            Capsule()
                .stroke(Color.white.opacity(0.10), lineWidth: 1)
        )
    }

    // MARK: - Export Actions

    private func exportCSV() {
        // TODO: Implement CSV export via KMP shared module or local generation.
        // For now, show a placeholder share sheet.
        let csvContent = generateCSVContent()
        shareContent(csvContent, filename: "activity_stats.csv")
    }

    private func exportPDF() {
        // PDF export requires UIGraphicsPDFRenderer integration.
        // For now, fall back to CSV export with a user-facing note.
        viewModel.errorMessage = "PDF export is not yet available. Use CSV export instead."
    }

    private func generateCSVContent() -> String {
        var lines = ["Date,Activity XP,Sessions,Earned Minutes,Quality"]
        for day in viewModel.calendarDays where day.hasWorkout {
            // Use the stable ISO date id ("yyyy-MM-dd") for unambiguous CSV output.
            let quality = String(format: "%.0f", day.averageQuality * 100)
            lines.append("\(day.id),\(day.activityPoints),\(day.sessions),\(day.earnedMinutes),\(quality)")
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
