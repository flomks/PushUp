import SwiftUI

// MARK: - DashboardView

/// Main Dashboard screen showing time credit, daily stats, weekly chart,
/// last session summary, and a "Workout starten" quick-action button.
///
/// Supports pull-to-refresh and renders appropriate empty / loading states.
/// Navigation to the Workout tab is handled via the `selectedTab` binding
/// passed in from `MainTabView`.
///
/// Widgets can be reordered, removed, and added. Layout is stored in
/// `UserSettings` (local SQLite + Supabase `user_settings`), like other account settings.
///
/// Grids (1×2 and 2×2) allow placing compact stat widgets side by side.
struct DashboardView: View {

    @ObservedObject var viewModel: DashboardViewModel
    @ObservedObject var layoutStore: DashboardLayoutStore

    /// Binding to the parent `TabView` selection so the "Workout starten"
    /// button can switch tabs without pushing a new navigation destination.
    @Binding var selectedTab: Tab

    @State private var editMode: EditMode = .inactive
    @State private var showTimeCreditDetail = false
    @State private var showAddWidgetSheet = false
    @State private var isDraggingWidget = false
    @State private var dashboardScrollView: UIScrollView? = nil
    @State private var gridSlotSelection: GridSlotSelection?

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

            scrollContent
        }
        .preferredColorScheme(.dark)
        .navigationTitle("Dashboard")
        .navigationBarTitleDisplayMode(.large)
        .toolbarBackground(DashboardWidgetChrome.pageBackground, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .environment(\.editMode, $editMode)
        .toolbar { dashboardToolbar }
        .task { await viewModel.startObserving() }
        .onAppear {
            if !viewModel.currentUserId.isEmpty {
                layoutStore.startObserving(userId: viewModel.currentUserId)
            }
        }
        .onChange(of: viewModel.currentUserId) { _, newId in
            if newId.isEmpty {
                layoutStore.stopObserving()
            } else {
                layoutStore.startObserving(userId: newId)
            }
        }
        .onChange(of: editMode) { _, newValue in
            if newValue.isEditing {
                DashboardHaptics.mediumImpact()
            } else {
                layoutStore.finishDebouncedPersistIfScheduled()
                DashboardHaptics.lightImpact()
            }
        }
        .sheet(isPresented: $showTimeCreditDetail) {
            TimeCreditDetailView(
                availableSeconds: viewModel.availableSeconds,
                dailyEarnedSeconds: viewModel.dailyEarnedSeconds,
                dailySpentSeconds: viewModel.dailySpentSeconds,
                todayWorkoutEarned: viewModel.todayWorkoutEarned,
                carryOverPercentSeconds: viewModel.carryOverPercentSeconds,
                carryOverLateNightSeconds: viewModel.carryOverLateNightSeconds,
                totalEarnedSeconds: viewModel.totalEarnedSeconds,
                totalSpentSeconds: viewModel.totalSpentSeconds,
                userId: viewModel.currentUserId
            )
        }
        .sheet(isPresented: $showAddWidgetSheet) {
            DashboardAddWidgetsSheet(layoutStore: layoutStore)
        }
        .sheet(item: $gridSlotSelection) { selection in
            GridSlotPickerSheet(
                layoutStore: layoutStore,
                gridId: selection.gridId,
                slotIndex: selection.slotIndex
            )
        }
        .alert("Error", isPresented: showError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
    }

    // MARK: - Scroll Content

    private var scrollContent: some View {
        dashboardList
    }

    private var dashboardList: some View {
        ScrollView {
            VStack(spacing: 0) {
                Color.clear.frame(height: AppSpacing.sm)

                if layoutStore.orderedItems.isEmpty {
                    emptyDashboardCard
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, AppSpacing.md)
                        .padding(.bottom, AppSpacing.md)
                } else {
                    ReorderableWidgetList(
                        items: $layoutStore.orderedItems,
                        isDragging: $isDraggingWidget,
                        isEditing: editMode.isEditing,
                        onPersist: { layoutStore.schedulePersistAfterReorder() },
                        onDelete: { index in
                            layoutStore.removeItem(at: index)
                            DashboardHaptics.mediumImpact()
                        },
                        onEdgeScroll: { delta in
                            guard let sv = dashboardScrollView else { return 0 }
                            let oldY = sv.contentOffset.y
                            let minY = -sv.adjustedContentInset.top
                            let maxY = max(minY, sv.contentSize.height - sv.bounds.height + sv.adjustedContentInset.bottom)
                            let newY = max(minY, min(oldY + delta, maxY))
                            sv.setContentOffset(CGPoint(x: 0, y: newY), animated: false)
                            return newY - oldY
                        },
                        listGlobalOriginY: {
                            guard let sv = dashboardScrollView else { return 0 }
                            return sv.convert(CGPoint(x: 0, y: AppSpacing.sm), to: nil).y
                        }
                    ) { item in
                        itemView(for: item)
                    }
                }

                Color.clear.frame(height: AppSpacing.screenVerticalBottom)
            }
            .background(
                UIScrollViewAccessor { sv in dashboardScrollView = sv }
                    .frame(width: 0, height: 0)
            )
        }
        .scrollDisabled(isDraggingWidget)
        .background(DashboardWidgetChrome.pageBackground)
        .environment(\.editMode, $editMode)
        .refreshable {
            await viewModel.refresh()
        }
    }

    // MARK: - Empty Dashboard

    private var emptyDashboardCard: some View {
        VStack(spacing: AppSpacing.md) {
            Image(systemName: "plus.circle.fill")
                .font(.system(size: 44))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(DashboardWidgetChrome.labelSecondary)

            VStack(alignment: .leading, spacing: AppSpacing.sm) {
                Label("No widgets on your dashboard", icon: .rectangleStackFill)
                    .font(AppTypography.headline)
                    .foregroundStyle(DashboardWidgetChrome.labelPrimary)

                Text("Add cards with the button below or the + button in the top bar.")
                    .font(AppTypography.subheadline)
                    .foregroundStyle(DashboardWidgetChrome.labelSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            PrimaryButton("Add widgets", icon: .plus) {
                DashboardHaptics.mediumImpact()
                showAddWidgetSheet = true
            }
        }
        .padding(DashboardWidgetChrome.padding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .dashboardWidgetChrome()
        .padding(.horizontal, AppSpacing.screenHorizontal)
    }

    // MARK: - Item View Dispatch

    @ViewBuilder
    private func itemView(for item: DashboardItem) -> some View {
        switch item {
        case .widget(let kind):
            widgetView(for: kind)
        case .grid(_, let size, let slots):
            DashboardGridWidget(
                size: size,
                slots: slots,
                isEditing: editMode.isEditing,
                onAddToSlot: { slotIndex in
                    gridSlotSelection = GridSlotSelection(gridId: item.id, slotIndex: slotIndex)
                },
                onRemoveFromSlot: { slotIndex in
                    layoutStore.clearGridSlot(gridId: item.id, slotIndex: slotIndex)
                }
            ) { kind in
                gridCellView(for: kind)
            }
        }
    }

    // MARK: - Widgets (full-size)

    @ViewBuilder
    private func widgetView(for kind: DashboardWidgetKind) -> some View {
        switch kind {
        case .timeCredit:
            DashboardTimeCreditCard(
                availableSeconds: viewModel.availableSeconds,
                dailyEarnedSeconds: viewModel.dailyEarnedSeconds,
                totalEarnedSeconds: viewModel.totalEarnedSeconds,
                isLoading: viewModel.isLoading,
                onTap: { showTimeCreditDetail = true }
            )
        case .screenTime:
            ScreenTimeStatusCard()
        case .dailyStats:
            DailyStatsCard(
                stats: viewModel.dailyStats,
                isLoading: viewModel.isLoading
            )
        case .weeklyChart:
            WeeklyChart(
                days: viewModel.weekDays,
                isLoading: viewModel.isLoading,
                weekOverWeekPercent: viewModel.weekSessionTrendPercent
            )
        case .activitySummary:
            if viewModel.hasEverWorkedOut {
                lastSessionSection
            } else {
                emptyStateSection
            }
        case .workoutQuickAction:
            workoutStartButton
        case .upcomingRuns:
            upcomingRunsWidget

        case .pushUpsThisWeek:
            DashboardMiniStatWidget(
                title: kind.title,
                systemImage: kind.systemImage,
                value: "\(viewModel.widgetMetrics.pushUpsWeek)",
                subtitle: "This calendar week",
                footnote: "Strength workouts only"
            )
        case .pushUpsThisMonth:
            DashboardMiniStatWidget(
                title: kind.title,
                systemImage: kind.systemImage,
                value: "\(viewModel.widgetMetrics.pushUpsMonth)",
                subtitle: "Current calendar month",
                footnote: "Strength workouts only"
            )
        case .pushUpsAllTime:
            DashboardMiniStatWidget(
                title: kind.title,
                systemImage: kind.systemImage,
                value: "\(viewModel.widgetMetrics.pushUpsAllTime)",
                subtitle: "Lifetime total reps"
            )
        case .pushUpSessionsWeek:
            DashboardMiniStatWidget(
                title: kind.title,
                systemImage: kind.systemImage,
                value: "\(viewModel.widgetMetrics.pushUpSessionsWeek)",
                subtitle: "Completed strength sessions"
            )
        case .bestPushUpSession:
            DashboardMiniStatWidget(
                title: kind.title,
                systemImage: kind.systemImage,
                value: viewModel.widgetMetrics.bestPushUpSession > 0
                    ? "\(viewModel.widgetMetrics.bestPushUpSession)"
                    : "—",
                subtitle: "Single session record"
            )
        case .averageFormWeek:
            DashboardMiniStatWidget(
                title: kind.title,
                systemImage: kind.systemImage,
                value: DashboardMetricFormatting.percentString(viewModel.widgetMetrics.averageFormWeek),
                subtitle: "Average form score this week"
            )
        case .streakCurrent:
            DashboardMiniStatWidget(
                title: kind.title,
                systemImage: kind.systemImage,
                value: "\(viewModel.widgetMetrics.streakCurrentDays)",
                subtitle: "Days in a row with activity",
                footnote: "Push-ups or runs"
            )
        case .streakBest:
            DashboardMiniStatWidget(
                title: kind.title,
                systemImage: kind.systemImage,
                value: "\(viewModel.widgetMetrics.streakLongestDays)",
                subtitle: "Longest run of active days"
            )

        case .runDistanceToday:
            DashboardMiniStatWidget(
                title: kind.title,
                systemImage: kind.systemImage,
                value: DashboardMetricFormatting.distanceLabel(meters: viewModel.widgetMetrics.runDistanceTodayMeters),
                subtitle: "Jogging today"
            )
        case .runDistanceWeek:
            DashboardMiniStatWidget(
                title: kind.title,
                systemImage: kind.systemImage,
                value: DashboardMetricFormatting.distanceLabel(meters: viewModel.widgetMetrics.runDistanceWeekMeters),
                subtitle: "This calendar week"
            )
        case .runDistanceMonth:
            DashboardMiniStatWidget(
                title: kind.title,
                systemImage: kind.systemImage,
                value: DashboardMetricFormatting.distanceLabel(meters: viewModel.widgetMetrics.runDistanceMonthMeters),
                subtitle: "This calendar month"
            )
        case .runDistanceAllTime:
            DashboardMiniStatWidget(
                title: kind.title,
                systemImage: kind.systemImage,
                value: DashboardMetricFormatting.distanceLabel(meters: viewModel.widgetMetrics.runDistanceAllTimeMeters),
                subtitle: "All completed runs"
            )
        case .runSessionsWeek:
            DashboardMiniStatWidget(
                title: kind.title,
                systemImage: kind.systemImage,
                value: "\(viewModel.widgetMetrics.runSessionsWeek)",
                subtitle: "Completed runs this week"
            )

        case .creditEarnedToday:
            DashboardMiniStatWidget(
                title: kind.title,
                systemImage: kind.systemImage,
                value: DashboardMetricFormatting.minutesFromSeconds(viewModel.dailyEarnedSeconds),
                subtitle: "Time credit earned today"
            )
        case .creditSpentToday:
            DashboardMiniStatWidget(
                title: kind.title,
                systemImage: kind.systemImage,
                value: DashboardMetricFormatting.minutesFromSeconds(viewModel.dailySpentSeconds),
                subtitle: "Against your daily budget"
            )
        case .creditTotalEarned:
            DashboardMiniStatWidget(
                title: kind.title,
                systemImage: kind.systemImage,
                value: DashboardMetricFormatting.hoursMinutesFromSeconds(viewModel.totalEarnedSeconds),
                subtitle: "Lifetime earned"
            )
        case .creditLifetimeSpent:
            DashboardMiniStatWidget(
                title: kind.title,
                systemImage: kind.systemImage,
                value: DashboardMetricFormatting.hoursMinutesFromSeconds(viewModel.totalSpentSeconds),
                subtitle: "Screen time spent (tracked)"
            )

        case .activeMinutesWeek:
            DashboardMiniStatWidget(
                title: kind.title,
                systemImage: kind.systemImage,
                value: "\(viewModel.widgetMetrics.activeMinutesWeek) min",
                subtitle: "Push-ups + runs combined"
            )
        case .allSessionsWeek:
            DashboardMiniStatWidget(
                title: kind.title,
                systemImage: kind.systemImage,
                value: "\(viewModel.widgetMetrics.totalSessionsWeek)",
                subtitle: "Strength + run sessions"
            )

        case .shortcutStats:
            DashboardShortcutWidget(title: kind.title, systemImage: kind.systemImage, tab: .stats, selectedTab: $selectedTab)
        case .shortcutProfile:
            DashboardShortcutWidget(title: kind.title, systemImage: kind.systemImage, tab: .profile, selectedTab: $selectedTab)
        case .shortcutFriends:
            DashboardShortcutWidget(title: kind.title, systemImage: kind.systemImage, tab: .friends, selectedTab: $selectedTab)
        case .shortcutSettings:
            DashboardShortcutWidget(title: kind.title, systemImage: kind.systemImage, tab: .settings, selectedTab: $selectedTab)
        default:
            EmptyView()
        }
    }

    // MARK: - Grid Cells (compact)

    @ViewBuilder
    private func gridCellView(for kind: DashboardWidgetKind) -> some View {
        switch kind {
        // Push-ups & strength
        case .pushUpsThisWeek:
            GridMiniStatCell(title: "Push-ups", systemImage: kind.systemImage,
                             value: "\(viewModel.widgetMetrics.pushUpsWeek)", subtitle: "This week")
        case .pushUpsThisMonth:
            GridMiniStatCell(title: "Push-ups", systemImage: kind.systemImage,
                             value: "\(viewModel.widgetMetrics.pushUpsMonth)", subtitle: "This month")
        case .pushUpsAllTime:
            GridMiniStatCell(title: "Push-ups", systemImage: kind.systemImage,
                             value: "\(viewModel.widgetMetrics.pushUpsAllTime)", subtitle: "All time")
        case .pushUpSessionsWeek:
            GridMiniStatCell(title: "Sessions", systemImage: kind.systemImage,
                             value: "\(viewModel.widgetMetrics.pushUpSessionsWeek)", subtitle: "Strength / week")
        case .bestPushUpSession:
            GridMiniStatCell(title: "Best session", systemImage: kind.systemImage,
                             value: viewModel.widgetMetrics.bestPushUpSession > 0
                                ? "\(viewModel.widgetMetrics.bestPushUpSession)" : "—",
                             subtitle: "Reps record")
        case .averageFormWeek:
            GridMiniStatCell(title: "Avg form", systemImage: kind.systemImage,
                             value: DashboardMetricFormatting.percentString(viewModel.widgetMetrics.averageFormWeek),
                             subtitle: "This week")
        case .streakCurrent:
            GridMiniStatCell(title: "Streak", systemImage: kind.systemImage,
                             value: "\(viewModel.widgetMetrics.streakCurrentDays)", subtitle: "Current days")
        case .streakBest:
            GridMiniStatCell(title: "Best streak", systemImage: kind.systemImage,
                             value: "\(viewModel.widgetMetrics.streakLongestDays)", subtitle: "Record days")

        // Running
        case .runDistanceToday:
            GridMiniStatCell(title: "Run today", systemImage: kind.systemImage,
                             value: DashboardMetricFormatting.distanceLabel(meters: viewModel.widgetMetrics.runDistanceTodayMeters))
        case .runDistanceWeek:
            GridMiniStatCell(title: "Run week", systemImage: kind.systemImage,
                             value: DashboardMetricFormatting.distanceLabel(meters: viewModel.widgetMetrics.runDistanceWeekMeters))
        case .runDistanceMonth:
            GridMiniStatCell(title: "Run month", systemImage: kind.systemImage,
                             value: DashboardMetricFormatting.distanceLabel(meters: viewModel.widgetMetrics.runDistanceMonthMeters))
        case .runDistanceAllTime:
            GridMiniStatCell(title: "Run total", systemImage: kind.systemImage,
                             value: DashboardMetricFormatting.distanceLabel(meters: viewModel.widgetMetrics.runDistanceAllTimeMeters))
        case .runSessionsWeek:
            GridMiniStatCell(title: "Runs", systemImage: kind.systemImage,
                             value: "\(viewModel.widgetMetrics.runSessionsWeek)", subtitle: "This week")

        // Time credit compact
        case .creditEarnedToday:
            GridMiniStatCell(title: "Earned", systemImage: kind.systemImage,
                             value: DashboardMetricFormatting.minutesFromSeconds(viewModel.dailyEarnedSeconds), subtitle: "Today")
        case .creditSpentToday:
            GridMiniStatCell(title: "Spent", systemImage: kind.systemImage,
                             value: DashboardMetricFormatting.minutesFromSeconds(viewModel.dailySpentSeconds), subtitle: "Today")
        case .creditTotalEarned:
            GridMiniStatCell(title: "Total earned", systemImage: kind.systemImage,
                             value: DashboardMetricFormatting.hoursMinutesFromSeconds(viewModel.totalEarnedSeconds))
        case .creditLifetimeSpent:
            GridMiniStatCell(title: "Total spent", systemImage: kind.systemImage,
                             value: DashboardMetricFormatting.hoursMinutesFromSeconds(viewModel.totalSpentSeconds))

        // Combined
        case .activeMinutesWeek:
            GridMiniStatCell(title: "Active", systemImage: kind.systemImage,
                             value: "\(viewModel.widgetMetrics.activeMinutesWeek) min", subtitle: "This week")
        case .allSessionsWeek:
            GridMiniStatCell(title: "Sessions", systemImage: kind.systemImage,
                             value: "\(viewModel.widgetMetrics.totalSessionsWeek)", subtitle: "All types / week")

        // Shortcuts
        case .shortcutStats:
            GridShortcutCell(title: kind.title, systemImage: kind.systemImage, tab: .stats, selectedTab: $selectedTab)
        case .shortcutProfile:
            GridShortcutCell(title: kind.title, systemImage: kind.systemImage, tab: .profile, selectedTab: $selectedTab)
        case .shortcutFriends:
            GridShortcutCell(title: kind.title, systemImage: kind.systemImage, tab: .friends, selectedTab: $selectedTab)
        case .shortcutSettings:
            GridShortcutCell(title: kind.title, systemImage: kind.systemImage, tab: .settings, selectedTab: $selectedTab)

        // Full-size widgets should not appear in grids, but handle gracefully
        default:
            GridMiniStatCell(title: kind.title, systemImage: kind.systemImage, value: "—")
        }
    }

    // MARK: - Last Session Section

    private var upcomingRunsWidget: some View {
        let visibleRuns = Array(viewModel.upcomingRuns.prefix(3))

        return VStack(alignment: .leading, spacing: AppSpacing.md) {
            HStack {
                HStack(spacing: 10) {
                    Image(systemName: "calendar")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(Color.white.opacity(0.42))

                    Text("Upcoming Runs")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(.white)
                }

                Spacer()

                HStack(spacing: 12) {
                    Text("\(viewModel.upcomingRuns.count)")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Color.white.opacity(0.42))

                    Button {
                        selectedTab = .workout
                        NotificationCenter.default.post(name: .openRunningFromDashboard, object: nil)
                    } label: {
                        Text("Running")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(Color.white.opacity(0.82))
                            .padding(.horizontal, 9)
                            .padding(.vertical, 5)
                            .background(AppColors.secondary.opacity(0.72), in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }

            if viewModel.upcomingRuns.isEmpty {
                VStack(alignment: .leading, spacing: AppSpacing.xs) {
                    Text("No planned runs yet.")
                        .font(AppTypography.bodySemibold)
                        .foregroundStyle(.white)
                    Text("Schedule a solo or crew run from the running screen.")
                        .font(AppTypography.caption1)
                        .foregroundStyle(Color.white.opacity(0.46))
                }
            } else {
                VStack(spacing: AppSpacing.sm) {
                    ForEach(Array(visibleRuns.enumerated()), id: \.element.id) { index, run in
                        upcomingRunRow(
                            run,
                            showsConnector: index != visibleRuns.count - 1
                        )
                    }
                }
            }
        }
        .padding(20)
        .background(Color(red: 0.06, green: 0.06, blue: 0.06), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.white.opacity(0.10), lineWidth: 1)
        )
    }

    private func upcomingRunRow(_ run: DashboardUpcomingRun, showsConnector: Bool) -> some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(spacing: 0) {
                Circle()
                    .fill(Color.white.opacity(0.20))
                    .frame(width: 16, height: 16)
                    .overlay(Circle().stroke(Color.white.opacity(0.40), lineWidth: 2))

                if showsConnector {
                    Rectangle()
                        .fill(Color.white.opacity(0.10))
                        .frame(width: 1, height: 64)
                        .padding(.top, 4)
                }
            }
            .frame(width: 16)

            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .top) {
                    Text(run.title)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)

                    Spacer(minLength: 12)

                    HStack(spacing: 4) {
                        Image(systemName: participantIconName(for: run.participantCount))
                            .font(.system(size: 12, weight: .medium))
                        Text("\(run.participantCount)")
                            .font(.system(size: 12, weight: .medium))
                    }
                    .foregroundStyle(Color.white.opacity(0.40))
                }

                Text(Self.dashboardUpcomingRunDateFormatter.string(from: run.plannedStartAt))
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Color.white.opacity(0.40))

                HStack(spacing: 8) {
                    HStack(spacing: 6) {
                        Image(systemName: "figure.run")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(Color.white.opacity(0.40))
                        Text(upcomingRunStatusLabel(run))
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(Color.white.opacity(0.60))
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color.white.opacity(0.05), in: Capsule())
                }
            }
        }
    }

    private func participantIconName(for count: Int) -> String {
        count <= 1 ? "person" : "person.2"
    }

    private func upcomingRunStatusLabel(_ run: DashboardUpcomingRun) -> String {
        if let status = run.currentUserStatus?.replacingOccurrences(of: "_", with: " ").capitalized,
           !status.isEmpty {
            return status
        }
        return run.visibility.uppercased() == "PRIVATE" ? "Solo Event" : "Crew Event"
    }

    @ViewBuilder
    private var lastSessionSection: some View {
        if let session = viewModel.lastSession {
            VStack(alignment: .leading, spacing: AppSpacing.sm) {

                HStack {
                    Label("Last Session", icon: .clockArrowCirclepath)
                        .font(AppTypography.headline)
                        .foregroundStyle(DashboardWidgetChrome.labelPrimary)

                    Spacer()

                    Text(session.relativeDate)
                        .font(AppTypography.caption1)
                        .foregroundStyle(DashboardWidgetChrome.labelSecondary)
                }

                Rectangle()
                    .fill(Color.white.opacity(0.1))
                    .frame(height: 1)

                lastSessionMetrics(session)
            }
            .padding(DashboardWidgetChrome.padding)
            .dashboardWidgetChrome()
        }
    }

    @ViewBuilder
    private func lastSessionMetrics(_ session: DashboardLastSession) -> some View {
        VStack(spacing: AppSpacing.sm) {
            VStack(spacing: AppSpacing.xxs) {
                Image(systemName: session.primaryMetricIcon.rawValue)
                    .font(.system(size: AppSpacing.iconSizeStandard, weight: .semibold))
                    .foregroundStyle(DashboardWidgetChrome.labelSecondary)

                Text(session.primaryMetricValue)
                    .font(AppTypography.displayMedium)
                    .foregroundStyle(DashboardWidgetChrome.labelPrimary)

                Text(session.primaryMetricLabel)
                    .font(AppTypography.caption1)
                    .foregroundStyle(DashboardWidgetChrome.labelSecondary)
            }

            HStack {
                metricItem(
                    icon: .clock,
                    value: formatDuration(session.durationSeconds),
                    label: "Duration",
                    tint: Color.white.opacity(0.65)
                )

                sessionColumnDivider

                metricItem(
                    icon: .boltFill,
                    value: "+\(session.earnedSeconds / 60) min",
                    label: "Earned",
                    tint: DashboardWidgetChrome.accentPositive
                )

                sessionColumnDivider

                metricItem(
                    icon: .starFill,
                    value: session.qualityScore > 0
                        ? String(format: "%.0f%%", session.qualityScore * 100)
                        : "--",
                    label: "Quality",
                    tint: AppColors.formScoreColor(session.qualityScore)
                )
            }
        }
    }

    @ViewBuilder
    private func metricItem(
        icon: AppIcon,
        value: String,
        label: String,
        tint: Color
    ) -> some View {
        VStack(spacing: AppSpacing.xxs) {
            Image(systemName: icon.rawValue)
                .font(.system(size: AppSpacing.iconSizeStandard, weight: .semibold))
                .foregroundStyle(tint)

            Text(value)
                .font(AppTypography.bodySemibold)
                .foregroundStyle(DashboardWidgetChrome.labelPrimary)

            Text(label)
                .font(AppTypography.caption1)
                .foregroundStyle(DashboardWidgetChrome.labelSecondary)
        }
        .frame(maxWidth: .infinity)
    }

    private var sessionColumnDivider: some View {
        Rectangle()
            .fill(Color.white.opacity(0.1))
            .frame(width: 1, height: 36)
    }

    private func formatDuration(_ seconds: Int) -> String {
        let m = seconds / 60
        let s = seconds % 60
        return String(format: "%d:%02d", m, s)
    }

    // MARK: - Empty State

    @ViewBuilder
    private var emptyStateSection: some View {
        VStack(spacing: AppSpacing.md) {
            Image(systemName: AppIcon.figureRun.rawValue)
                .font(.system(size: AppSpacing.iconSizeXL, weight: .light))
                .foregroundStyle(DashboardWidgetChrome.labelMuted)

            VStack(spacing: AppSpacing.xs) {
                Text("Start your first activity!")
                    .font(AppTypography.headline)
                    .foregroundStyle(DashboardWidgetChrome.labelPrimary)
                    .multilineTextAlignment(.center)

                Text("Track workouts or running and earn time credit for screen time.")
                    .font(AppTypography.body)
                    .foregroundStyle(DashboardWidgetChrome.labelSecondary)
                    .multilineTextAlignment(.center)
            }

            PrimaryButton("Choose Workout", icon: .figureStrengthTraining) {
                selectedTab = .workout
            }
            .padding(.top, AppSpacing.xs)
        }
        .padding(.vertical, AppSpacing.lg)
        .padding(.horizontal, AppSpacing.md)
        .frame(maxWidth: .infinity)
        .dashboardWidgetChrome()
    }

    // MARK: - Workout Start Button

    private var workoutStartButton: some View {
        PrimaryButton(
            "Choose Workout",
            icon: .figureStrengthTraining
        ) {
            selectedTab = .workout
        }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var dashboardToolbar: some ToolbarContent {
        ToolbarItem(placement: .navigationBarLeading) {
            Button {
                DashboardHaptics.lightImpact()
                withAnimation(.easeInOut(duration: 0.2)) {
                    editMode = editMode.isEditing ? .inactive : .active
                }
            } label: {
                Text(editMode.isEditing ? "Done" : "Edit")
                    .fontWeight(.semibold)
            }
            .accessibilityLabel(editMode.isEditing ? "Done editing dashboard" : "Edit dashboard layout")
        }

        ToolbarItemGroup(placement: .navigationBarTrailing) {
            Button {
                DashboardHaptics.lightImpact()
                showAddWidgetSheet = true
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(AppColors.primary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Add widget")

            SyncIndicator()
        }
    }
}

private extension DashboardView {
    static let dashboardUpcomingRunDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE, MMM d • HH:mm"
        formatter.locale = Locale(identifier: "en_US")
        return formatter
    }()
}

// MARK: - GridSlotSelection

struct GridSlotSelection: Identifiable {
    let gridId: String
    let slotIndex: Int
    var id: String { "\(gridId)-\(slotIndex)" }
}

// MARK: - Add Widgets Sheet

private struct DashboardAddWidgetsSheet: View {

    @ObservedObject var layoutStore: DashboardLayoutStore
    @Environment(\.dismiss) private var dismiss

    private var availableKinds: [DashboardWidgetKind] {
        let used = layoutStore.allUsedWidgetKinds
        return DashboardWidgetKind.allCases
            .filter { !used.contains($0) }
            .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
    }

    private var allSlotsOccupied: Bool {
        availableKinds.isEmpty
    }

    var body: some View {
        NavigationStack {
            List {
                // Grids section
                Section {
                    ForEach(DashboardGridSize.allCases, id: \.self) { size in
                        Button {
                            layoutStore.addGrid(size)
                            DashboardHaptics.success()
                            dismiss()
                        } label: {
                            HStack(spacing: AppSpacing.md) {
                                Image(systemName: size.systemImage)
                                    .font(.title2)
                                    .foregroundStyle(AppColors.primary)
                                    .frame(width: 36, alignment: .center)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(size.title)
                                        .font(AppTypography.bodySemibold)
                                        .foregroundStyle(AppColors.textPrimary)
                                    Text(size.subtitle)
                                        .font(AppTypography.caption1)
                                        .foregroundStyle(AppColors.textSecondary)
                                }
                                Spacer(minLength: 0)
                                Image(systemName: "plus.circle.fill")
                                    .font(.title3)
                                    .symbolRenderingMode(.hierarchical)
                                    .foregroundStyle(AppColors.primary)
                            }
                            .padding(DashboardWidgetChrome.padding)
                            .contentShape(Rectangle())
                            .dashboardWidgetChrome(cornerRadius: AppSpacing.cornerRadiusCard)
                        }
                        .buttonStyle(.plain)
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                    }
                } header: {
                    Text("Grids")
                        .font(AppTypography.captionSemibold)
                        .foregroundStyle(DashboardWidgetChrome.labelSecondary)
                }

                // Widgets section
                if !availableKinds.isEmpty {
                    Section {
                        ForEach(availableKinds, id: \.self) { kind in
                            Button {
                                layoutStore.addWidget(kind)
                                DashboardHaptics.success()
                                dismiss()
                            } label: {
                                HStack(spacing: AppSpacing.md) {
                                    Image(systemName: kind.systemImage)
                                        .font(.title2)
                                        .foregroundStyle(AppColors.primary)
                                        .frame(width: 36, alignment: .center)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(kind.title)
                                            .font(AppTypography.bodySemibold)
                                            .foregroundStyle(AppColors.textPrimary)
                                        Text("Tap to add")
                                            .font(AppTypography.caption1)
                                            .foregroundStyle(AppColors.textSecondary)
                                    }
                                    Spacer(minLength: 0)
                                Image(systemName: "plus.circle.fill")
                                    .font(.title3)
                                    .symbolRenderingMode(.hierarchical)
                                    .foregroundStyle(AppColors.primary)
                            }
                            .padding(DashboardWidgetChrome.padding)
                            .contentShape(Rectangle())
                            .dashboardWidgetChrome(cornerRadius: AppSpacing.cornerRadiusCard)
                        }
                        .buttonStyle(.plain)
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                    }
                } header: {
                    Text("Widgets")
                        .font(AppTypography.captionSemibold)
                        .foregroundStyle(DashboardWidgetChrome.labelSecondary)
                }
                } else {
                    Section {
                        ContentUnavailableView(
                            "All widgets placed",
                            systemImage: "checkmark.circle",
                            description: Text("Remove a widget to add it back here.")
                        )
                        .foregroundStyle(DashboardWidgetChrome.labelPrimary, DashboardWidgetChrome.labelSecondary)
                    }
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(DashboardWidgetChrome.pageBackground)
            .navigationTitle("Add widget")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(DashboardWidgetChrome.pageBackground, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        DashboardHaptics.lightImpact()
                        dismiss()
                    }
                    .foregroundStyle(AppColors.primary)
                }
            }
        }
        .preferredColorScheme(.dark)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(28)
        .presentationBackground(DashboardWidgetChrome.pageBackground)
    }
}

