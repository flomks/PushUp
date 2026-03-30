import Foundation
import os.log
import UIKit
import UserNotifications

// MARK: - NotificationIdentifier

/// Stable string identifiers for every notification the app schedules.
///
/// Using an enum with static constants prevents typos and makes it easy to
/// cancel a specific notification by its identifier without scattering raw
/// strings across the codebase.
enum NotificationIdentifier {
    /// Daily "Zeit fuer Push-Ups!" reminder at the user-configured time.
    static let dailyReminder = "com.pushup.notification.dailyReminder"

    /// Evening streak-danger warning: "Du hast heute noch kein Workout".
    static let streakWarning = "com.pushup.notification.streakWarning"

    /// Low time-credit alert: "Dein Zeitguthaben ist aufgebraucht".
    static let creditWarning = "com.pushup.notification.creditWarning"

    /// Post-workout confirmation: "Workout abgeschlossen! +X Minuten verdient".
    static let workoutComplete = "com.pushup.notification.workoutComplete"

    /// All identifiers for recurring (scheduled) notifications.
    /// Used by `disableAllScheduledNotifications()` to cancel only the
    /// repeating triggers without removing one-shot event notifications.
    static let allRecurring = [dailyReminder, streakWarning]
}

// MARK: - NotificationManager

/// Central service for all local push-notification scheduling in the PushUp app.
///
/// **Responsibilities**
/// - Request `UNUserNotificationCenter` authorisation on first launch.
/// - Schedule / reschedule the daily reminder when the user changes the time
///   or toggles notifications on/off.
/// - Schedule the streak-warning notification each evening; suppress it when
///   the user has already completed a workout today.
/// - Fire the post-workout "Workout abgeschlossen!" notification after a
///   session ends.
/// - Fire the low-credit warning when the user's time credit reaches zero.
/// - Cancel individual or all pending notifications.
///
/// **"Not send if already worked out today" strategy**
///
/// iOS local notifications do not support conditional delivery. The approach
/// used here:
/// 1. The daily reminder and streak warning are scheduled as repeating
///    calendar triggers.
/// 2. When a workout completes, both are cancelled for the current day and
///    rescheduled for the *next* day using a non-repeating trigger. The
///    repeating trigger is then re-added so subsequent days are covered.
/// 3. On each app launch, if the user has already worked out today, the
///    pending streak warning for today is cancelled.
///
/// **Threading**
/// The class is `@MainActor`-isolated. All public methods are safe to call
/// from SwiftUI views and view models.
///
/// **Usage**
/// ```swift
/// // Request permission (call once from AppDelegate)
/// await NotificationManager.shared.requestAuthorisationIfNeeded()
///
/// // After a workout ends
/// await NotificationManager.shared.scheduleWorkoutCompleteNotification(earnedMinutes: 5)
///
/// // When settings change
/// await NotificationManager.shared.rescheduleDailyReminder(hour: 8, minute: 0)
/// ```
@MainActor
final class NotificationManager: NSObject, UNUserNotificationCenterDelegate {

    // MARK: - Singleton

    static let shared = NotificationManager()

    // MARK: - Private

    private let center = UNUserNotificationCenter.current()
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.pushup", category: "Notifications")

    /// `UserDefaults` key that stores the date string (yyyy-MM-dd) of the
    /// last day a workout was completed.
    static let lastWorkoutDateKey = "notificationManager.lastWorkoutDate"

