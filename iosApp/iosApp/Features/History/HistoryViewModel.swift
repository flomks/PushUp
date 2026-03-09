import Combine
import Foundation
import Shared

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

// MARK: - WorkoutSession (view model)

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

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

    private static let shortDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "EEE, MMM d"
        f.locale = Locale(identifier: "en_US")
        return f
    }()
}

// MARK: - PushUpRecord (view model)

/// A single push-up rep recorded during a workout session.
struct PushUpRecord: Identifiable {
    let id: UUID
    let repNumber: Int
    let timeOffset: TimeInterval
    let formScore: Double
}

// MARK: - HistorySection

/// A group of workout sessions sharing the same calendar day.
struct HistorySection: Identifiable {
    let id: String
    let title: String
    let sessions: [WorkoutSession]
}

// MARK: - HistoryViewModel

/// Manages all data and state for the History screen.
///
/// Observes the local SQLite database via KMP's `DataBridge.observeSessions`.
/// The Flow emits immediately with the current list and again on every change
/// (e.g. after a workout is finished), so the history is always up to date
/// without requiring a manual refresh.
@MainActor
final class HistoryViewModel: ObservableObject {

    // MARK: - Published State

    @Published var selectedFilter: HistoryFilter = .all
    @Published var searchText: String = ""
    @Published private(set) var isLoading: Bool = false
    @Published private(set) var isRefreshing: Bool = false
    @Published var errorMessage: String? = nil
    @Published var sessionPendingDeletion: WorkoutSession? = nil
    @Published var showDeleteConfirmation: Bool = false
    @Published private(set) var filteredSections: [HistorySection] = []

    // MARK: - Private Data

    @Published private var allSessions: [WorkoutSession] = []
    private var cancellables = Set<AnyCancellable>()

    /// The KMP Flow observation job. Cancelled when this ViewModel is deallocated.
    private var observationJob: Kotlinx_coroutines_coreJob?

    // MARK: - Derived State

    var isEmpty: Bool { filteredSections.isEmpty }
    var hasAnyData: Bool { !allSessions.isEmpty }

    // MARK: - Init

    init() {
        bindFilterPipeline()
    }

    deinit {
        observationJob?.cancel(cause: nil)
    }

    // MARK: - Actions

    /// Starts observing the local database. Call once on first appear.
    func startObserving() async {
        guard observationJob == nil else { return }
        isLoading = true

        guard let user = await AuthService.shared.getCurrentUser() else {
            isLoading = false
            return
        }
        let userId = user.id

        // observeSessions returns a Job that keeps the Flow alive.
        // Each emission updates allSessions on the main thread.
        observationJob = DataBridge.shared.observeSessions(userId: userId) { [weak self] kmpSessions in
            guard let self else { return }
            self.allSessions = kmpSessions.compactMap { Self.map(kmpSession: $0) }
            self.isLoading = false
            self.isRefreshing = false
        }
    }

    /// Triggered by pull-to-refresh — the Flow already keeps data live,
    /// so this just shows the refreshing indicator briefly.
    func refresh() async {
        guard !isRefreshing, !isLoading else { return }
        isRefreshing = true
        // The Flow will emit again automatically if data changed.
        // Give it a moment then clear the indicator.
        try? await Task.sleep(for: .milliseconds(500))
        isRefreshing = false
    }

    func clearError() { errorMessage = nil }

    func requestDelete(_ session: WorkoutSession) {
        sessionPendingDeletion = session
        showDeleteConfirmation = true
    }

    func confirmDelete() {
        guard let session = sessionPendingDeletion else { return }
        allSessions.removeAll { $0.id == session.id }
        sessionPendingDeletion = nil
        showDeleteConfirmation = false
        // TODO: call WorkoutSessionRepository.delete once exposed via DataBridge
    }

    func cancelDelete() {
        sessionPendingDeletion = nil
        showDeleteConfirmation = false
    }

    // MARK: - Private: Reactive Filter Pipeline

    private func bindFilterPipeline() {
        let sessionsPublisher = $allSessions
        let filterPublisher   = $selectedFilter
        let searchPublisher   = $searchText
            .debounce(for: .milliseconds(300), scheduler: RunLoop.main)
            .removeDuplicates()

        Publishers.CombineLatest3(sessionsPublisher, filterPublisher, searchPublisher)
            .map { [weak self] sessions, filter, searchText in
                guard let self else { return [] }
                let filtered = self.applyFilters(sessions: sessions, filter: filter, searchText: searchText)
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

        let now = Date()
        let calendar = Calendar.current
        switch filter {
        case .all: break
        case .lastWeek:
            let cutoff = calendar.date(byAdding: .day, value: -7, to: now) ?? now
            result = result.filter { $0.startDate >= cutoff }
        case .lastMonth:
            let cutoff = calendar.date(byAdding: .month, value: -1, to: now) ?? now
            result = result.filter { $0.startDate >= cutoff }
        }

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
        let today     = calendar.startOfDay(for: Date())
        let yesterday = calendar.date(byAdding: .day, value: -1, to: today) ?? today

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
            let dayDate  = Self.isoDateFormatter.date(from: group.key) ?? Date()
            let dayStart = calendar.startOfDay(for: dayDate)

            let title: String
            if dayStart == today {
                title = "Today"
            } else if dayStart == yesterday {
                title = "Yesterday"
            } else {
                title = Self.sectionHeaderFormatter.string(from: dayDate)
            }

            return HistorySection(id: group.key, title: title, sessions: group.sessions)
        }
    }

    // MARK: - Private: KMP → View Model Mapping

    /// Maps a KMP `WorkoutSession` to the view-layer `WorkoutSession`.
    /// Only completed sessions (endedAt != nil) are shown in history.
    private static func map(kmpSession: Shared.WorkoutSession) -> WorkoutSession? {
        guard let endedAtInstant = kmpSession.endedAt else { return nil }

        let startMs  = kmpSession.startedAt.epochSeconds * 1_000 + Int64(kmpSession.startedAt.nanosecondsOfSecond) / 1_000_000
        let endMs    = endedAtInstant.epochSeconds * 1_000 + Int64(endedAtInstant.nanosecondsOfSecond) / 1_000_000
        let startDate = Date(timeIntervalSince1970: Double(startMs) / 1_000.0)
        let duration  = max(0, Int((endMs - startMs) / 1_000))

        return WorkoutSession(
            id: UUID(uuidString: kmpSession.id) ?? UUID(),
            startDate: startDate,
            pushUpCount: Int(kmpSession.pushUpCount),
            durationSeconds: duration,
            earnedMinutes: Int(kmpSession.earnedTimeCreditSeconds / 60),
            averageQuality: Double(kmpSession.quality),
            records: []
        )
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
