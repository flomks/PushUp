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
/// **Reinstall-proof design:**
/// On every threshold event, this extension writes the cumulative usage
/// seconds to `screentime.todaySystemUsageSeconds`. The main app reads
/// this value when computing the DeviceActivity threshold, ensuring that
/// reinstalling the app does not reset the "already used today" counter.
/// The OS tracks cumulative usage independently of our UserDefaults.
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

        // Reset the system usage counter for the new day.
        // The OS resets cumulative usage at midnight, so we reset our
        // mirror value too.
        let today = isoDateString(from: Date())
        sharedDefaults?.set(0, forKey: "screentime.todaySystemUsageSeconds")
        sharedDefaults?.set(today, forKey: "screentime.todaySystemUsageDate")

        // Snapshot the credit balance at the start of the day so we can
        // calculate how many seconds were actually consumed during the day.
        let currentCredit = sharedDefaults?.integer(forKey: "screentime.availableSeconds") ?? 0
        sharedDefaults?.set(currentCredit, forKey: "screentime.startOfDaySeconds")
        sharedDefaults?.set(Date(), forKey: "screentime.startOfDayDate")
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
        // If we're already blocking (credit exhausted / shield active), do not
        // show "5 minutes left" — that event can still fire when schedules
        // restart or thresholds are re-registered after the user hit the limit.
        let alreadyBlocking = sharedDefaults?.bool(forKey: "screentime.isBlocking") ?? false
        if alreadyBlocking { return }

        // Update the system usage snapshot before sending the notification.
        // At the warning threshold, the user has consumed ~80% of their credit.
        // We record the cumulative usage at this point so the main app can
        // use it for accurate threshold recalculation after a workout.
        updateSystemUsageSnapshot(forEvent: "warning")

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
        // Update the system usage snapshot BEFORE blocking.
        // This records the exact cumulative usage at the moment the limit
        // was reached. The main app uses this value to compute the correct
        // threshold after the user earns more credit via a workout.
        updateSystemUsageSnapshot(forEvent: "limitReached")

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
            store.shield.webDomains = selection.webDomainTokens
        }
    }

    private func unblockApps() {
        store.shield.applications = nil
        store.shield.applicationCategories = nil
        store.shield.webDomainCategories = nil
    }

    // MARK: - System Usage Snapshot (Reinstall-proof)

    /// Records the cumulative usage at the current threshold event.
    ///
    /// The DeviceActivityEvent threshold IS the cumulative usage value at
    /// which the event fires. When `limitReached` fires, the cumulative
    /// usage equals the threshold we set in `startMonitoring`. We can
    /// reconstruct this value as:
    ///   `todaySystemUsage = alreadyUsedAtMonitoringStart + availableSecondsAtMonitoringStart`
    ///
    /// However, the most reliable approach is to read the threshold value
    /// that was stored when monitoring was started. The threshold equals
    /// the cumulative usage at the moment the event fires.
    ///
    /// We store this as `screentime.todaySystemUsageSeconds` so the main
    /// app can use it as the authoritative "already used today" value when
    /// restarting monitoring after a workout. This value is NOT reset by
    /// reinstalling the app -- the OS tracks usage independently.
    private func updateSystemUsageSnapshot(forEvent event: String) {
        let today = isoDateString(from: Date())

        // The cumulative usage at the moment this threshold fires equals
        // the threshold value that was configured in startMonitoring.
        // We stored the limit threshold as:
        //   cumulativeLimitSeconds = alreadyUsedToday + availableSeconds
        //
        // For the warning event, the threshold is cumulativeLimitSeconds - 300.
        // For the limitReached event, the threshold is cumulativeLimitSeconds.
        //
        // We read the stored available seconds and start-of-day snapshot to
        // reconstruct the cumulative usage at this moment.
        let availableSeconds = sharedDefaults?.integer(forKey: "screentime.availableSeconds") ?? 0
        let startOfDaySeconds = sharedDefaults?.integer(forKey: "screentime.startOfDaySeconds") ?? availableSeconds
        let alreadyUsedAtStart = max(0, startOfDaySeconds - availableSeconds)

        // The cumulative usage right now is the threshold that just fired.
        // For limitReached: cumulative = alreadyUsedAtStart + availableSeconds
        // For warning: cumulative = alreadyUsedAtStart + availableSeconds - 300
        let cumulativeUsageNow: Int
        if event == "limitReached" {
            cumulativeUsageNow = alreadyUsedAtStart + availableSeconds
        } else {
            // Warning fires 5 min before limit; usage is limit - 300s
            cumulativeUsageNow = max(0, alreadyUsedAtStart + availableSeconds - 300)
        }

        // Only update if the stored date matches today (reset at midnight).
        let storedDate = sharedDefaults?.string(forKey: "screentime.todaySystemUsageDate") ?? ""
        if storedDate != today {
            // New day -- reset
            sharedDefaults?.set(today, forKey: "screentime.todaySystemUsageDate")
        }

        // Always write the latest (highest) cumulative value.
        let existing = sharedDefaults?.integer(forKey: "screentime.todaySystemUsageSeconds") ?? 0
        if cumulativeUsageNow > existing {
            sharedDefaults?.set(cumulativeUsageNow, forKey: "screentime.todaySystemUsageSeconds")
        }
    }

    // MARK: - Usage Recording

    private func updateTodayUsageRecord(creditExhausted: Bool) {
        let today = isoDateString(from: Date())
        let triggerKey = "screentime.shieldTriggers.\(today)"
        let currentTriggerCount = (sharedDefaults?.integer(forKey: triggerKey) ?? 0) + 1
        sharedDefaults?.set(currentTriggerCount, forKey: triggerKey)

        // Use the system usage snapshot as the authoritative usage value.
        // This is more accurate than the credit-delta approach because it
        // reflects actual OS-tracked usage, not just credit consumed.
        let systemUsage = sharedDefaults?.integer(forKey: "screentime.todaySystemUsageSeconds") ?? 0

        // Fallback: calculate from credit delta if system usage is not available.
        let availableNow = sharedDefaults?.integer(forKey: "screentime.availableSeconds") ?? 0
        let startOfDay   = sharedDefaults?.integer(forKey: "screentime.startOfDaySeconds") ?? availableNow
        let creditDelta  = max(0, startOfDay - availableNow)

        let usedToday = systemUsage > 0 ? systemUsage : creditDelta

        // Build a Codable-compatible record matching AppUsageRecord in the main app.
        // Keys must match the CodingKeys of AppUsageRecord exactly.
        let record: [String: Any] = [
            "date": today,
            "totalSeconds": usedToday,
            "categoryBreakdown": [String: Int](),
            "shieldTriggerCount": currentTriggerCount,
            "creditExhausted": creditExhausted
        ]

        // Read existing records (written by this extension or the main app).
        var records: [[String: Any]] = []
        if let data = sharedDefaults?.data(forKey: "screentime.usageData"),
           let existing = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] {
            records = existing
        }

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

    private static let isoFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

    private func isoDateString(from date: Date) -> String {
        Self.isoFormatter.string(from: date)
    }
}
