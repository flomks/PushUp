import Foundation
import Combine
import Shared

// MARK: - DashboardItemCoding

/// Parse / encode logic for the new item-based dashboard layout JSON.
///
/// Format: a JSON array where each element is either:
/// - A `String` (standalone widget raw value), or
/// - An object `{"grid": "1x2", "slots": ["widgetA", null, ...]}`.
enum DashboardItemCoding {

    static let defaultItems: [DashboardItem] = DashboardWidgetKind.defaultOrder.map { .widget($0) }

    // MARK: Decode

    static func items(fromJsonUtf8 string: String) -> [DashboardItem] {
        guard let data = string.data(using: .utf8),
              let rawArray = try? JSONSerialization.jsonObject(with: data) as? [Any]
        else {
            return defaultItems
        }
        if rawArray.isEmpty { return [] }

        var seen = Set<DashboardWidgetKind>()
        var result: [DashboardItem] = []

        for element in rawArray {
            if let str = element as? String {
                guard let kind = DashboardWidgetKind(rawValue: str), !seen.contains(kind) else { continue }
                seen.insert(kind)
                result.append(.widget(kind))
            } else if let dict = element as? [String: Any],
                      let gridSizeStr = dict["grid"] as? String,
                      let gridSize = DashboardGridSize(rawValue: gridSizeStr),
                      let slotsRaw = dict["slots"] as? [Any] {
                var slots: [DashboardWidgetKind?] = []
                for slotElement in slotsRaw.prefix(gridSize.capacity) {
                    if let str = slotElement as? String,
                       let kind = DashboardWidgetKind(rawValue: str),
                       !seen.contains(kind) {
                        seen.insert(kind)
                        slots.append(kind)
                    } else {
                        slots.append(nil)
                    }
                }
                while slots.count < gridSize.capacity { slots.append(nil) }
                result.append(.grid(id: UUID(), size: gridSize, slots: slots))
            }
        }
        return result.isEmpty ? defaultItems : result
    }

    // MARK: Encode

    static func jsonString(from items: [DashboardItem]) -> String? {
        var array: [Any] = []
        for item in items {
            switch item {
            case .widget(let kind):
                array.append(kind.rawValue)
            case .grid(_, let size, let slots):
                let slotsArray: [Any] = slots.map { kind -> Any in
                    if let kind { return kind.rawValue }
                    return NSNull()
                }
                array.append(["grid": size.rawValue, "slots": slotsArray] as [String: Any])
            }
        }
        guard let data = try? JSONSerialization.data(withJSONObject: array),
              let str = String(data: data, encoding: .utf8)
        else { return nil }
        return str
    }
}

// MARK: - DashboardLayoutStore

@MainActor
final class DashboardLayoutStore: ObservableObject {

    @Published var orderedItems: [DashboardItem]

    private var observeJob: Kotlinx_coroutines_coreJob?
    private var syncUserId: String?
    private var didAttemptLegacyMigration = false
    private var didSeedDefaultWhenDashboardJsonUnset = false
    private var persistDebounceTask: Task<Void, Never>?
    private var lastPersistedItems: [DashboardItem]?
    private var suppressStaleFlowEmissionsUntil: Date?

    private static let localCacheKey = "dashboard.widgetOrderCache"

    // MARK: - Init

    init() {
        orderedItems = Self.loadFromLocalCache()
    }

    private static func loadFromLocalCache() -> [DashboardItem] {
        guard let json = UserDefaults.standard.string(forKey: localCacheKey),
              !json.isEmpty else {
            return DashboardItemCoding.defaultItems
        }
        return DashboardItemCoding.items(fromJsonUtf8: json)
    }

    private func saveToLocalCache() {
        guard let json = DashboardItemCoding.jsonString(from: orderedItems) else { return }
        UserDefaults.standard.set(json, forKey: Self.localCacheKey)
    }

    // MARK: - Computed

    /// Every widget kind currently used — standalone or inside any grid.
    var allUsedWidgetKinds: Set<DashboardWidgetKind> {
        orderedItems.reduce(into: Set()) { $0.formUnion($1.usedWidgetKinds) }
    }

    // MARK: - Observe

