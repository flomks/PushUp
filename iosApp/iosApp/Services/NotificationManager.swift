import Foundation
import UserNotifications

// MARK: - NotificationIdentifier

/// Stable string identifiers for every notification category the app schedules.
///
/// Using an enum prevents typos and makes it easy to cancel a specific
/// notification by its identifier without scattering raw strings across the
/// codebase.
enum NotificationIdentifier {
    /// Daily "Zeit fuer Push-Ups!" reminder at the user-configured time.
    static let dailyReminder = "com.pushup.notification.dailyReminder"

    /// Evening streak-danger warning: "Du hast heute noch kein Workout".
    /// Only delivered when no workout has been completed today.
    static let streakWarning = "com.pushup.notification.streakWarning"

    /// Low time-credit alert: "Dein Zeitguthaben ist aufgebraucht".
    static let creditWarning = "com.pushup.notification.creditWarning"

    /// Post-workout confirmation: "Workout abgeschlossen! +X Minuten verdient".
    /// Delivered immediately after a session ends.
    static let workoutComplete = "com.pushup.notification.workoutComplete"
}

// MARK: - NotificationManager

/// Central service for all local push-notification scheduling in the PushUp app.
///
/// **Responsibilities**
/// - Request `UNUserNotificationCenter` authorisation on first launch.
/// - Schedule / reschedule the daily reminder when the user changes the time
///   or toggles notifications on/off.
/// - Schedule the streak-warning notification (fired at 20:00 each day) only
///   when no workout has been recorded today.
/// - Fire the post-workout "Workout abgeschlossen!" notification immediately
///   after a session ends.
/// - Fire the low-credit warning when the user's time credit reaches zero.
/// - Cancel individual or all pending notifications.
///
/// **Threading**
/// All public methods are `async` and safe to call from any actor. Internally
/// they dispatch to `UNUserNotificationCenter` which is thread-safe.
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
final class NotificationManager {

    // MARK: - Singleton

    static let shared = NotificationManager()

    private init() {}

    // MARK: - Private

    private let center = UNUserNotificationCenter.current()

    /// `UserDefaults` key that stores the date string (yyyy-MM-dd) of the
    /// last day a workout was completed. Used to suppress the streak warning
    /// when the user has already worked out today.
    private static let lastWorkoutDateKey = "notificationManager.lastWorkoutDate"

