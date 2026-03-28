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
struct DashboardView: View {

    @StateObject private var viewModel = DashboardViewModel()
    @StateObject private var layoutStore = DashboardLayoutStore()

    /// Binding to the parent `TabView` selection so the "Workout starten"
    /// button can switch tabs without pushing a new navigation destination.
    @Binding var selectedTab: Tab

    @State private var editMode: EditMode = .inactive
    @State private var showTimeCreditDetail = false
    @State private var showAddWidgetSheet = false

    private var showError: Binding<Bool> {
        Binding(
            get: { viewModel.errorMessage != nil },
            set: { if !$0 { viewModel.clearError() } }
        )
    }

    private var isInitialLoading: Bool {
        viewModel.isLoading && !viewModel.hasEverWorkedOut
    }

    var body: some View {
        ZStack {
            AppColors.backgroundPrimary
                .ignoresSafeArea()

            if isInitialLoading {
                initialLoadingView
            } else {
                scrollContent
            }
        }
        .navigationTitle("Dashboard")
        .navigationBarTitleDisplayMode(.large)
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
        .alert("Error", isPresented: showError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
    }

    // MARK: - Scroll Content

    private var scrollContent: some View {
        List {
            if layoutStore.orderedWidgets.isEmpty {
                emptyDashboardRow
            } else {
                ForEach(layoutStore.orderedWidgets, id: \.self) { kind in
                    widgetView(for: kind)
                        .frame(maxWidth: .infinity)
                        .padding(.horizontal, AppSpacing.screenHorizontal)
                        .padding(.top, layoutStore.orderedWidgets.first == kind ? AppSpacing.sm : 0)
                        .padding(.bottom, AppSpacing.md)
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                }
                .onMove { source, destination in
                    layoutStore.move(fromOffsets: source, toOffset: destination)
                    DashboardHaptics.lightImpact()
                }
                .onDelete { offsets in
                    layoutStore.remove(atOffsets: offsets)
                    DashboardHaptics.mediumImpact()
                }
            }

            Color.clear
                .frame(height: AppSpacing.screenVerticalBottom)
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(AppColors.backgroundPrimary)
        .refreshable {
            await viewModel.refresh()
        }
    }

    // MARK: - Empty Dashboard

    private var emptyDashboardRow: some View {
        Card {
            VStack(alignment: .leading, spacing: AppSpacing.md) {
                Label("No widgets yet", icon: .rectangleStackFill)
                    .font(AppTypography.headline)
                    .foregroundStyle(AppColors.textPrimary)

                Text("Add widgets to customize your dashboard.")
                    .font(AppTypography.subheadline)
                    .foregroundStyle(AppColors.textSecondary)

                PrimaryButton("Add widgets", icon: .plus) {
                    DashboardHaptics.mediumImpact()
                    showAddWidgetSheet = true
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, AppSpacing.screenHorizontal)
        .padding(.top, AppSpacing.sm)
        .padding(.bottom, AppSpacing.md)
        .listRowInsets(EdgeInsets())
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
    }

    // MARK: - Widgets

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
                isLoading: viewModel.isLoading
            )
        case .activitySummary:
            if viewModel.hasEverWorkedOut {
                lastSessionSection
            } else {
                emptyStateSection
            }
        case .workoutQuickAction:
            workoutStartButton
        }
    }

    // MARK: - Last Session Section

    @ViewBuilder
    private var lastSessionSection: some View {
        if let session = viewModel.lastSession {
            Card {
                VStack(alignment: .leading, spacing: AppSpacing.sm) {

                    HStack {
                        Label("Last Session", icon: .clockArrowCirclepath)
                            .font(AppTypography.headline)
                            .foregroundStyle(AppColors.textPrimary)

                        Spacer()

                        Text(session.relativeDate)
                            .font(AppTypography.caption1)
                            .foregroundStyle(AppColors.textSecondary)
                    }

                    Divider()

                    lastSessionMetrics(session)
                }
            }
        }
    }

    @ViewBuilder
    private func lastSessionMetrics(_ session: DashboardLastSession) -> some View {
        VStack(spacing: AppSpacing.sm) {
            VStack(spacing: AppSpacing.xxs) {
                Image(systemName: session.primaryMetricIcon.rawValue)
                    .font(.system(size: AppSpacing.iconSizeStandard, weight: .semibold))
                    .foregroundStyle(AppColors.primary)

                Text(session.primaryMetricValue)
                    .font(AppTypography.displayMedium)
                    .foregroundStyle(AppColors.textPrimary)

                Text(session.primaryMetricLabel)
                    .font(AppTypography.caption1)
                    .foregroundStyle(AppColors.textSecondary)
            }

            HStack {
                metricItem(
                    icon: .clock,
                    value: formatDuration(session.durationSeconds),
                    label: "Duration",
                    tint: AppColors.info
                )

                Divider().frame(height: 36)

                metricItem(
                    icon: .boltFill,
                    value: "+\(session.earnedSeconds / 60) min",
                    label: "Earned",
                    tint: AppColors.success
                )

                Divider().frame(height: 36)

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
                .foregroundStyle(AppColors.textPrimary)

            Text(label)
                .font(AppTypography.caption1)
                .foregroundStyle(AppColors.textSecondary)
        }
        .frame(maxWidth: .infinity)
    }

    private func formatDuration(_ seconds: Int) -> String {
        let m = seconds / 60
        let s = seconds % 60
        return String(format: "%d:%02d", m, s)
    }

    // MARK: - Empty State

    @ViewBuilder
    private var emptyStateSection: some View {
        EmptyStateCard(
            icon: .figureRun,
            title: "Start your first activity!",
            message: "Track workouts or running and earn time credit for screen time.",
            actionTitle: "Choose Workout",
            action: { selectedTab = .workout }
        )
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

    // MARK: - Initial Loading View

    private var initialLoadingView: some View {
        VStack(spacing: AppSpacing.lg) {
            ProgressView()
                .progressViewStyle(.circular)
                .tint(AppColors.primary)
                .scaleEffect(1.4)

            Text("Loading Dashboard...")
                .font(AppTypography.subheadline)
                .foregroundStyle(AppColors.textSecondary)
        }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var dashboardToolbar: some ToolbarContent {
        ToolbarItem(placement: .navigationBarLeading) {
            if !isInitialLoading {
                EditButton()
            }
        }

        ToolbarItemGroup(placement: .navigationBarTrailing) {
            if editMode.isEditing {
                Button {
                    DashboardHaptics.lightImpact()
                    showAddWidgetSheet = true
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.title3)
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(AppColors.primary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Add widget")
            }

            if viewModel.isRefreshing {
                ProgressView()
                    .progressViewStyle(.circular)
                    .tint(AppColors.primary)
            }

            SyncIndicator()
        }
    }
}

// MARK: - Add Widgets Sheet

private struct DashboardAddWidgetsSheet: View {

    @ObservedObject var layoutStore: DashboardLayoutStore
    @Environment(\.dismiss) private var dismiss

    private var availableKinds: [DashboardWidgetKind] {
        DashboardWidgetKind.allCases.filter { !layoutStore.orderedWidgets.contains($0) }
    }

    var body: some View {
        NavigationStack {
            Group {
                if availableKinds.isEmpty {
                    ContentUnavailableView(
                        "All widgets on dashboard",
                        systemImage: "square.grid.2x2",
                        description: Text("Remove a widget from the dashboard to add it back here.")
                    )
                } else {
                    List(availableKinds, id: \.self) { kind in
                        Button {
                            layoutStore.add(kind)
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
                            .padding(.vertical, AppSpacing.xs)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .navigationTitle("Add widget")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        DashboardHaptics.lightImpact()
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(28)
        .presentationBackground(.regularMaterial)
    }
}

// MARK: - Previews

#if DEBUG
#Preview("Dashboard - Loaded") {
    NavigationStack {
        DashboardView(selectedTab: .constant(.dashboard))
    }
}

#Preview("Dashboard - Dark") {
    NavigationStack {
        DashboardView(selectedTab: .constant(.dashboard))
    }
    .preferredColorScheme(.dark)
}
#endif
