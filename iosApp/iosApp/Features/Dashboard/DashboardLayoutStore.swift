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

    init() {
        orderedWidgets = DashboardWidgetKind.defaultOrder
    }

    /// Starts observing `UserSettings.dashboardWidgetOrderJson` for [userId]. Call when the user id is known.
    func startObserving(userId: String) {
        guard !userId.isEmpty else { return }
        syncUserId = userId
        observeJob?.cancel(cause: nil)
        observeJob = DataBridge.shared.observeDashboardWidgetOrderJson(userId: userId) { [weak self] json in
            Task { @MainActor in
                self?.applyDatabaseOrMigrate(json: json, userId: userId)
            }
        }
    }

    func stopObserving() {
        observeJob?.cancel(cause: nil)
        observeJob = nil
    }

    func move(fromOffsets source: IndexSet, toOffset destination: Int) {
        var next = orderedWidgets
        next.move(fromOffsets: source, toOffset: destination)
        orderedWidgets = next
        persist()
    }

    func remove(atOffsets offsets: IndexSet) {
        var next = orderedWidgets
        next.remove(atOffsets: offsets)
        orderedWidgets = next
        persist()
    }

    func add(_ kind: DashboardWidgetKind) {
        guard !orderedWidgets.contains(kind) else { return }
        orderedWidgets.append(kind)
        persist()
    }

    func resetToDefault() {
        orderedWidgets = DashboardWidgetKind.defaultOrder
        persist()
    }

    // MARK: - Remote / legacy

    private func applyDatabaseOrMigrate(json: String?, userId: String) {
        if let json, !json.isEmpty {
            orderedWidgets = DashboardWidgetLayoutCoding.widgets(fromJsonUtf8: json)
            return
        }

        if !didAttemptLegacyMigration {
            didAttemptLegacyMigration = true
            let legacyKey = SettingsKeys.dashboardWidgetOrder
            if let data = UserDefaults.standard.data(forKey: legacyKey) {
                orderedWidgets = DashboardWidgetLayoutCoding.widgets(fromLegacyDefaultsData: data)
                UserDefaults.standard.removeObject(forKey: legacyKey)
                persist()
                return
            }
        }

        orderedWidgets = DashboardWidgetKind.defaultOrder
    }

    private func persist() {
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