    func startObserving(userId: String) {
        guard !userId.isEmpty else { return }
        syncUserId = userId
        didSeedDefaultWhenDashboardJsonUnset = false
        lastPersistedItems = nil
        suppressStaleFlowEmissionsUntil = nil
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

    // MARK: - Item CRUD

    func move(fromOffsets source: IndexSet, toOffset destination: Int) {
        var next = orderedItems
        next.move(fromOffsets: source, toOffset: destination)
        guard next != orderedItems else { return }
        orderedItems = next
        schedulePersistDebounced()
    }

    func schedulePersistAfterReorder() {
        schedulePersistDebounced()
    }

    func removeItem(at index: Int) {
        cancelPersistDebounce()
        var next = orderedItems
        next.remove(at: index)
        orderedItems = next
        persistNow()
    }

    func addWidget(_ kind: DashboardWidgetKind) {
        guard !allUsedWidgetKinds.contains(kind) else { return }
        cancelPersistDebounce()
        orderedItems.append(.widget(kind))
        persistNow()
    }

    func addGrid(_ size: DashboardGridSize) {
        cancelPersistDebounce()
        let slots = [DashboardWidgetKind?](repeating: nil, count: size.capacity)
        orderedItems.append(.grid(id: UUID(), size: size, slots: slots))
        persistNow()
    }

    func setGridSlot(gridId: String, slotIndex: Int, kind: DashboardWidgetKind) {
        guard let itemIndex = orderedItems.firstIndex(where: { $0.id == gridId }),
              case .grid(let id, let size, var slots) = orderedItems[itemIndex],
              slotIndex < slots.count
        else { return }
        cancelPersistDebounce()
        slots[slotIndex] = kind
        orderedItems[itemIndex] = .grid(id: id, size: size, slots: slots)
        persistNow()
    }

    func clearGridSlot(gridId: String, slotIndex: Int) {
        guard let itemIndex = orderedItems.firstIndex(where: { $0.id == gridId }),
              case .grid(let id, let size, var slots) = orderedItems[itemIndex],
              slotIndex < slots.count
        else { return }
        cancelPersistDebounce()
        slots[slotIndex] = nil
        orderedItems[itemIndex] = .grid(id: id, size: size, slots: slots)
        persistNow()
    }

    func resetToDefault() {
        cancelPersistDebounce()
        orderedItems = DashboardItemCoding.defaultItems
        persistNow()
    }

    func finishDebouncedPersistIfScheduled() {
        guard persistDebounceTask != nil else { return }
        cancelPersistDebounce()
        persistNow()
    }

    // MARK: - Remote / legacy

    private func applyDatabaseOrMigrate(json: String?, userId: String) {
        if let json, !json.isEmpty {
            let parsed = DashboardItemCoding.items(fromJsonUtf8: json)
            // Stale-emission guard: ignore echoed-back JSON that matches what we just wrote.
            if let expected = lastPersistedItems, parsed == expected {
                suppressStaleFlowEmissionsUntil = nil
            } else if let until = suppressStaleFlowEmissionsUntil, Date() < until {
                return
            }
            if parsed == orderedItems { return }
            orderedItems = parsed
            saveToLocalCache()
            return
        }

        let jsonMissingOrBlank = json == nil || json?.isEmpty == true
        if jsonMissingOrBlank && orderedItems.isEmpty {
            return
        }

        if !didAttemptLegacyMigration {
            didAttemptLegacyMigration = true
            let legacyKey = SettingsKeys.dashboardWidgetOrder
            if let data = UserDefaults.standard.data(forKey: legacyKey) {
                let legacyWidgets = legacyWidgets(fromData: data)
                orderedItems = legacyWidgets.map { .widget($0) }
                UserDefaults.standard.removeObject(forKey: legacyKey)
                persistNow()
                return
            }
        }

        if orderedItems != DashboardItemCoding.defaultItems {
            return
        }

        orderedItems = DashboardItemCoding.defaultItems
        guard !didSeedDefaultWhenDashboardJsonUnset else { return }
        didSeedDefaultWhenDashboardJsonUnset = true
        persistNow()
    }

    private func legacyWidgets(fromData data: Data) -> [DashboardWidgetKind] {
        guard let rawStrings = try? JSONDecoder().decode([String].self, from: data) else {
            return DashboardWidgetKind.defaultOrder
        }
        if rawStrings.isEmpty { return [] }
        var seen = Set<DashboardWidgetKind>()
        var result: [DashboardWidgetKind] = []
        for s in rawStrings {
            guard let kind = DashboardWidgetKind(rawValue: s), !seen.contains(kind) else { continue }
            seen.insert(kind)
            result.append(kind)
        }
        return result.isEmpty ? DashboardWidgetKind.defaultOrder : result
    }

    // MARK: - Persist

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
        guard let json = DashboardItemCoding.jsonString(from: orderedItems) else { return }
        lastPersistedItems = orderedItems
        suppressStaleFlowEmissionsUntil = Date().addingTimeInterval(1.0)
        saveToLocalCache()

        guard let userId = syncUserId, !userId.isEmpty else {
            if let data = json.data(using: .utf8) {
                UserDefaults.standard.set(data, forKey: SettingsKeys.dashboardWidgetOrder)
            }
            return
        }

        DataBridge.shared.saveDashboardWidgetOrderJson(userId: userId, json: json) { _ in }
    }
}
