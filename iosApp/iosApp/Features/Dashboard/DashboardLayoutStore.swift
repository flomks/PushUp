import Foundation
import Combine
import Shared

// MARK: - DashboardWidgetLayoutCoding

/// Shared parse/encode logic (used by the store and unit tests).
enum DashboardWidgetLayoutCoding {

    static func widgets(fromJsonUtf8 string: String) -> [DashboardWidgetKind] {
        guard let data = string.data(using: .utf8),
              let rawStrings = try? JSONDecoder().decode([String].self, from: data)
        else {
            return DashboardWidgetKind.defaultOrder
        }
        // Explicit `[]` means “user cleared the dashboard” — keep empty (do not substitute defaultOrder).
        if rawStrings.isEmpty {
            return []
        }
        var seen = Set<DashboardWidgetKind>()
        var result: [DashboardWidgetKind] = []
        for s in rawStrings {
            guard let kind = DashboardWidgetKind(rawValue: s), !seen.contains(kind) else { continue }
            seen.insert(kind)
            result.append(kind)
        }
        // Non-empty JSON but no valid widget ids → treat as corrupt, fall back to default.
        return result.isEmpty ? DashboardWidgetKind.defaultOrder : result
    }

    static func jsonString(from widgets: [DashboardWidgetKind]) -> String? {
        let strings = widgets.map(\.rawValue)
        guard let data = try? JSONEncoder().encode(strings) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    /// Legacy `UserDefaults` payload (Data) from before cloud-backed settings.
    static func widgets(fromLegacyDefaultsData data: Data) -> [DashboardWidgetKind] {
        guard let rawStrings = try? JSONDecoder().decode([String].self, from: data) else {
            return DashboardWidgetKind.defaultOrder
        }
        if rawStrings.isEmpty {
            return []
        }
        var seen = Set<DashboardWidgetKind>()
        var result: [DashboardWidgetKind] = []
        for s in rawStrings {
            guard let kind = DashboardWidgetKind(rawValue: s), !seen.contains(kind) else { continue }
            seen.insert(kind)
            result.append(kind)
        }
        return result.isEmpty ? DashboardWidgetKind.defaultOrder : result
    }
}

// MARK: - DashboardLayoutStore

/// Dashboard widget order is stored in the KMP `UserSettings` row (local SQLite + Supabase
/// `user_settings.dashboard_widget_order_json`), matching other per-account settings.
@MainActor
final class DashboardLayoutStore: ObservableObject {

    @Published private(set) var orderedWidgets: [DashboardWidgetKind]

    private var observeJob: Kotlinx_coroutines_coreJob?
    private var syncUserId: String?
    private var didAttemptLegacyMigration = false
    /// Ensures we only write default layout once when DB/Flow still has no JSON (`nil`) — matches on-screen default widgets.
    private var didSeedDefaultWhenDashboardJsonUnset = false
    /// Avoids a feedback loop: each `move` was persisting immediately, the DB Flow echoed the same JSON,
    /// and re-applying it re-published `orderedWidgets` while the system drag was still resolving — jitter + extra haptics.
    private var persistDebounceTask: Task<Void, Never>?

    init() {
        orderedWidgets = DashboardWidgetKind.defaultOrder
    }

    /// Starts observing `UserSettings.dashboardWidgetOrderJson` for [userId]. Call when the user id is known.
    func startObserving(userId: String) {
        guard !userId.isEmpty else { return }
        syncUserId = userId
        didSeedDefaultWhenDashboardJsonUnset = false
        observeJob?.cancel(cause: nil)
        observeJob = DataBridge.shared.observeDashboardWidgetOrderJson(userId: userId) { [weak self] json in
            Task { @MainActor in
                self?.applyDatabaseOrMigrate(json: json, userId: userId)
            }
        }
    }

    func stopObserving() {
        finishDebouncedPersistIfScheduled()
        observeJob?.cancel(cause: nil)
        observeJob = nil
    }