// MARK: - Grid Slot Picker Sheet

private struct GridSlotPickerSheet: View {

    @ObservedObject var layoutStore: DashboardLayoutStore
    let gridId: String
    let slotIndex: Int
    @Environment(\.dismiss) private var dismiss

    private var availableKinds: [DashboardWidgetKind] {
        let used = layoutStore.allUsedWidgetKinds
        return DashboardWidgetKind.allCases
            .filter { $0.isGridEligible && !used.contains($0) }
            .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
    }

    var body: some View {
        NavigationStack {
            Group {
                if availableKinds.isEmpty {
                    ContentUnavailableView(
                        "No widgets available",
                        systemImage: "square.grid.2x2",
                        description: Text("All compact widgets are already placed. Remove one to free a slot.")
                    )
                    .foregroundStyle(DashboardWidgetChrome.labelPrimary, DashboardWidgetChrome.labelSecondary)
                } else {
                    List(availableKinds, id: \.self) { kind in
                        Button {
                            layoutStore.setGridSlot(gridId: gridId, slotIndex: slotIndex, kind: kind)
                            DashboardHaptics.success()
                            dismiss()
                        } label: {
                            HStack(spacing: AppSpacing.md) {
                                Image(systemName: kind.systemImage)
                                    .font(.title2)
                                    .foregroundStyle(AppColors.primary)
                                    .frame(width: 36, alignment: .center)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(kind.title)
                                        .font(AppTypography.bodySemibold)
                                        .foregroundStyle(AppColors.textPrimary)
                                    Text("Tap to place")
                                        .font(AppTypography.caption1)
                                        .foregroundStyle(AppColors.textSecondary)
                                }
                                Spacer(minLength: 0)
                                Image(systemName: "plus.circle.fill")
                                    .font(.title3)
                                    .symbolRenderingMode(.hierarchical)
                                    .foregroundStyle(AppColors.primary)
                            }
                            .padding(DashboardWidgetChrome.padding)
                            .contentShape(Rectangle())
                            .dashboardWidgetChrome(cornerRadius: AppSpacing.cornerRadiusCard)
                        }
                        .buttonStyle(.plain)
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                    }
                    .listStyle(.insetGrouped)
                    .scrollContentBackground(.hidden)
                }
            }
            .background(DashboardWidgetChrome.pageBackground)
            .navigationTitle("Choose widget")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(DashboardWidgetChrome.pageBackground, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        DashboardHaptics.lightImpact()
                        dismiss()
                    }
                    .foregroundStyle(AppColors.primary)
                }
            }
        }
        .preferredColorScheme(.dark)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(28)
        .presentationBackground(DashboardWidgetChrome.pageBackground)
    }
}

