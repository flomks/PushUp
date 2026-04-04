import SwiftUI

// MARK: - HistoryView

/// Unified workout history screen showing all past sessions grouped by day.
///
/// **Layout**
/// ```
/// +-----------------------------------+
/// |  History                          |  <- navigation bar
/// |  [All | Last Month | Last Week]   |  <- filter chips
/// |  [Search by date...]              |  <- search field
/// |                                   |
/// |  Today                            |  <- section header
/// |  [HistoryListItem - Push-Up]      |
/// |  [HistoryListItem - Running]      |
/// |                                   |
/// |  Yesterday                        |  <- section header
/// |  [HistoryListItem]                |
/// |  ...                              |
/// +-----------------------------------+
/// ```
///
/// **Features**
/// - Unified list of push-up workouts and running sessions
/// - Grouped list with section headers (Today / Yesterday / date)
/// - Filter chips: All, Last Month, Last Week
/// - Date search field
/// - Swipe-to-delete with confirmation alert
/// - Tap push-up -> WorkoutDetailView sheet
/// - Tap running -> JoggingDetailView sheet (with interactive route map)
/// - Pull-to-refresh
/// - Empty state: "No workouts yet"
/// - Loading state
struct HistoryView: View {

    @StateObject private var viewModel = HistoryViewModel()

    /// The currently selected history item for the detail sheet.
    @State private var selectedItem: HistoryItem? = nil

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

            if viewModel.isLoading && !viewModel.hasAnyData {
                initialLoadingView
            } else {
                mainContent
            }
        }
        .preferredColorScheme(.dark)
        .navigationTitle("History")
        .navigationBarTitleDisplayMode(.large)
        .toolbar { toolbarContent }
        .task { await viewModel.startObserving() }
        .alert("Error", isPresented: showError) {
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
            if let item = viewModel.itemPendingDeletion {
                Text("This will permanently delete the workout from \(item.shortDateString) at \(item.timeString).")
            }
        }
        .sheet(item: $selectedItem) { item in
            switch item {
            case .pushUp(let session):
                WorkoutDetailView(session: session)
                    .presentationDetents([.large])
                    .presentationDragIndicator(.visible)
            case .jogging(let session):
                JoggingDetailView(session: session)
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
                .background(DashboardWidgetChrome.pageBackground)

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
                    .foregroundStyle(DashboardWidgetChrome.labelPrimary)
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
            .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: AppSpacing.cornerRadiusButton))
            .overlay(
                RoundedRectangle(cornerRadius: AppSpacing.cornerRadiusButton)
                    .strokeBorder(Color.white.opacity(0.10), lineWidth: 1)
            )
        }
    }

    // MARK: - List Content

    @ViewBuilder
    private var listContent: some View {
        if viewModel.isEmpty {
            emptyStateView
        } else {
            List {
                ForEach(viewModel.filteredSections) { section in
                    Section {
                        ForEach(section.items) { item in
                            HistoryListItem(item: item)
                                .listRowInsets(EdgeInsets(
                                    top: AppSpacing.xxs,
                                    leading: AppSpacing.screenHorizontal,
                                    bottom: AppSpacing.xxs,
                                    trailing: AppSpacing.screenHorizontal
                                ))
                                .listRowBackground(Color.clear)
                                .listRowSeparator(.hidden)
                                .onTapGesture {
                                    selectedItem = item
                                }
                                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                    Button(role: .destructive) {
                                        viewModel.requestDelete(item)
                                    } label: {
                                        Label("Delete", icon: .trash)
                                    }
                                }
                                .contextMenu {
                                    Button(role: .destructive) {
                                        viewModel.requestDelete(item)
                                    } label: {
                                        Label("Delete Workout", icon: .trash)
                                    }
                                }
                                .accessibilityIdentifier("history_item_\(item.id.uuidString)")
                        }
                    } header: {
                        sectionHeader(section.title)
                    }
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(DashboardWidgetChrome.pageBackground)
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
                .foregroundStyle(DashboardWidgetChrome.labelPrimary)

            Spacer()
        }
        .padding(.vertical, AppSpacing.xs)
        .padding(.horizontal, AppSpacing.xxs)
        .background(DashboardWidgetChrome.pageBackground)
        .textCase(nil)
    }

    // MARK: - Empty State

    @ViewBuilder
    private var emptyStateView: some View {
        ScrollView {
            VStack(spacing: AppSpacing.lg) {
                Spacer(minLength: AppSpacing.xxl)

                if viewModel.hasAnyData {
                    EmptyStateCard(
                        icon: .calendarBadgeCheckmark,
                        title: "No workouts found",
                        message: viewModel.searchText.isEmpty
                            ? "No workouts in the selected time range."
                            : "No workouts match your search."
                    )
                } else {
                    EmptyStateCard(
                        icon: .figureStrengthTraining,
                        title: "No workouts yet",
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
                .foregroundStyle(DashboardWidgetChrome.labelSecondary)
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