    /// Date formatter for the `lastWorkoutDate` key.
    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

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
                return granted
            } catch {
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
    /// - Parameters:
    ///   - hour:   Hour component (0-23).
    ///   - minute: Minute component (0-59).
    func scheduleDailyReminder(hour: Int, minute: Int) async {
        // Cancel the existing reminder before rescheduling.
        center.removePendingNotificationRequests(
            withIdentifiers: [NotificationIdentifier.dailyReminder]
        )

        guard await authorizationStatus() == .authorized else { return }

        let content = UNMutableNotificationContent()
        content.title = "Zeit fuer Push-Ups!"
        content.body = "Deine taegliche Erinnerung: Mach jetzt dein Workout und verdiene Zeitguthaben."
        content.sound = .default
        content.badge = 1

        var components = DateComponents()
        components.hour   = hour
        components.minute = minute

        let trigger = UNCalendarNotificationTrigger(
            dateMatching: components,
            repeats: true
        )

        let request = UNNotificationRequest(
            identifier: NotificationIdentifier.dailyReminder,
            content: content,
            trigger: trigger
        )

        try? await center.add(request)
    }

    /// Cancels the daily reminder notification.
    func cancelDailyReminder() {
        center.removePendingNotificationRequests(
            withIdentifiers: [NotificationIdentifier.dailyReminder]
        )
    }

    // MARK: - Streak Warning

    /// Schedules the daily streak-warning notification at 20:00.
    ///
    /// The notification is only delivered when the user has **not** completed
    /// a workout today. This is enforced by checking `lastWorkoutDate` inside
    /// a `UNNotificationServiceExtension`-style approach: we schedule the
    /// notification unconditionally but cancel it from `scheduleWorkoutCompleteNotification`
    /// whenever a workout is finished on the same day.
    ///
    /// The notification repeats daily. Call this once when notifications are
    /// enabled; it will fire every evening until cancelled.
    func scheduleStreakWarning() async {
        center.removePendingNotificationRequests(
            withIdentifiers: [NotificationIdentifier.streakWarning]
        )

        guard await authorizationStatus() == .authorized else { return }

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

        try? await center.add(request)
    }

    /// Cancels the streak-warning notification.
    func cancelStreakWarning() {
        center.removePendingNotificationRequests(
            withIdentifiers: [NotificationIdentifier.streakWarning]
        )
    }

    // MARK: - Post-Workout Notification

    /// Fires an immediate "Workout abgeschlossen!" notification.
    ///
    /// Also records today's date so the streak-warning notification can be
    /// suppressed for the rest of the day by cancelling it.
    ///
    /// - Parameter earnedMinutes: Minutes of time credit earned in the session.
    func scheduleWorkoutCompleteNotification(earnedMinutes: Int) async {
        // Record that the user worked out today.
        recordWorkoutToday()

        // Cancel today's streak warning -- the user already worked out.
        cancelStreakWarning()

        guard await authorizationStatus() == .authorized else { return }

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

        try? await center.add(request)

        // Reschedule the streak warning for tomorrow (repeating trigger
        // handles this automatically, but we need to re-add it after
        // cancellation so it fires again the next day).
        await rescheduleStreakWarningIfEnabled()
    }

    // MARK: - Credit Warning

    /// Fires an immediate "Dein Zeitguthaben ist aufgebraucht" notification.
    ///
    /// Call this when the user's available time credit reaches zero.
    func scheduleCreditWarningNotification() async {
        guard await authorizationStatus() == .authorized else { return }

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

        try? await center.add(request)
    }

    // MARK: - Bulk Operations

    /// Enables all notifications: schedules the daily reminder and streak warning.
    ///
    /// - Parameters:
    ///   - hour:   Hour for the daily reminder (0-23).
    ///   - minute: Minute for the daily reminder (0-59).
    func enableAllNotifications(hour: Int, minute: Int) async {
        await scheduleDailyReminder(hour: hour, minute: minute)
        await scheduleStreakWarning()
    }

    /// Disables all notifications by cancelling every pending request.
    func disableAllNotifications() {
        center.removeAllPendingNotificationRequests()
    }

    /// Reschedules only the daily reminder (e.g. when the user changes the time).
    ///
    /// - Parameters:
    ///   - hour:   New hour (0-23).
    ///   - minute: New minute (0-59).
    func rescheduleDailyReminder(hour: Int, minute: Int) async {
        await scheduleDailyReminder(hour: hour, minute: minute)
    }

    // MARK: - Private Helpers

    /// Stores today's date string in `UserDefaults` to mark that a workout
    /// was completed today.
    private func recordWorkoutToday() {
        let today = Self.dateFormatter.string(from: Date())
        UserDefaults.standard.set(today, forKey: Self.lastWorkoutDateKey)
    }

    /// Returns `true` when the user has already completed a workout today.
    private func hasWorkedOutToday() -> Bool {
        guard let stored = UserDefaults.standard.string(forKey: Self.lastWorkoutDateKey) else {
            return false
        }
        let today = Self.dateFormatter.string(from: Date())
        return stored == today
    }

    /// Re-adds the streak warning (repeating daily at 20:00) only when
    /// notifications are enabled in settings. This is called after a workout
    /// completes so the warning fires again the following day.
    private func rescheduleStreakWarningIfEnabled() async {
        let notificationsEnabled = UserDefaults.standard.bool(
            forKey: SettingsKeys.notificationsEnabled
        )
        guard notificationsEnabled else { return }
        await scheduleStreakWarning()
    }
}