// MARK: - UIScrollViewAccessor

private struct UIScrollViewAccessor: UIViewRepresentable {
    let onFound: (UIScrollView) -> Void

    func makeUIView(context: Context) -> FinderView { FinderView(onFound: onFound) }
    func updateUIView(_ uiView: FinderView, context: Context) {}

    final class FinderView: UIView {
        private let onFound: (UIScrollView) -> Void

        init(onFound: @escaping (UIScrollView) -> Void) {
            self.onFound = onFound
            super.init(frame: .zero)
            backgroundColor = .clear
            isUserInteractionEnabled = false
        }
        required init?(coder: NSCoder) { fatalError() }

        override func didMoveToWindow() {
            super.didMoveToWindow()
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                var view: UIView? = superview
                while let v = view {
                    if let sv = v as? UIScrollView {
                        onFound(sv)
                        return
                    }
                    view = v.superview
                }
            }
        }
    }
}

// MARK: - Previews

#if DEBUG
#Preview("Dashboard - Loaded") {
    NavigationStack {
        DashboardView(viewModel: DashboardViewModel(), layoutStore: DashboardLayoutStore(), selectedTab: .constant(.dashboard))
    }
}

#Preview("Dashboard - Dark") {
    NavigationStack {
        DashboardView(viewModel: DashboardViewModel(), layoutStore: DashboardLayoutStore(), selectedTab: .constant(.dashboard))
    }
    .preferredColorScheme(.dark)
}
#endif
