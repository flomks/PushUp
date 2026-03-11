import DeviceActivity
import ManagedSettings
import FamilyControls
import Foundation
import UserNotifications

// MARK: - DeviceActivityMonitorExtension

/// DeviceActivity Monitor Extension.
///
/// This extension runs in a **separate process** from the main app.
/// It receives callbacks from the system when DeviceActivity thresholds
/// are reached. All communication with the main app happens via the
/// shared App Group UserDefaults container: `group.com.flomks.pushup`
///
/// **Registered events:**
/// - `com.flomks.pushup.warning`      -- 80% of credit consumed
/// - `com.flomks.pushup.limitReached` -- 100% of credit consumed (block)
///
/// **Bundle ID:** `com.flomks.pushup.ScreenTimeMonitor`
class DeviceActivityMonitorExtension: DeviceActivityMonitor {

    private let store = ManagedSettingsStore()
    private let sharedDefaults = UserDefaults(suiteName: "group.com.flomks.pushup")

    // MARK: - Interval Lifecycle

    override func intervalDidStart(for activity: DeviceActivityName) {
        super.intervalDidStart(for: activity)
        // New day started -- unblock apps so the user starts fresh.
        unblockApps()
        sharedDefaults?.set(false, forKey: "screentime.isBlocking")
    }

    override func intervalDidEnd(for activity: DeviceActivityName) {
        super.intervalDidEnd(for: activity)
        // Day ended -- unblock so tomorrow starts clean.
        unblockApps()
        sharedDefaults?.set(false, forKey: "screentime.isBlocking")
    }

    override func intervalWillStartWarning(for activity: DeviceActivityName) {
        super.intervalWillStartWarning(for: activity)
    }

    override func intervalWillEndWarning(for activity: DeviceActivityName) {
        super.intervalWillEndWarning(for: activity)
    }

    // MARK: - Threshold Events

    override func eventDidReachThreshold(
        _ event: DeviceActivityEvent.Name,
        activity: DeviceActivityName
    ) {
        super.eventDidReachThreshold(event, activity: activity)

        switch event.rawValue {
        case "com.flomks.pushup.warning":
            handleWarning()
        case "com.flomks.pushup.limitReached":
            handleLimitReached()
        default:
            break
        }
    }

    override func eventWillReachThresholdWarning(
        _ event: DeviceActivityEvent.Name,
        activity: DeviceActivityName
    ) {
        super.eventWillReachThresholdWarning(event, activity: activity)
    }

    // MARK: - Warning (80% consumed)

    private func handleWarning() {
        let content = UNMutableNotificationContent()
        content.title = "Time Credit Running Low"
        content.body = "You have about 5 minutes of screen time credit left. Do some push-ups to earn more!"
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: "screentime.warning.\(Date().timeIntervalSince1970)",
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request) { _ in }
    }

    // MARK: - Limit Reached (100% consumed -- block apps)

    private func handleLimitReached() {
        blockSelectedApps()
        sharedDefaults?.set(true, forKey: "screentime.isBlocking")
        updateTodayUsageRecord(creditExhausted: true)

        let content = UNMutableNotificationContent()
        content.title = "Time Credit Exhausted"
        content.body = "Your screen time credit has run out. Open PushUp and do some push-ups to earn more time!"
        content.sound = .default
        content.categoryIdentifier = "SCREEN_TIME_BLOCKED"

        let workoutAction = UNNotificationAction(
            identifier: "START_WORKOUT",
            title: "Start Workout",
            options: [.foreground]
        )
        let category = UNNotificationCategory(
            identifier: "SCREEN_TIME_BLOCKED",
            actions: [workoutAction],
            intentIdentifiers: [],
            options: []
        )
        UNUserNotificationCenter.current().setNotificationCategories([category])

        let request = UNNotificationRequest(
            identifier: "screentime.blocked.\(Date().timeIntervalSince1970)",
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request) { _ in }
    }

    // MARK: - App Blocking

    private func blockSelectedApps() {
        guard let data = sharedDefaults?.data(forKey: "screentime.activitySelection"),
              let selection = try? JSONDecoder().decode(FamilyActivitySelection.self, from: data)
        else { return }

        if !selection.applicationTokens.isEmpty {
            store.shield.applications = selection.applicationTokens
        }
        if !selection.categoryTokens.isEmpty {
            store.shield.applicationCategories = .specific(selection.categoryTokens)
        }
        if !selection.webDomainTokens.isEmpty {
            store.shield.webDomainCategories = .specific(selection.webDomainTokens)
        }
    }

    private func unblockApps() {
        store.shield.applications = nil
        store.shield.applicationCategories = nil
        store.shield.webDomainCategories = nil
    }

    // MARK: - Usage Recording

    private func updateTodayUsageRecord(creditExhausted: Bool) {
        let today = isoDateString(from: Date())
        let triggerKey = "screentime.shieldTriggers.\(today)"
        let current = sharedDefaults?.integer(forKey: triggerKey) ?? 0
        sharedDefaults?.set(current + 1, forKey: triggerKey)

        var records: [[String: Any]] = []
        if let data = sharedDefaults?.data(forKey: "screentime.usageData"),
           let existing = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] {
            records = existing
        }

        let availableSeconds = sharedDefaults?.integer(forKey: "screentime.availableSeconds") ?? 0
        let record: [String: Any] = [
            "date": today,
            "totalSeconds": availableSeconds,
            "categoryBreakdown": [:] as [String: Int],
            "shieldTriggerCount": current + 1,
            "creditExhausted": creditExhausted
        ]

        records.removeAll { ($0["date"] as? String) == today }
        records.append(record)

        // Keep 90 days
        let cutoff = isoDateString(from: Calendar.current.date(
            byAdding: .day, value: -90, to: Date()) ?? Date()
        )
        records = records.filter { ($0["date"] as? String ?? "") >= cutoff }

        if let data = try? JSONSerialization.data(withJSONObject: records) {
            sharedDefaults?.set(data, forKey: "screentime.usageData")
        }
    }

    // MARK: - Helpers

    private func isoDateString(from date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter.string(from: date)
    }
}
