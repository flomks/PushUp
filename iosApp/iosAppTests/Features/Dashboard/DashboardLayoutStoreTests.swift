import Foundation
import Testing

@testable import iosApp

// MARK: - DashboardWidgetLayoutCodingTests

@Suite("DashboardWidgetLayoutCoding")
struct DashboardWidgetLayoutCodingTests {

    @Test("parse JSON array preserves order and deduplicates")
    func parseDedupes() {
        let json = #"["timeCredit","nope","timeCredit","dailyStats"]"#
        let w = DashboardWidgetLayoutCoding.widgets(fromJsonUtf8: json)
        #expect(w == [.timeCredit, .dailyStats])
    }

    @Test("parse invalid JSON falls back to default order")
    func parseInvalidFallback() {
        let w = DashboardWidgetLayoutCoding.widgets(fromJsonUtf8: "not-json")
        #expect(w == DashboardWidgetKind.defaultOrder)
    }

    @Test("encode then decode round-trip")
    func encodeRoundTrip() {
        let original = [DashboardWidgetKind.weeklyChart, DashboardWidgetKind.timeCredit]
        let str = DashboardWidgetLayoutCoding.jsonString(from: original)
        #expect(str != nil)
        let back = DashboardWidgetLayoutCoding.widgets(fromJsonUtf8: str!)
        #expect(back == original)
    }

    @Test("new dashboard widget kinds round-trip JSON")
    func newKindsRoundTrip() {
        let original: [DashboardWidgetKind] = [
            .pushUpsThisWeek, .runDistanceWeek, .streakCurrent, .shortcutStats, .creditEarnedToday,
        ]
        let str = DashboardWidgetLayoutCoding.jsonString(from: original)
        #expect(str != nil)
        let back = DashboardWidgetLayoutCoding.widgets(fromJsonUtf8: str!)
        #expect(back == original)
    }

    @Test("default order stays the original six core widgets")
    func defaultOrderIsCoreOnly() {
        #expect(DashboardWidgetKind.defaultOrder.count == 6)
        #expect(DashboardWidgetKind.defaultOrder.contains(.timeCredit))
        #expect(DashboardWidgetKind.defaultOrder.contains(.workoutQuickAction))
        #expect(DashboardWidgetKind.allCases.count > DashboardWidgetKind.defaultOrder.count)
    }

    @Test("empty JSON array stays empty (shows empty dashboard UI)")
    func parseEmptyArray() {
        let w = DashboardWidgetLayoutCoding.widgets(fromJsonUtf8: "[]")
        #expect(w.isEmpty)
        let encoded = DashboardWidgetLayoutCoding.jsonString(from: [])
        #expect(encoded == "[]")
    }

    @Test("legacy UserDefaults Data decodes like JSON Data")
    func legacyData() {
        let data = try! JSONEncoder().encode(["screenTime", "workoutQuickAction"])
        let w = DashboardWidgetLayoutCoding.widgets(fromLegacyDefaultsData: data)
        #expect(w == [.screenTime, .workoutQuickAction])
    }
}

// MARK: - DashboardLayoutStore static load (guest / tests)

@Suite("DashboardLayoutStore.load legacy")
struct DashboardLayoutStoreLoadTests {

    private func isolatedDefaults() -> (UserDefaults, String, String) {
        let suite = "test.DashboardLayoutLegacy.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suite) else {
            preconditionFailure("UserDefaults(suiteName:) returned nil")
        }
        defaults.removePersistentDomain(forName: suite)
        let key = "legacy.widgets"
        return (defaults, key, suite)
    }

    @Test("load reads encoded widget order from UserDefaults data")
    @MainActor
    func loadFromDefaultsData() {
        let (defaults, key, suite) = isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }

        let data = try! JSONEncoder().encode(["dailyStats", "weeklyChart"])
        defaults.set(data, forKey: key)

        let loaded = DashboardLayoutStore.load(from: defaults, key: key)
        #expect(loaded == [.dailyStats, .weeklyChart])
    }
}
