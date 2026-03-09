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
        do {
            // Simulate network / database latency.
            // Replace with real KMP use-case invocations once shared module is linked.
            try await Task.sleep(nanoseconds: 600_000_000)
            allSessions = Self.makeStubSessions()
        } catch is CancellationError {
            // Task was cancelled -- do not set error.
        } catch {
            errorMessage = errorPrefix
        }
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

    // MARK: - Stub Data Factory

    private static func makeStubSessions() -> [WorkoutSession] {
        let calendar = Calendar.current
        let now = Date()

        // Deterministic session data: (daysAgo, hour, minute, pushUps, durationSec, quality)
        let sessionData: [(Int, Int, Int, Int, Int, Double)] = [
            (0,  8, 15, 42, 487, 0.88),
            (0, 18, 30, 28, 312, 0.74),
            (1,  7, 45, 55, 623, 0.92),
            (2,  9,  0, 35, 401, 0.81),
            (3, 17, 20, 48, 534, 0.86),
            (3, 12,  5, 22, 258, 0.69),
            (5,  8, 30, 61, 712, 0.94),
            (6, 19, 10, 33, 378, 0.77),
            (7,  7, 55, 45, 510, 0.83),
            (8, 16, 40, 18, 210, 0.62),
            (9,  9, 15, 52, 598, 0.90),
            (10, 8,  0, 38, 432, 0.79),
            (12, 17, 30, 44, 498, 0.85),
            (13,  8, 20, 29, 335, 0.72),
            (14,  9, 45, 57, 648, 0.91),
            (15, 18,  0, 36, 412, 0.80),
            (16,  7, 30, 50, 567, 0.87),
            (17, 16, 15, 25, 288, 0.68),
            (19,  8, 45, 63, 724, 0.93),
            (20, 17, 50, 41, 468, 0.82),
            (21,  9, 10, 34, 390, 0.76),
            (22,  8,  0, 47, 535, 0.84),
            (24, 18, 25, 20, 235, 0.65),
            (25,  7, 40, 58, 662, 0.89),
            (26,  9, 30, 32, 368, 0.75),
            (27, 17,  5, 46, 522, 0.83),
            (28,  8, 15, 39, 445, 0.78),
            (30, 16, 50, 53, 605, 0.88),
        ]

        return sessionData.compactMap { (daysAgo, hour, minute, pushUps, duration, quality) in
            guard var date = calendar.date(byAdding: .day, value: -daysAgo, to: now) else {
                return nil
            }
            date = calendar.date(
                bySettingHour: hour, minute: minute, second: 0, of: date
            ) ?? date

            let earned = max(1, pushUps / 10)
            let records = makeStubRecords(count: pushUps, duration: TimeInterval(duration), quality: quality)

            return WorkoutSession(
                id: UUID(),
                startDate: date,
                pushUpCount: pushUps,
                durationSeconds: duration,
                earnedMinutes: earned,
                averageQuality: quality,
                records: records
            )
        }
        .sorted { $0.startDate > $1.startDate }
    }

    /// Generates realistic push-up records for a session.
    private static func makeStubRecords(
        count: Int,
        duration: TimeInterval,
        quality: Double
    ) -> [PushUpRecord] {
        guard count > 0 else { return [] }

        // Distribute reps roughly evenly across the session duration,
        // with slight variation to simulate natural pacing.
        let baseInterval = duration / Double(count)

        return (0..<count).map { i in
            let jitter = Double.random(in: -0.3...0.3) * baseInterval
            let timeOffset = max(0, Double(i) * baseInterval + jitter)
            // Quality varies around the session average with +/-0.1 noise
            let repQuality = min(1.0, max(0.0, quality + Double.random(in: -0.1...0.1)))

            return PushUpRecord(
                id: UUID(),
                repNumber: i + 1,
                timeOffset: timeOffset,
                formScore: repQuality
            )
        }
    }
}
