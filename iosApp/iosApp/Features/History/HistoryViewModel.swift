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

// MARK: - HistoryItem

/// A unified history item that wraps either a push-up workout or a jogging session.
enum HistoryItem: Identifiable, Equatable {
    case pushUp(PushUpSession)
    case jogging(JoggingSessionItem)

    var id: UUID {
        switch self {
        case .pushUp(let s):  return s.id
        case .jogging(let s): return s.id
        }
    }

    static func == (lhs: HistoryItem, rhs: HistoryItem) -> Bool {
        lhs.id == rhs.id
    }

    var startDate: Date {
        switch self {
        case .pushUp(let s):  return s.startDate
        case .jogging(let s): return s.startDate
        }
    }

    var shortDateString: String {
        switch self {
        case .pushUp(let s):  return s.shortDateString
        case .jogging(let s): return s.shortDateString
        }
    }

    var timeString: String {
        switch self {
        case .pushUp(let s):  return s.timeString
        case .jogging(let s): return s.timeString
        }
    }

    var earnedMinutes: Int {
        switch self {
        case .pushUp(let s):  return s.earnedMinutes
        case .jogging(let s): return s.earnedMinutes
        }
    }
}

// MARK: - PushUpSession (view model)

/// A completed push-up workout session with all associated data.
struct PushUpSession: Identifiable {
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

// MARK: - JoggingSessionItem (view model)

/// A completed jogging session with all associated data.
struct JoggingSessionItem: Identifiable {
    let id: UUID
    /// The original KMP session ID string (for fetching route points).
    let kmpSessionId: String
    /// When the session started.
    let startDate: Date
    /// Total distance in meters.
    let distanceMeters: Double
    /// Session duration in seconds.
    let durationSeconds: Int
    /// Average pace in seconds per km, or nil if not available.
    let avgPaceSecondsPerKm: Int?
    /// Estimated calories burned.
    let caloriesBurned: Int
    /// Time credit earned in whole minutes.
    let earnedMinutes: Int

    /// Distance in km.
    var distanceKm: Double { distanceMeters / 1000.0 }

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

    /// Formatted distance string (e.g. "3.42 km" or "850 m").
    var distanceString: String {
        if distanceMeters >= 1000 {
            return String(format: "%.2f km", distanceKm)
        } else {
            return "\(Int(distanceMeters)) m"
        }
    }

