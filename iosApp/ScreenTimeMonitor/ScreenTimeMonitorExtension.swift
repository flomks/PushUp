import DeviceActivity
import ManagedSettings
import FamilyControls
import Foundation
import UserNotifications

// MARK: - ScreenTimeMonitorExtension

/// DeviceActivity Monitor Extension.
///
/// This extension runs in a **separate process** from the main app.
/// It receives callbacks from the system when DeviceActivity thresholds
/// are reached. It cannot directly update the main app's UI -- all
/// communication happens via the shared App Group UserDefaults.
///
/// **Registered events:**
/// - `com.flomks.pushup.warning`   -- 80% of credit consumed
/// - `com.flomks.pushup.limitReached` -- 100% of credit consumed (block)
///
/// **Bundle ID:** `com.flomks.pushup.ScreenTimeMonitor`
/// **App Group:** `group.com.flomks.pushup`
class ScreenTimeMonitorExtension: DeviceActivityMonitor {

    // MARK: - Private

    private let store = ManagedSettingsStore()
    private let sharedDefaults = UserDefaults(suiteName: "group.com.flomks.pushup")

    // MARK: - Interval Lifecycle

    override func intervalDidStart(for activity: DeviceActivityName) {
        super.intervalDidStart(for: activity)
        // A new monitoring interval started (new day).
        // Reset the blocking state so apps are accessible at the start of each day.
        unblockApps()
        sharedDefaults?.set(false, forKey: "screentime.isBlocking")
    }

    override func intervalDidEnd(for activity: DeviceActivityName) {
        super.intervalDidEnd(for: activity)
        // The monitoring interval ended (end of day).
        // Unblock apps so the user starts fresh tomorrow.
        unblockApps()
        sharedDefaults?.set(false, forKey: "screentime.isBlocking")
    }

    // MARK: - Event Thresholds

    override func eventDidReachThreshold(
        _ event: DeviceActivityEvent.Name,
        activity: DeviceActivityName
    ) {
        super.eventDidReachThreshold(event, activity: activity)

        switch event {
        case DeviceActivityEvent.Name("com.flomks.pushup.warning"):
            handleWarningThreshold()

        case DeviceActivityEvent.Name("com.flomks.pushup.limitReached"):
            handleLimitReached()

        default:
            break
        }
    }

    override func eventWillReachThreshold(
        _ event: DeviceActivityEvent.Name,
        activity: DeviceActivityName
    ) {
        super.eventWillReachThreshold(event, activity: activity)
        // Called shortly before the threshold is reached.
        // We use eventDidReachThreshold instead for reliability.
    }

    // MARK: - Warning Handler

    private func handleWarningThreshold() {
        // Send a local notification warning the user that credit is running low.
        let content = UNMutableNotificationContent()
        content.title = "Time Credit Running Low"
        content.body = "You have about 5 minutes of screen time credit left. Do some push-ups to earn more!"
        content.sound = .default
        content.categoryIdentifier = "SCREEN_TIME_WARNING"

        let request = UNNotificationRequest(
            identifier: "screentime.warning.\(Date().timeIntervalSince1970)",
            content: content,
            trigger: nil  // Deliver immediately
        )

        UNUserNotificationCenter.current().add(request) { _ in }

        // Record the warning in shared storage
        recordUsageEvent(type: "warning")
    }

    // MARK: - Limit Reached Handler

    private func handleLimitReached() {
        // Block the selected apps via ManagedSettings.
        blockSelectedApps()

        // Mark as blocking in shared storage so the main app can reflect this.
        sharedDefaults?.set(true, forKey: "screentime.isBlocking")

        // Send a local notification.
        let content = UNMutableNotificationContent()
        content.title = "Time Credit Exhausted"
        content.body = "Your screen time credit has run out. Open PushUp and do some push-ups to earn more time!"
        content.sound = .default
        content.categoryIdentifier = "SCREEN_TIME_BLOCKED"

        // Add a deep link action to open the workout screen.
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

        // Record the block event and update usage data.
        recordUsageEvent(type: "blocked")
        updateTodayUsageRecord(creditExhausted: true)
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

    private func recordUsageEvent(type: String) {
        // Increment the shield trigger count for today.
        let key = "screentime.shieldTriggers.\(todayDateString())"
        let current = sharedDefaults?.integer(forKey: key) ?? 0
        sharedDefaults?.set(current + 1, forKey: key)
    }

    private func updateTodayUsageRecord(creditExhausted: Bool) {
        let today = todayDateString()
        let shieldTriggers = sharedDefaults?.integer(
            forKey: "screentime.shieldTriggers.\(today)"
        ) ?? 1

        // Read existing usage data
        var records: [AppUsageRecord] = []
        if let data = sharedDefaults?.data(forKey: "screentime.usageData"),
           let existing = try? JSONDecoder().decode([AppUsageRecord].self, from: data) {
            records = existing
        }

        // Build today's record.
        // Note: We don't have exact usage seconds here (DeviceActivity doesn't
        // provide them in the callback). We use the threshold value as an approximation.
        let availableSeconds = sharedDefaults?.integer(forKey: "screentime.availableSeconds") ?? 0
        let record = AppUsageRecord(
            date: today,
            totalSeconds: availableSeconds,
            categoryBreakdown: [:],
            shieldTriggerCount: shieldTriggers,
            creditExhausted: creditExhausted
        )

        // Replace or append
        if let index = records.firstIndex(where: { $0.date == today }) {
            records[index] = record
        } else {
            records.append(record)
        }

        // Keep 90 days
        let cutoff = isoDateString(from: Calendar.current.date(
            byAdding: .day, value: -90, to: Date()) ?? Date()
        )
        records = records.filter { $0.date >= cutoff }

        if let data = try? JSONEncoder().encode(records) {
            sharedDefaults?.set(data, forKey: "screentime.usageData")
        }
    }

    // MARK: - Date Helpers

    private func todayDateString() -> String {
        isoDateString(from: Date())
    }

    private func isoDateString(from date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter.string(from: date)
    }
}

// MARK: - AppUsageRecord (duplicated for Extension isolation)
//
// The Extension cannot import the main app module, so we duplicate the
// Codable struct here. Both definitions must stay in sync.

struct AppUsageRecord: Codable, Identifiable {
    var id: String { date }
    let date: String
    let totalSeconds: Int
    let categoryBreakdown: [String: Int]
    let shieldTriggerCount: Int
    let creditExhausted: Bool
}