    func move(fromOffsets source: IndexSet, toOffset destination: Int) {
        var next = orderedWidgets
        next.move(fromOffsets: source, toOffset: destination)
        guard next != orderedWidgets else { return }
        orderedWidgets = next
        schedulePersistDebounced()
    }

    func remove(atOffsets offsets: IndexSet) {
        cancelPersistDebounce()
        var next = orderedWidgets
        next.remove(atOffsets: offsets)
        orderedWidgets = next
        persistNow()
    }

    func add(_ kind: DashboardWidgetKind) {
        guard !orderedWidgets.contains(kind) else { return }
        cancelPersistDebounce()
        orderedWidgets.append(kind)
        persistNow()
    }

    func resetToDefault() {
        cancelPersistDebounce()
        orderedWidgets = DashboardWidgetKind.defaultOrder
        persistNow()
    }

    /// If a reorder debounce is still pending, cancel it and persist now (e.g. when leaving edit mode).
    func finishDebouncedPersistIfScheduled() {
        guard persistDebounceTask != nil else { return }
        cancelPersistDebounce()
        persistNow()
    }

    // MARK: - Remote / legacy

    private func applyDatabaseOrMigrate(json: String?, userId: String) {
        if let json, !json.isEmpty {
            let parsed = DashboardWidgetLayoutCoding.widgets(fromJsonUtf8: json)
            if parsed == orderedWidgets { return }
            orderedWidgets = parsed
            return
        }

        // Flow can briefly emit nil/blank after a local write; don’t replace an intentional empty dashboard
        // with the default widget set again.
        let jsonMissingOrBlank = json == nil || json?.isEmpty == true
        if jsonMissingOrBlank && orderedWidgets.isEmpty {
            return
        }

        if !didAttemptLegacyMigration {
            didAttemptLegacyMigration = true
            let legacyKey = SettingsKeys.dashboardWidgetOrder
            if let data = UserDefaults.standard.data(forKey: legacyKey) {
                orderedWidgets = DashboardWidgetLayoutCoding.widgets(fromLegacyDefaultsData: data)
                UserDefaults.standard.removeObject(forKey: legacyKey)
                persistNow()
                return
            }
        }

        // Flow can briefly emit nil after a write; never replace a user-edited order with the full default.
        if orderedWidgets != DashboardWidgetKind.defaultOrder {
            return
        }

        orderedWidgets = DashboardWidgetKind.defaultOrder
        // Fresh install / row exists but `dashboardWidgetOrderJson` is still NULL: UI shows default widgets while DB had
        // nothing — persist once so remove/reorder matches storage (local + Supabase after push).
        guard !didSeedDefaultWhenDashboardJsonUnset else { return }
        didSeedDefaultWhenDashboardJsonUnset = true
        persistNow()
    }

    private func cancelPersistDebounce() {
        persistDebounceTask?.cancel()
        persistDebounceTask = nil
    }

    private func schedulePersistDebounced() {
        persistDebounceTask?.cancel()
        persistDebounceTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(420))
            guard let self, !Task.isCancelled else { return }
            self.persistDebounceTask = nil
            self.persistNow()
        }
    }

    private func persistNow() {
        guard let json = DashboardWidgetLayoutCoding.jsonString(from: orderedWidgets) else { return }

        guard let userId = syncUserId, !userId.isEmpty else {
            if let data = json.data(using: .utf8) {
                UserDefaults.standard.set(data, forKey: SettingsKeys.dashboardWidgetOrder)
            }
            return
        }

        DataBridge.shared.saveDashboardWidgetOrderJson(userId: userId, json: json) { _ in }
    }

    // MARK: - Tests only

    static func load(from defaults: UserDefaults, key: String) -> [DashboardWidgetKind] {
        guard let data = defaults.data(forKey: key) else {
            return DashboardWidgetKind.defaultOrder
        }
        return DashboardWidgetLayoutCoding.widgets(fromLegacyDefaultsData: data)
    }
}