    /// Formatted pace as "MM:SS /km", or "--:-- /km" if not available.
    var formattedPace: String {
        guard let pace = avgPaceSecondsPerKm else { return "--:--" }
        let minutes = pace / 60
        let seconds = pace % 60
        return String(format: "%d:%02d", minutes, seconds)
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

/// A group of history items sharing the same calendar day.
struct HistorySection: Identifiable {
    let id: String
    let title: String
    let items: [HistoryItem]
}

// MARK: - HistoryViewModel

/// Manages all data and state for the History screen.
///
/// Observes both push-up workout sessions and jogging sessions from the local
/// SQLite database via KMP's `DataBridge`. Both Flows emit immediately with
/// the current list and again on every change, so the history is always up to
/// date without requiring a manual refresh.
@MainActor
final class HistoryViewModel: ObservableObject {

    // MARK: - Published State

    @Published var selectedFilter: HistoryFilter = .all
    @Published var searchText: String = ""
    @Published private(set) var isLoading: Bool = false
    @Published private(set) var isRefreshing: Bool = false
    @Published var errorMessage: String? = nil
    @Published var itemPendingDeletion: HistoryItem? = nil
    @Published var showDeleteConfirmation: Bool = false
    @Published private(set) var filteredSections: [HistorySection] = []

    // MARK: - Private Data

    @Published private var allItems: [HistoryItem] = []
    private var pushUpSessions: [PushUpSession] = []
    private var joggingSessions: [JoggingSessionItem] = []
    private var cancellables = Set<AnyCancellable>()

    /// The KMP Flow observation jobs. Cancelled when this ViewModel is deallocated.
    private var workoutObservationJob: Kotlinx_coroutines_coreJob?
    private var joggingObservationJob: Kotlinx_coroutines_coreJob?

    // MARK: - Derived State

    var isEmpty: Bool { filteredSections.isEmpty }
    var hasAnyData: Bool { !allItems.isEmpty }

    // MARK: - Init

    init() {
        bindFilterPipeline()
    }

    deinit {
        workoutObservationJob?.cancel(cause: nil)
        joggingObservationJob?.cancel(cause: nil)
    }

    // MARK: - Actions

    /// Starts observing the local database. Call once on first appear.
    func startObserving() async {
        guard workoutObservationJob == nil else { return }
        isLoading = true

        guard let user = await AuthService.shared.getCurrentUser() else {
            isLoading = false
            return
        }
        let userId = user.id

        // Observe push-up workout sessions
        workoutObservationJob = DataBridge.shared.observeSessions(userId: userId) { [weak self] kmpSessions in
            guard let self else { return }
            self.pushUpSessions = kmpSessions.compactMap { Self.mapPushUp(kmpSession: $0) }
            self.mergeAllItems()
            self.isLoading = false
            self.isRefreshing = false
        }

        // Observe jogging sessions
        joggingObservationJob = DataBridge.shared.observeJoggingSessions(userId: userId) { [weak self] kmpSessions in
            guard let self else { return }
            self.joggingSessions = kmpSessions.compactMap { Self.mapJogging(kmpSession: $0) }
            self.mergeAllItems()
            self.isLoading = false
            self.isRefreshing = false
        }
    }

    /// Triggered by pull-to-refresh -- the Flow already keeps data live,
    /// so this just shows the refreshing indicator briefly.
    func refresh() async {
        guard !isRefreshing, !isLoading else { return }
        isRefreshing = true
        try? await Task.sleep(for: .milliseconds(500))
        isRefreshing = false
    }

    func clearError() { errorMessage = nil }

    func requestDelete(_ item: HistoryItem) {
        itemPendingDeletion = item
        showDeleteConfirmation = true
    }

    func confirmDelete() {
        guard let item = itemPendingDeletion else { return }
        allItems.removeAll { $0.id == item.id }
        itemPendingDeletion = nil
        showDeleteConfirmation = false
    }

    func cancelDelete() {
        itemPendingDeletion = nil
        showDeleteConfirmation = false
    }

    // MARK: - Private: Merge

    private func mergeAllItems() {
        var merged: [HistoryItem] = []
        merged.append(contentsOf: pushUpSessions.map { .pushUp($0) })
        merged.append(contentsOf: joggingSessions.map { .jogging($0) })
        // Sort by start date descending (most recent first)
        merged.sort { $0.startDate > $1.startDate }
        allItems = merged
    }

    // MARK: - Private: Reactive Filter Pipeline

    private func bindFilterPipeline() {
        let itemsPublisher = $allItems
        let filterPublisher   = $selectedFilter
        let searchPublisher   = $searchText
            .debounce(for: .milliseconds(300), scheduler: RunLoop.main)
            .removeDuplicates()

        Publishers.CombineLatest3(itemsPublisher, filterPublisher, searchPublisher)
            .map { [weak self] items, filter, searchText in
                guard let self else { return [] }
                let filtered = self.applyFilters(items: items, filter: filter, searchText: searchText)
                return self.groupedByDay(filtered)
            }
            .receive(on: RunLoop.main)
            .assign(to: &$filteredSections)
    }

    // MARK: - Private: Filtering

    private func applyFilters(
        items: [HistoryItem],
        filter: HistoryFilter,
        searchText: String
    ) -> [HistoryItem] {
        var result = items

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
            result = result.filter { item in
                item.shortDateString.lowercased().contains(query) ||
                Self.searchDateFormatter.string(from: item.startDate).lowercased().contains(query) ||
                Self.isoDateFormatter.string(from: item.startDate).lowercased().contains(query)
            }
        }

        return result
    }

    // MARK: - Private: Grouping

    private func groupedByDay(_ items: [HistoryItem]) -> [HistorySection] {
        let calendar = Calendar.current
        let today     = calendar.startOfDay(for: Date())
        let yesterday = calendar.date(byAdding: .day, value: -1, to: today) ?? today

        var groups: [(key: String, items: [HistoryItem])] = []
        var seen: [String: Int] = [:]

        for item in items {
            let dayKey = Self.isoDateFormatter.string(from: item.startDate)
            if let idx = seen[dayKey] {
                groups[idx].items.append(item)
            } else {
                seen[dayKey] = groups.count
                groups.append((key: dayKey, items: [item]))
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

            return HistorySection(id: group.key, title: title, items: group.items)
        }
    }

    // MARK: - Private: KMP -> View Model Mapping

    /// Maps a KMP `WorkoutSession` to the view-layer `PushUpSession`.
    /// Only completed sessions (endedAt != nil) are shown in history.
    private static func mapPushUp(kmpSession: Shared.WorkoutSession) -> PushUpSession? {
        guard let endedAtInstant = kmpSession.endedAt else { return nil }

        let startMs  = kmpSession.startedAt.epochSeconds * 1_000 + Int64(kmpSession.startedAt.nanosecondsOfSecond) / 1_000_000
        let endMs    = endedAtInstant.epochSeconds * 1_000 + Int64(endedAtInstant.nanosecondsOfSecond) / 1_000_000
        let startDate = Date(timeIntervalSince1970: Double(startMs) / 1_000.0)
        let duration  = max(0, Int((endMs - startMs) / 1_000))

        return PushUpSession(
            id: UUID(uuidString: kmpSession.id) ?? UUID(),
            startDate: startDate,
            pushUpCount: Int(kmpSession.pushUpCount),
            durationSeconds: duration,
            earnedMinutes: Int(kmpSession.earnedTimeCreditSeconds / 60),
            averageQuality: Double(kmpSession.quality),
            records: []
        )
    }

    /// Maps a KMP `JoggingSession` to the view-layer `JoggingSessionItem`.
    /// Only completed sessions (endedAt != nil) are shown in history.
    private static func mapJogging(kmpSession: Shared.JoggingSession) -> JoggingSessionItem? {
        guard kmpSession.endedAt != nil else { return nil }

        let startMs = kmpSession.startedAt.epochSeconds * 1_000 + Int64(kmpSession.startedAt.nanosecondsOfSecond) / 1_000_000
        let startDate = Date(timeIntervalSince1970: Double(startMs) / 1_000.0)

        return JoggingSessionItem(
            id: UUID(uuidString: kmpSession.id) ?? UUID(),
            kmpSessionId: kmpSession.id,
            startDate: startDate,
            distanceMeters: kmpSession.distanceMeters,
            durationSeconds: Int(kmpSession.durationSeconds),
            avgPaceSecondsPerKm: kmpSession.avgPaceSecondsPerKm?.intValue,
            caloriesBurned: Int(kmpSession.caloriesBurned),
            earnedMinutes: Int(kmpSession.earnedTimeCreditSeconds / 60)
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
