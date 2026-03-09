import Combine
import Foundation

// MARK: - HistoryFilter

/// Time-range filter options for the workout history list.
enum HistoryFilter: Int, CaseIterable, Identifiable {
    case all       = 0
    case lastMonth = 1
    case lastWeek  = 2

    var id: Int { rawValue }

    var label: String {
        switch self {
        case .all:       return "All"
        case .lastMonth: return "Last Month"
        case .lastWeek:  return "Last Week"
        }
    }
}

// MARK: - PushUpRecord

/// A single push-up rep recorded during a workout session.
struct PushUpRecord: Identifiable {
    let id: UUID
    /// Rep number within the session (1-based).
    let repNumber: Int
    /// Timestamp of the rep relative to session start, in seconds.
    let timeOffset: TimeInterval
    /// Form quality score for this rep in [0.0, 1.0].
    let formScore: Double
}

// MARK: - WorkoutSession

/// A completed workout session with all associated data.
struct WorkoutSession: Identifiable {
    let id: UUID
    /// When the session started.
    let startDate: Date
    /// Total push-ups counted.
    let pushUpCount: Int
    /// Session duration in seconds.
    let durationSeconds: Int
    /// Time credit earned in whole minutes.
    let earnedMinutes: Int
    /// Average form quality score in [0.0, 1.0].
    let averageQuality: Double
    /// Individual push-up records for the detail view.
    let records: [PushUpRecord]

    /// Formatted time string (e.g. "09:42").
    var timeString: String {
        Self.timeFormatter.string(from: startDate)
    }

    /// Formatted date string (e.g. "Mon, Mar 8").
    var shortDateString: String {
        Self.shortDateFormatter.string(from: startDate)
    }

    /// Formatted duration string (e.g. "7:32").
    var durationString: String {
        let m = durationSeconds / 60
        let s = durationSeconds % 60
        return String(format: "%d:%02d", m, s)
    }

    /// Number of filled stars (0-5) based on average quality.
    var starCount: Int {
        Int((averageQuality * 5).rounded())
    }

    // MARK: - Cached DateFormatters

    /// Cached formatter for "HH:mm" (e.g. "09:42").
    /// `DateFormatter` is expensive to allocate -- reuse a single instance.
    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

    /// Cached formatter for "EEE, MMM d" (e.g. "Mon, Mar 8").
    private static let shortDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "EEE, MMM d"
        f.locale = Locale(identifier: "en_US")
        return f
    }()
}

// MARK: - HistorySection

/// A group of workout sessions sharing the same calendar day.
struct HistorySection: Identifiable {
    /// The calendar day this section represents (yyyy-MM-dd).
    let id: String
    /// Display header string (e.g. "Today", "Yesterday", "Mon, Mar 8").
    let title: String
    /// Sessions within this day, sorted newest first.
    let sessions: [WorkoutSession]
}

// MARK: - HistoryViewModel

/// Manages all data and state for the History screen.
///
/// Data is currently simulated with realistic stub values so the UI can be
/// built and previewed without a live backend. Replace `fetchData()` with
/// real KMP use-case calls (e.g. `GetWorkoutHistoryUseCase`) once the shared
/// module is linked into the iOS target.
@MainActor
final class HistoryViewModel: ObservableObject {

    // MARK: - Published State

    /// Currently selected time-range filter.
    @Published var selectedFilter: HistoryFilter = .all

    /// Current search text (date search).
    @Published var searchText: String = ""

    /// Whether the initial load is in progress.
    @Published private(set) var isLoading: Bool = false

    /// Whether a pull-to-refresh is in progress.
    @Published private(set) var isRefreshing: Bool = false

    /// Non-nil when a load attempt failed.
    @Published var errorMessage: String? = nil

    /// The session pending deletion (triggers confirmation alert).
    @Published var sessionPendingDeletion: WorkoutSession? = nil

    /// Whether the delete confirmation alert is shown.
    @Published var showDeleteConfirmation: Bool = false

    /// Filtered and grouped sections, recomputed when inputs change.
    /// Using `@Published` instead of a computed property avoids redundant
    /// re-filtering on every SwiftUI body evaluation.
    @Published private(set) var filteredSections: [HistorySection] = []

    // MARK: - Private Data

    /// All sessions loaded from the data source, newest first.
    /// `@Published` so that mutations (e.g. delete) trigger UI updates.
    @Published private var allSessions: [WorkoutSession] = []

    /// Combine subscriptions for reactive filtering.
    private var cancellables = Set<AnyCancellable>()

    // MARK: - Derived State

    /// Whether the filtered result set is empty.
    var isEmpty: Bool {
        filteredSections.isEmpty
    }

    /// Whether there are any sessions at all (for empty state messaging).
    var hasAnyData: Bool {
        !allSessions.isEmpty
    }

    // MARK: - Init

    init() {
        bindFilterPipeline()
    }

    // MARK: - Actions

