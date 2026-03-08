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
        .task { await viewModel.loadData() }
        .alert(
            "Fehler",
            isPresented: Binding(
                get: { viewModel.errorMessage != nil },
                set: { if !$0 { /* errors clear on next load */ } }
            )
        ) {
            Button("Erneut versuchen") {
                Task { await viewModel.loadData() }
            }
            Button("OK", role: .cancel) {}
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
    }

    // MARK: - Scroll Content

    private var scrollContent: some View {
        ScrollView {
            RefreshControl(isRefreshing: viewModel.isRefreshing)

            LazyVStack(spacing: AppSpacing.md) {

                if viewModel.hasEverWorkedOut || !viewModel.isLoading {
                    // 1. Time credit hero card
                    DashboardTimeCreditCard(
                        availableSeconds: viewModel.availableSeconds,
                        totalEarnedSeconds: viewModel.totalEarnedSeconds,
                        isLoading: viewModel.isLoading
                    )

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
            VStack(alignment: .leading, spacing: AppSpacing.sm) {

                HStack {
                    Label("Letzte Session", icon: .clockArrowCirclepath)
                        .font(AppTypography.headline)
                        .foregroundStyle(AppColors.textPrimary)

                    Spacer()

                    Text(session.relativeDate)
                        .font(AppTypography.caption1)
                        .foregroundStyle(AppColors.textSecondary)
                }
                .padding(.horizontal, AppSpacing.md)
                .padding(.top, AppSpacing.md)

                WorkoutSummaryCard(
                    pushUpCount: session.pushUpCount,
                    durationSeconds: session.durationSeconds,
                    earnedSeconds: session.earnedSeconds,
                    qualityScore: session.qualityScore
                )
                .padding(.horizontal, AppSpacing.md)
                .padding(.bottom, AppSpacing.md)
            }
            .background(AppColors.backgroundSecondary)
            .clipShape(RoundedRectangle(cornerRadius: AppSpacing.cornerRadiusCard))
            .shadow(color: Color.black.opacity(0.06), radius: 8, x: 0, y: 2)
        }
    }

    // MARK: - Empty State

    @ViewBuilder
    private var emptyStateSection: some View {
        EmptyStateCard(
            icon: .figureStrengthTraining,
            title: "Starte dein erstes Workout!",
            message: "Mach Push-Ups und verdiene Zeitguthaben fuer deine Bildschirmzeit.",
            actionTitle: "Workout starten",
            action: { selectedTab = .workout }
        )
    }

    // MARK: - Workout Start Button

    private var workoutStartButton: some View {
        PrimaryButton(
            "Workout starten",
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

            Text("Lade Dashboard...")
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
    }
}

// MARK: - RefreshControl

/// Invisible spacer that triggers pull-to-refresh visual feedback.
/// The actual refresh logic is handled by `.refreshable` on the ScrollView.
private struct RefreshControl: View {
    let isRefreshing: Bool

    var body: some View {
        Color.clear
            .frame(height: 0)
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
