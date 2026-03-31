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

            scrollContent
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

                if layoutStore.orderedWidgets.isEmpty {
                    emptyDashboardCard
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, AppSpacing.md)
                        .padding(.bottom, AppSpacing.md)
                } else {
                    ReorderableWidgetList(
                        widgets: $layoutStore.orderedWidgets,
                        isDragging: $isDraggingWidget,
                        isEditing: editMode.isEditing,
                        onPersist: { layoutStore.schedulePersistAfterReorder() },
                        onDelete: { index in
                            layoutStore.remove(atOffsets: IndexSet(integer: index))
                            DashboardHaptics.mediumImpact()
                        },
                        onEdgeScroll: { delta in
                            guard let sv = dashboardScrollView else { return 0 }
                            let oldY = sv.contentOffset.y
                            let maxY = max(0, sv.contentSize.height - sv.bounds.height)
                            let newY = max(0, min(oldY + delta, maxY))
                            sv.setContentOffset(CGPoint(x: 0, y: newY), animated: false)
                            return newY - oldY // actual delta applied
                        },
                        listGlobalOriginY: {
                            // The content's global Y origin: the scroll view's screen
                            // position minus how far the user has already scrolled.
                            guard let sv = dashboardScrollView else { return 0 }
                            let svScreenY = sv.convert(CGPoint.zero, to: nil).y
                            return svScreenY - sv.contentOffset.y
                        }
                    ) { kind in
                        widgetView(for: kind)
                    }
                }

                Color.clear.frame(height: AppSpacing.screenVerticalBottom)
            }
            // Must be inside the ScrollView content so FinderView sits inside the UIScrollView
            // hierarchy – walking up via superview then finds the UIScrollView.
            // Placing it as .background on the ScrollView itself makes FinderView a sibling of
            // the UIScrollView, so the superview walk never reaches it and dashboardScrollView stays nil.
            .background(
                UIScrollViewAccessor { sv in dashboardScrollView = sv }
                    .frame(width: 0, height: 0)
            )
        }
        .scrollDisabled(isDraggingWidget)
        .background(AppColors.backgroundPrimary)
        .environment(\.editMode, $editMode)
        .refreshable {
            await viewModel.refresh()
        }
    }

    // MARK: - Empty Dashboard

    private var emptyDashboardCard: some View {
        Card {
            VStack(spacing: AppSpacing.md) {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 44))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(AppColors.primary)

                VStack(alignment: .leading, spacing: AppSpacing.sm) {
                    Label("No widgets on your dashboard", icon: .rectangleStackFill)
                        .font(AppTypography.headline)
                        .foregroundStyle(AppColors.textPrimary)

                    Text("Add cards with the button below or the + button in the top bar.")
                        .font(AppTypography.subheadline)
                        .foregroundStyle(AppColors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                PrimaryButton("Add widgets", icon: .plus) {
                    DashboardHaptics.mediumImpact()
                    showAddWidgetSheet = true
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, AppSpacing.screenHorizontal)
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
                Image(systemName: "plus.circle.fill")
                    .font(.title3)
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(AppColors.primary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Add widget")

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

// MARK: - UIScrollViewAccessor

/// A zero-size `UIViewRepresentable` that walks up the UIKit hierarchy to find the nearest
/// `UIScrollView` and delivers it via a callback.
/// Place it as `.background` on a SwiftUI `ScrollView` to obtain a reference for
/// programmatic `setContentOffset` calls (used for drag-to-scroll auto-scrolling).
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
