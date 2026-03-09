import SwiftUI

// MARK: - HistoryView

/// Workout history screen showing all past sessions grouped by day.
///
/// **Layout**
/// ```
/// +-----------------------------------+
/// |  History                          |  <- navigation bar
/// |  [All | Last Month | Last Week]   |  <- filter chips
/// |  [Search by date...]              |  <- search field
/// |                                   |
/// |  Today                            |  <- section header
/// |  [WorkoutListItem]                |
/// |  [WorkoutListItem]                |
/// |                                   |
/// |  Yesterday                        |  <- section header
/// |  [WorkoutListItem]                |
/// |  ...                              |
/// +-----------------------------------+
/// ```
///
/// **Features**
/// - Grouped list with section headers (Today / Yesterday / date)
/// - Filter chips: All, Last Month, Last Week
/// - Date search field
/// - Swipe-to-delete with confirmation alert
/// - Tap -> WorkoutDetailView sheet
/// - Pull-to-refresh
/// - Empty state: "Noch keine Workouts"
/// - Loading state
struct HistoryView: View {

    @StateObject private var viewModel = HistoryViewModel()

    /// The session currently shown in the detail sheet.
    @State private var selectedSession: WorkoutSession? = nil

    /// Whether the detail sheet is presented.
    @State private var showDetail: Bool = false

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