    /// Thread-safe ISO date formatter for the `lastWorkoutDate` key.
    /// Uses POSIX locale to prevent locale-dependent formatting.
    private static let dateFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withFullDate]
        return f
    }()

    // MARK: - Init

    private override init() {
        super.init()
        // Register as delegate so notifications can be delivered in the foreground.
        center.delegate = self
    }

    // MARK: - UNUserNotificationCenterDelegate

    /// Allows notifications to be displayed as banners even when the app is
    /// in the foreground. Without this, the post-workout notification would
    /// be silently dropped because the user is looking at the summary screen.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }

    /// Called when the user taps a notification (local or remote) while the
    /// app is in the foreground, background, or after a cold launch.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let userInfo = response.notification.request.content.userInfo

        // Shield "Train now" notification or "Start Workout" action from limit-reached notification.
        if let action = userInfo["action"] as? String, action == "openWorkout" {
            let defaults = UserDefaults(suiteName: "group.com.flomks.pushup")
            defaults?.set(true, forKey: "shield.shouldOpenWorkout")
            defaults?.synchronize()
            completionHandler()
            return
        }
        if response.actionIdentifier == "START_WORKOUT" {
            let defaults = UserDefaults(suiteName: "group.com.flomks.pushup")
            defaults?.set(true, forKey: "shield.shouldOpenWorkout")
            defaults?.synchronize()
            completionHandler()
            return
        }

        Task { @MainActor in
            self.handleRemotePush(userInfo: userInfo)
        }
        completionHandler()
    }

    // MARK: - Remote Push Handling

    /// Routes an incoming remote push notification payload.
    ///
    /// Called from both `AppDelegate.didReceiveRemoteNotification` (background)
    /// and `userNotificationCenter(_:didReceive:)` (tap from notification center).
    ///
    /// Currently posts a `Notification.Name.didReceiveFriendPush` so that
    /// the Friends tab can refresh its badge and request list automatically.
    @MainActor
    func handleRemotePush(userInfo: [AnyHashable: Any]) {
        guard let type = userInfo["type"] as? String else { return }

        switch type {
        case "friend_request":
            // Post a notification so FriendsViewModel can refresh incoming requests.
            NotificationCenter.default.post(
                name: .didReceiveFriendRequestPush,
                object: nil,
                userInfo: userInfo as? [String: Any]
            )
            logger.info("Received friend_request push -- notifying FriendsViewModel.")

        case "friend_accepted":
            // Post a notification so FriendsViewModel can refresh the friends list.
            NotificationCenter.default.post(
                name: .didReceiveFriendAcceptedPush,
                object: nil,
                userInfo: userInfo as? [String: Any]
            )
            logger.info("Received friend_accepted push -- notifying FriendsViewModel.")

        default:
            logger.debug("Received unknown push type: \(type)")
        }
    }

    // MARK: - Authorisation

    /// Requests notification authorisation if the status is `.notDetermined`.
    ///
    /// - Returns: `true` when the user granted permission (or had already
    ///   granted it), `false` otherwise.
    @discardableResult
    func requestAuthorisationIfNeeded() async -> Bool {
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .notDetermined:
            do {
                let granted = try await center.requestAuthorization(
                    options: [.alert, .badge, .sound]
                )
                logger.info("Notification authorisation result: \(granted)")
                return granted
            } catch {
                logger.error("Notification authorisation failed: \(error.localizedDescription)")
                return false
            }
        case .authorized, .provisional, .ephemeral:
            return true
        case .denied:
            return false
        @unknown default:
            return false
        }
    }

    /// Returns the current `UNAuthorizationStatus` without triggering a prompt.
    func authorizationStatus() async -> UNAuthorizationStatus {
        await center.notificationSettings().authorizationStatus
    }

    // MARK: - Daily Reminder

    /// Schedules (or reschedules) the daily "Zeit fuer Push-Ups!" reminder.
    ///
    /// The notification fires every day at the given hour/minute. Any
    /// previously scheduled daily reminder is cancelled first so there is
    /// never more than one pending.
    ///
    /// If the user has already worked out today, the reminder is still
    /// scheduled (it will fire tomorrow and every day after). To suppress
    /// today's delivery, call `cancelTodaysNotificationsIfWorkedOut()` after
    /// scheduling.
    ///
    /// - Parameters:
    ///   - hour:   Hour component (0-23). Clamped to valid range.
    ///   - minute: Minute component (0-59). Clamped to valid range.
    func scheduleDailyReminder(hour: Int, minute: Int) async {
        center.removePendingNotificationRequests(
            withIdentifiers: [NotificationIdentifier.dailyReminder]
        )

        guard await isAuthorized() else { return }

        let clampedHour   = max(0, min(23, hour))
        let clampedMinute = max(0, min(59, minute))

        let content = UNMutableNotificationContent()
        content.title = "Zeit fuer Push-Ups!"
        content.body = "Deine taegliche Erinnerung: Mach jetzt dein Workout und verdiene Zeitguthaben."
        content.sound = .default

        var components = DateComponents()
        components.hour   = clampedHour
        components.minute = clampedMinute

        let trigger = UNCalendarNotificationTrigger(
            dateMatching: components,
            repeats: true
        )

        let request = UNNotificationRequest(
            identifier: NotificationIdentifier.dailyReminder,
            content: content,
            trigger: trigger
        )

        do {
            try await center.add(request)
            logger.info("Daily reminder scheduled at \(clampedHour):\(clampedMinute)")
        } catch {
            logger.error("Failed to schedule daily reminder: \(error.localizedDescription)")
        }
    }

    /// Cancels the daily reminder notification.
    func cancelDailyReminder() {
        center.removePendingNotificationRequests(
            withIdentifiers: [NotificationIdentifier.dailyReminder]
        )
        logger.debug("Daily reminder cancelled")
    }

    // MARK: - Streak Warning

    /// Schedules the daily streak-warning notification at 20:00.
    ///
    /// The notification repeats daily. To suppress it on days when the user
    /// has already worked out, call `cancelTodaysNotificationsIfWorkedOut()`
    /// after a workout completes.
    func scheduleStreakWarning() async {
        center.removePendingNotificationRequests(
            withIdentifiers: [NotificationIdentifier.streakWarning]
        )

        guard await isAuthorized() else { return }

        let content = UNMutableNotificationContent()
        content.title = "Streak in Gefahr!"
        content.body = "Du hast heute noch kein Workout gemacht. Mach jetzt Push-Ups, um deinen Streak zu retten!"
        content.sound = .default

        var components = DateComponents()
        components.hour   = 20
        components.minute = 0

        let trigger = UNCalendarNotificationTrigger(
            dateMatching: components,
            repeats: true
        )

        let request = UNNotificationRequest(
            identifier: NotificationIdentifier.streakWarning,
            content: content,
            trigger: trigger
        )

        do {
            try await center.add(request)
            logger.info("Streak warning scheduled at 20:00")
        } catch {
            logger.error("Failed to schedule streak warning: \(error.localizedDescription)")
        }
    }

    /// Cancels the streak-warning notification.
    func cancelStreakWarning() {
        center.removePendingNotificationRequests(
            withIdentifiers: [NotificationIdentifier.streakWarning]
        )
    }

    // MARK: - Post-Workout Notification

    /// Fires a "Workout abgeschlossen!" notification.
    ///
    /// Also records today's date so the daily reminder and streak warning
    /// can be suppressed for the rest of the day, and cancels both pending
    /// recurring notifications for today. They are rescheduled to resume
    /// firing from tomorrow onward.
    ///
    /// - Parameter earnedMinutes: Minutes of time credit earned in the session.
    func scheduleWorkoutCompleteNotification(earnedMinutes: Int) async {
        // Record that the user worked out today.
        recordWorkoutToday()

        // Cancel today's recurring notifications -- the user already worked out.
        cancelDailyReminder()
        cancelStreakWarning()

        guard await isAuthorized() else {
            // Even if not authorized, still reschedule the recurring triggers
            // so they are ready if the user re-enables notifications later.
            await rescheduleRecurringNotificationsIfEnabled()
            return
        }

        // Cancel any previous workout-complete notification to avoid stacking.
        center.removePendingNotificationRequests(
            withIdentifiers: [NotificationIdentifier.workoutComplete]
        )

        let content = UNMutableNotificationContent()
        content.title = "Workout abgeschlossen!"
        let minuteWord = earnedMinutes == 1 ? "Minute" : "Minuten"
        content.body = "Super! Du hast +\(earnedMinutes) \(minuteWord) Zeitguthaben verdient."
        content.sound = .default

        // Deliver after a short delay so the summary screen is visible first.
        let trigger = UNTimeIntervalNotificationTrigger(
            timeInterval: 3,
            repeats: false
        )

        let request = UNNotificationRequest(
            identifier: NotificationIdentifier.workoutComplete,
            content: content,
            trigger: trigger
        )

        do {
            try await center.add(request)
            logger.info("Workout complete notification scheduled (+\(earnedMinutes) min)")
        } catch {
            logger.error("Failed to schedule workout complete notification: \(error.localizedDescription)")
        }

        // Re-add the recurring triggers so they fire again starting tomorrow.
        // Because we just recorded today's workout, the next call to
        // `cancelTodaysNotificationsIfWorkedOut()` on app launch will
        // suppress them again if needed.
        await rescheduleRecurringNotificationsIfEnabled()
    }

    // MARK: - Credit Warning

    /// Fires an immediate "Dein Zeitguthaben ist aufgebraucht" notification.
    ///
    /// Call this when the user's available time credit reaches zero.
    func scheduleCreditWarningNotification() async {
        guard await isAuthorized() else { return }

        // Avoid duplicate credit warnings.
        center.removePendingNotificationRequests(
            withIdentifiers: [NotificationIdentifier.creditWarning]
        )

        let content = UNMutableNotificationContent()
        content.title = "Zeitguthaben aufgebraucht"
        content.body = "Dein Zeitguthaben ist aufgebraucht. Mach Push-Ups, um neues Guthaben zu verdienen!"
        content.sound = .default

        let trigger = UNTimeIntervalNotificationTrigger(
            timeInterval: 1,
            repeats: false
        )

        let request = UNNotificationRequest(
            identifier: NotificationIdentifier.creditWarning,
            content: content,
            trigger: trigger
        )

        do {
            try await center.add(request)
            logger.info("Credit warning notification scheduled")
        } catch {
            logger.error("Failed to schedule credit warning: \(error.localizedDescription)")
        }
    }

    // MARK: - Bulk Operations

    /// Enables all recurring notifications: daily reminder and streak warning.
    ///
    /// After scheduling, suppresses today's notifications if the user has
    /// already worked out.
    ///
    /// - Parameters:
    ///   - hour:   Hour for the daily reminder (0-23).
    ///   - minute: Minute for the daily reminder (0-59).
    func enableAllNotifications(hour: Int, minute: Int) async {
        await scheduleDailyReminder(hour: hour, minute: minute)
        await scheduleStreakWarning()
        cancelTodaysNotificationsIfWorkedOut()
    }

    /// Disables all recurring notifications by cancelling only the scheduled
    /// repeating triggers. Does NOT remove one-shot event notifications
    /// (workout complete, credit warning) that may already be in-flight.
    func disableAllScheduledNotifications() {
        center.removePendingNotificationRequests(
            withIdentifiers: NotificationIdentifier.allRecurring
        )
        logger.info("All scheduled notifications disabled")
    }

    /// Reschedules only the daily reminder (e.g. when the user changes the time).
    ///
    /// - Parameters:
    ///   - hour:   New hour (0-23).
    ///   - minute: New minute (0-59).
    func rescheduleDailyReminder(hour: Int, minute: Int) async {
        await scheduleDailyReminder(hour: hour, minute: minute)
        cancelTodaysNotificationsIfWorkedOut()
    }

    // MARK: - Today's Workout Tracking

    /// Cancels today's daily reminder and streak warning if the user has
    /// already completed a workout today.
    ///
    /// Call this:
    /// - On app launch (from `AppDelegate`)
    /// - After scheduling recurring notifications
    /// - After a workout completes
    func cancelTodaysNotificationsIfWorkedOut() {
        guard hasWorkedOutToday() else { return }
        center.removePendingNotificationRequests(
            withIdentifiers: [
                NotificationIdentifier.dailyReminder,
                NotificationIdentifier.streakWarning,
            ]
        )
        logger.debug("Suppressed today's notifications (workout already completed)")
    }

    /// Records that a workout was completed today.
    /// Public so that `WorkoutViewModel` can call it directly if needed.
    func recordWorkoutToday() {
        let today = Self.dateFormatter.string(from: Date())
        UserDefaults.standard.set(today, forKey: Self.lastWorkoutDateKey)
        logger.debug("Recorded workout for today")
    }

    /// Returns `true` when the user has already completed a workout today.
    func hasWorkedOutToday() -> Bool {
        guard let stored = UserDefaults.standard.string(forKey: Self.lastWorkoutDateKey) else {
            return false
        }
        let today = Self.dateFormatter.string(from: Date())
        return stored == today
    }

    /// Clears the app badge count. Call when the user opens the app.
    func clearBadge() {
        UNUserNotificationCenter.current().setBadgeCount(0)
    }


    // MARK: - Private Helpers

    /// Convenience: returns `true` when notification authorisation is `.authorized`.
    private func isAuthorized() async -> Bool {
        await authorizationStatus() == .authorized
    }

    /// Re-adds recurring notifications (daily reminder + streak warning) only
    /// when notifications are enabled in settings. Called after a workout
    /// completes so the triggers resume for subsequent days.
    private func rescheduleRecurringNotificationsIfEnabled() async {
        let defaults = UserDefaults.standard
        let notificationsEnabled = defaults.bool(forKey: SettingsKeys.notificationsEnabled)
        guard notificationsEnabled else { return }

        let hour = defaults.object(forKey: SettingsKeys.notificationHour) != nil
            ? defaults.integer(forKey: SettingsKeys.notificationHour)
            : 8
        let minute = defaults.integer(forKey: SettingsKeys.notificationMinute)

        await scheduleDailyReminder(hour: hour, minute: minute)
        await scheduleStreakWarning()

        // Suppress today's delivery since the user just worked out.
        cancelTodaysNotificationsIfWorkedOut()
    }
}

// MARK: - Notification Names (Remote Push)

extension Notification.Name {
    /// Posted when a `friend_request` push notification is received.
    /// FriendsViewModel observes this to refresh the incoming requests list.
    static let didReceiveFriendRequestPush = Notification.Name("didReceiveFriendRequestPush")

    /// Posted when a `friend_accepted` push notification is received.
    /// FriendsViewModel observes this to refresh the friends list.
    static let didReceiveFriendAcceptedPush = Notification.Name("didReceiveFriendAcceptedPush")
}