    /// Loads history data. Called on first appear.
    func loadData() async {
        guard !isLoading, !isRefreshing else { return }
        isLoading = true
        errorMessage = nil
        await fetchData(errorPrefix: "Failed to load history.")
        isLoading = false
    }

    /// Triggered by pull-to-refresh.
    func refresh() async {
        guard !isRefreshing, !isLoading else { return }
        isRefreshing = true
        errorMessage = nil
        await fetchData(errorPrefix: "Refresh failed.")
        isRefreshing = false
    }

    /// Clears the current error message.
    func clearError() {
        errorMessage = nil
    }

    /// Initiates the delete flow for a session.
    func requestDelete(_ session: WorkoutSession) {
        sessionPendingDeletion = session
        showDeleteConfirmation = true
    }

    /// Confirms and performs the deletion.
    func confirmDelete() {
        guard let session = sessionPendingDeletion else { return }
        allSessions.removeAll { $0.id == session.id }
        sessionPendingDeletion = nil
        showDeleteConfirmation = false
    }

    /// Cancels the pending deletion.
    func cancelDelete() {
        sessionPendingDeletion = nil
        showDeleteConfirmation = false
    }

    // MARK: - Private: Reactive Filter Pipeline

    /// Sets up a Combine pipeline that recomputes `filteredSections`
    /// whenever `allSessions`, `selectedFilter`, or `searchText` change.
    /// Debounces search text by 300ms to avoid excessive recomputation
    /// while the user is typing.
    private func bindFilterPipeline() {
        let sessionsPublisher = $allSessions
        let filterPublisher = $selectedFilter
        let searchPublisher = $searchText
            .debounce(for: .milliseconds(300), scheduler: RunLoop.main)
            .removeDuplicates()

        Publishers.CombineLatest3(sessionsPublisher, filterPublisher, searchPublisher)
            .map { [weak self] sessions, filter, searchText in
                guard let self else { return [] }
                let filtered = self.applyFilters(
                    sessions: sessions,
                    filter: filter,
                    searchText: searchText
                )
                return self.groupedByDay(filtered)
            }
            .receive(on: RunLoop.main)
            .assign(to: &$filteredSections)
    }

    // MARK: - Private: Filtering

    private func applyFilters(
        sessions: [WorkoutSession],
        filter: HistoryFilter,
        searchText: String
    ) -> [WorkoutSession] {
        var result = sessions

        // Apply time-range filter
        let now = Date()
        let calendar = Calendar.current
        switch filter {
        case .all:
            break
        case .lastWeek:
            let cutoff = calendar.date(byAdding: .day, value: -7, to: now) ?? now
            result = result.filter { $0.startDate >= cutoff }
        case .lastMonth:
            let cutoff = calendar.date(byAdding: .month, value: -1, to: now) ?? now
            result = result.filter { $0.startDate >= cutoff }
        }

        // Apply date search
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if !query.isEmpty {
            result = result.filter { session in
                session.shortDateString.lowercased().contains(query) ||
                Self.searchDateFormatter.string(from: session.startDate).lowercased().contains(query) ||
                Self.isoDateFormatter.string(from: session.startDate).lowercased().contains(query)
            }
        }

        return result
    }

    // MARK: - Private: Grouping

    private func groupedByDay(_ sessions: [WorkoutSession]) -> [HistorySection] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let yesterday = calendar.date(byAdding: .day, value: -1, to: today) ?? today

        // Group by day key, preserving insertion order (newest first).
        var groups: [(key: String, sessions: [WorkoutSession])] = []
        var seen: [String: Int] = [:]

        for session in sessions {
            let dayKey = Self.isoDateFormatter.string(from: session.startDate)
            if let idx = seen[dayKey] {
                groups[idx].sessions.append(session)
            } else {
                seen[dayKey] = groups.count
                groups.append((key: dayKey, sessions: [session]))
            }
        }

        return groups.map { group in
            let dayDate = Self.isoDateFormatter.date(from: group.key) ?? Date()
            let dayStart = calendar.startOfDay(for: dayDate)

            let title: String
            if dayStart == today {
                title = "Today"
            } else if dayStart == yesterday {
                title = "Yesterday"
            } else {
                title = Self.sectionHeaderFormatter.string(from: dayDate)
            }

            return HistorySection(
                id: group.key,
                title: title,
                sessions: group.sessions
            )
        }
    }

    // MARK: - Private: Fetch

    private func fetchData(errorPrefix: String) async {
        // TODO: Replace with real KMP use-case calls once workout history
        // use cases are wired up. For now show empty list — no mock data.
        allSessions = []
    }

    // MARK: - Cached DateFormatters

    private static let isoDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

    private static let sectionHeaderFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "EEE, MMM d"
        f.locale = Locale(identifier: "en_US")
        return f
    }()

    private static let searchDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMMM d yyyy"
        f.locale = Locale(identifier: "en_US")
        return f
    }()

}