            if viewModel.isLoading && !viewModel.hasAnyData {
                initialLoadingView
            } else {
                mainContent
            }
        }
        .navigationTitle("History")
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
        .alert("Delete Workout?", isPresented: $viewModel.showDeleteConfirmation) {
            Button("Delete", role: .destructive) {
                viewModel.confirmDelete()
            }
            Button("Cancel", role: .cancel) {
                viewModel.cancelDelete()
            }
        } message: {
            if let session = viewModel.sessionPendingDeletion {
                Text("This will permanently delete the workout from \(session.shortDateString) at \(session.timeString).")
            }
        }
        .sheet(isPresented: $showDetail) {
            if let session = selectedSession {
                WorkoutDetailView(session: session)
                    .presentationDetents([.large])
                    .presentationDragIndicator(.visible)
            }
        }
        .accessibilityIdentifier("history_screen")
    }

    // MARK: - Main Content

    private var mainContent: some View {
        VStack(spacing: 0) {
            // Filter + search bar (sticky header)
            filterAndSearchBar
                .padding(.horizontal, AppSpacing.screenHorizontal)
                .padding(.top, AppSpacing.xs)
                .padding(.bottom, AppSpacing.sm)
                .background(AppColors.backgroundPrimary)

            // List content
            listContent
        }
    }

    // MARK: - Filter + Search Bar

    private var filterAndSearchBar: some View {
        VStack(spacing: AppSpacing.xs) {
            // Filter chips
            HStack(spacing: AppSpacing.xs) {
                ForEach(HistoryFilter.allCases) { filter in
                    ChipButton(
                        filter.label,
                        isSelected: viewModel.selectedFilter == filter
                    ) {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            viewModel.selectedFilter = filter
                        }
                    }
                    .accessibilityIdentifier("history_filter_\(filter.label.lowercased().replacingOccurrences(of: " ", with: "_"))")
                }
                Spacer()
            }

            // Search field
            HStack(spacing: AppSpacing.xs) {
                Image(icon: .magnifyingglass)
                    .font(.system(size: AppSpacing.iconSizeSmall, weight: .medium))
                    .foregroundStyle(AppColors.textSecondary)

                TextField("Search by date (e.g. March 8)", text: $viewModel.searchText)
                    .font(AppTypography.body)
                    .foregroundStyle(AppColors.textPrimary)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .accessibilityIdentifier("history_search_field")

                if !viewModel.searchText.isEmpty {
                    Button {
                        viewModel.searchText = ""
                    } label: {
                        Image(icon: .xmarkCircleFill)
                            .font(.system(size: AppSpacing.iconSizeSmall))
                            .foregroundStyle(AppColors.textSecondary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Clear search")
                    .accessibilityIdentifier("history_search_clear")
                }
            }
            .padding(.horizontal, AppSpacing.sm)
            .padding(.vertical, AppSpacing.xs)
            .background(AppColors.backgroundSecondary)
            .clipShape(RoundedRectangle(cornerRadius: AppSpacing.cornerRadiusButton))
            .overlay(
                RoundedRectangle(cornerRadius: AppSpacing.cornerRadiusButton)
                    .strokeBorder(AppColors.separator, lineWidth: 0.5)
            )
        }
    }

    // MARK: - List Content

    @ViewBuilder
    private var listContent: some View {
        if viewModel.isEmpty {
            emptyStateView
        } else {
            // Use List for native swipe-to-delete support.
            // Custom row background + separator removal preserves the card design.
            List {
                ForEach(viewModel.filteredSections) { section in
                    Section {
                        ForEach(section.sessions) { session in
                            WorkoutListItem(session: session)
                                .listRowInsets(EdgeInsets(
                                    top: AppSpacing.xxs,
                                    leading: AppSpacing.screenHorizontal,
                                    bottom: AppSpacing.xxs,
                                    trailing: AppSpacing.screenHorizontal
                                ))
                                .listRowBackground(Color.clear)
                                .listRowSeparator(.hidden)
                                .onTapGesture {
                                    selectedSession = session
                                    showDetail = true
                                }
                                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                    Button(role: .destructive) {
                                        viewModel.requestDelete(session)
                                    } label: {
                                        Label("Delete", icon: .trash)
                                    }
                                }
                                .contextMenu {
                                    Button(role: .destructive) {
                                        viewModel.requestDelete(session)
                                    } label: {
                                        Label("Delete Workout", icon: .trash)
                                    }
                                }
                                .accessibilityIdentifier("history_session_\(session.id.uuidString)")
                        }
                    } header: {
                        sectionHeader(section.title)
                    }
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(AppColors.backgroundPrimary)
            .refreshable {
                await viewModel.refresh()
            }
            .accessibilityIdentifier("history_list")
        }
    }

    // MARK: - Section Header

    private func sectionHeader(_ title: String) -> some View {
        HStack {
            Text(title)
                .font(AppTypography.subheadlineSemibold)
                .foregroundStyle(AppColors.textPrimary)

            Spacer()
        }
        .padding(.vertical, AppSpacing.xs)
        .padding(.horizontal, AppSpacing.xxs)
        .background(AppColors.backgroundPrimary)
        .textCase(nil)
    }

    // MARK: - Empty State

    @ViewBuilder
    private var emptyStateView: some View {
        ScrollView {
            VStack(spacing: AppSpacing.lg) {
                Spacer(minLength: AppSpacing.xxl)

                if viewModel.hasAnyData {
                    // Has data but filter/search returned nothing
                    EmptyStateCard(
                        icon: .calendarBadgeCheckmark,
                        title: "No workouts found",
                        message: viewModel.searchText.isEmpty
                            ? "No workouts in the selected time range."
                            : "No workouts match your search."
                    )
                } else {
                    // No workouts at all
                    EmptyStateCard(
                        icon: .figureStrengthTraining,
                        title: "Noch keine Workouts",
                        message: "Complete your first workout to see your history here."
                    )
                }

                Spacer(minLength: AppSpacing.xxl)
            }
            .padding(.horizontal, AppSpacing.screenHorizontal)
        }
        .refreshable {
            await viewModel.refresh()
        }
        .accessibilityIdentifier("history_empty_state")
    }

    // MARK: - Initial Loading View

    private var initialLoadingView: some View {
        VStack(spacing: AppSpacing.lg) {
            ProgressView()
                .progressViewStyle(.circular)
                .tint(AppColors.primary)
                .scaleEffect(1.4)

            Text("Loading History...")
                .font(AppTypography.subheadline)
                .foregroundStyle(AppColors.textSecondary)
        }
        .accessibilityIdentifier("history_loading")
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .navigationBarTrailing) {
            if viewModel.isRefreshing {
                ProgressView()
                    .progressViewStyle(.circular)
                    .tint(AppColors.primary)
            }
        }
    }
}

// MARK: - Previews

#if DEBUG
#Preview("HistoryView - Loaded") {
    NavigationStack {
        HistoryView()
    }
}

#Preview("HistoryView - Dark") {
    NavigationStack {
        HistoryView()
    }
    .preferredColorScheme(.dark)
}
#endif
