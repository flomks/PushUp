import SwiftUI

// MARK: - DashboardView

/// Main Dashboard screen showing time credit, daily stats, weekly chart,
/// last session summary, and a "Workout starten" quick-action button.
///
/// Supports pull-to-refresh and renders appropriate empty / loading states.
/// Navigation to the Workout tab is handled via the `selectedTab` binding
/// passed in from `MainTabView`.
struct DashboardView: View {

    @StateObject private var viewModel = DashboardViewModel()

    /// Binding to the parent `TabView` selection so the "Workout starten"
    /// button can switch tabs without pushing a new navigation destination.
    @Binding var selectedTab: Tab

    /// Controls whether the time credit detail sheet is presented.
    @State private var showTimeCreditDetail = false

    /// Controls whether the error alert is presented. Derived from
    /// `viewModel.errorMessage` and properly clears it on dismiss.
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

            if viewModel.isLoading && !viewModel.hasEverWorkedOut {
                initialLoadingView
            } else {
                scrollContent
            }
        }
        .navigationTitle("Dashboard")
        .navigationBarTitleDisplayMode(.large)
        .toolbar { refreshToolbarItem }
        .task { await viewModel.startObserving() }
        .sheet(isPresented: $showTimeCreditDetail) {
            TimeCreditDetailView(
                availableSeconds: viewModel.availableSeconds,
                dailyEarnedSeconds: viewModel.dailyEarnedSeconds,
                dailySpentSeconds: viewModel.dailySpentSeconds,
                todayWorkoutEarned: viewModel.todayWorkoutEarned,
                carryOverPercentSeconds: viewModel.carryOverPercentSeconds,
                carryOverLateNightSeconds: viewModel.carryOverLateNightSeconds,
                totalEarnedSeconds: viewModel.totalEarnedSeconds,
                totalSpentSeconds: viewModel.totalSpentSeconds
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
        ScrollView {
            LazyVStack(spacing: AppSpacing.md) {

                // 1. Time credit hero card (tappable for detail breakdown)
                DashboardTimeCreditCard(
                    availableSeconds: viewModel.availableSeconds,
                    dailyEarnedSeconds: viewModel.dailyEarnedSeconds,
                    totalEarnedSeconds: viewModel.totalEarnedSeconds,
                    isLoading: viewModel.isLoading,
                    onTap: { showTimeCreditDetail = true }
                )

                // 1b. Screen Time status (only shown when authorized + selection exists)
                ScreenTimeStatusCard()

                // 2. Daily stats
                DailyStatsCard(
                    stats: viewModel.dailyStats,
                    isLoading: viewModel.isLoading
                )

                // 3. Weekly chart
                WeeklyChart(
                    days: viewModel.weekDays,
                    isLoading: viewModel.isLoading
                )

                // 4. Last session or empty state
                if viewModel.hasEverWorkedOut {
                    lastSessionSection
                } else {
                    emptyStateSection
                }

                // 5. "Workout starten" quick-action button
                workoutStartButton
            }
            .padding(.horizontal, AppSpacing.screenHorizontal)
            .padding(.top, AppSpacing.sm)
            .padding(.bottom, AppSpacing.screenVerticalBottom)
        }
        .refreshable {
            await viewModel.refresh()
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

                    // Metrics row -- reuses the same layout pattern as
                    // WorkoutSummaryCard but inline to avoid double-card nesting.
                    lastSessionMetrics(session)
                }
            }
        }
    }

    @ViewBuilder
    private func lastSessionMetrics(_ session: DashboardLastSession) -> some View {
        VStack(spacing: AppSpacing.sm) {
            // Push-up count hero
            VStack(spacing: AppSpacing.xxs) {
                Text("\(session.pushUpCount)")
                    .font(AppTypography.displayMedium)
                    .foregroundStyle(AppColors.textPrimary)

                Text("Push-Ups")
                    .font(AppTypography.caption1)
                    .foregroundStyle(AppColors.textSecondary)
            }

            // Metrics row
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
                    value: String(format: "%.0f%%", session.qualityScore * 100),
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
            icon: .figureStrengthTraining,
            title: "Start your first workout!",
            message: "Do push-ups and earn time credit for your screen time.",
            actionTitle: "Start Workout",
            action: { selectedTab = .workout }
        )
    }

    // MARK: - Workout Start Button

    private var workoutStartButton: some View {
        PrimaryButton(
            "Start Workout",
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
    private var refreshToolbarItem: some ToolbarContent {
        ToolbarItem(placement: .navigationBarTrailing) {
            if viewModel.isRefreshing {
                ProgressView()
                    .progressViewStyle(.circular)
                    .tint(AppColors.primary)
            }
        }

        // Sync status indicator (Task 3.14) -- shows sync state and
        // unsynced workout count badge in the navigation bar.
        SyncIndicatorToolbarItem()
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
