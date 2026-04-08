import Foundation
import Testing

@testable import iosApp

// MARK: - DashboardItemCodingTests

@Suite("DashboardItemCoding")
struct DashboardItemCodingTests {

    @Test("parse flat JSON array of widget strings")
    func parseFlatArray() {
        let json = #"["timeCredit","nope","timeCredit","dailyStats"]"#
        let items = DashboardItemCoding.items(fromJsonUtf8: json)
        #expect(items.count == 2)
        if case .widget(let k1) = items[0] { #expect(k1 == .timeCredit) }
        if case .widget(let k2) = items[1] { #expect(k2 == .dailyStats) }
    }

    @Test("parse invalid JSON falls back to default items")
    func parseInvalidFallback() {
        let items = DashboardItemCoding.items(fromJsonUtf8: "not-json")
        #expect(items == DashboardItemCoding.defaultItems)
    }

    @Test("parse grid object inside array")
    func parseGrid() {
        let json = #"["timeCredit",{"grid":"1x2","slots":["pushUpsThisWeek","streakCurrent"]},"dailyStats"]"#
        let items = DashboardItemCoding.items(fromJsonUtf8: json)
        #expect(items.count == 3)
        if case .widget(let k1) = items[0] { #expect(k1 == .timeCredit) }
        if case .grid(_, let size, let slots) = items[1] {
            #expect(size == .oneByTwo)
            #expect(slots == [.pushUpsThisWeek, .streakCurrent])
        } else {
            Issue.record("Expected grid item at index 1")
        }
        if case .widget(let k3) = items[2] { #expect(k3 == .dailyStats) }
    }

    @Test("parse 2x2 grid with null slots")
    func parse2x2GridWithNulls() {
        let json = #"[{"grid":"2x2","slots":["pushUpsThisWeek",null,"streakCurrent",null]}]"#
        let items = DashboardItemCoding.items(fromJsonUtf8: json)
        #expect(items.count == 1)
        if case .grid(_, let size, let slots) = items[0] {
            #expect(size == .twoByTwo)
            #expect(slots.count == 4)
            #expect(slots[0] == .pushUpsThisWeek)
            #expect(slots[1] == nil)
            #expect(slots[2] == .streakCurrent)
            #expect(slots[3] == nil)
        } else {
            Issue.record("Expected grid item")
        }
    }

    @Test("encode then decode round-trip with grids")
    func encodeRoundTripGrid() {
        let original: [DashboardItem] = [
            .widget(.weeklyChart),
            .grid(id: UUID(), size: .oneByTwo, slots: [.pushUpsThisWeek, .streakCurrent]),
            .widget(.timeCredit),
        ]
        let str = DashboardItemCoding.jsonString(from: original)
        #expect(str != nil)
        let back = DashboardItemCoding.items(fromJsonUtf8: str!)
        #expect(back.count == 3)
        if case .widget(let k) = back[0] { #expect(k == .weeklyChart) }
        if case .grid(_, let size, let slots) = back[1] {
            #expect(size == .oneByTwo)
            #expect(slots == [.pushUpsThisWeek, .streakCurrent])
        }
        if case .widget(let k) = back[2] { #expect(k == .timeCredit) }
    }

    @Test("empty JSON array stays empty")
    func parseEmptyArray() {
        let items = DashboardItemCoding.items(fromJsonUtf8: "[]")
        #expect(items.isEmpty)
        let encoded = DashboardItemCoding.jsonString(from: [])
        #expect(encoded == "[]")
    }

    @Test("default items match default widget order")
    func defaultItems() {
        #expect(DashboardItemCoding.defaultItems.count == DashboardWidgetKind.defaultOrder.count)
    }

    @Test("grid deduplicates widgets already used standalone")
    func gridDeduplicatesWithStandalone() {
        let json = #"["pushUpsThisWeek",{"grid":"1x2","slots":["pushUpsThisWeek","streakCurrent"]}]"#
        let items = DashboardItemCoding.items(fromJsonUtf8: json)
        #expect(items.count == 2)
        if case .grid(_, _, let slots) = items[1] {
            // pushUpsThisWeek already used as standalone, so grid slot should be nil
            #expect(slots[0] == nil)
            #expect(slots[1] == .streakCurrent)
        }
    }
}

// MARK: - DashboardWidgetKind grid eligibility

@Suite("DashboardWidgetKind.isGridEligible")
struct DashboardWidgetKindGridTests {

    @Test("core widgets are not grid-eligible")
    func coreNotEligible() {
        #expect(!DashboardWidgetKind.timeCredit.isGridEligible)
        #expect(!DashboardWidgetKind.screenTime.isGridEligible)
        #expect(!DashboardWidgetKind.dailyStats.isGridEligible)
        #expect(!DashboardWidgetKind.weeklyChart.isGridEligible)
        #expect(!DashboardWidgetKind.activitySummary.isGridEligible)
        #expect(!DashboardWidgetKind.workoutQuickAction.isGridEligible)
        #expect(!DashboardWidgetKind.upcomingRuns.isGridEligible)
    }

    @Test("mini-stat widgets are grid-eligible")
    func miniStatsEligible() {
        #expect(DashboardWidgetKind.pushUpsThisWeek.isGridEligible)
        #expect(DashboardWidgetKind.streakCurrent.isGridEligible)
        #expect(DashboardWidgetKind.runDistanceWeek.isGridEligible)
        #expect(DashboardWidgetKind.creditEarnedToday.isGridEligible)
    }

    @Test("shortcut widgets are grid-eligible")
    func shortcutsEligible() {
        #expect(DashboardWidgetKind.shortcutStats.isGridEligible)
        #expect(DashboardWidgetKind.shortcutProfile.isGridEligible)
    }
}
