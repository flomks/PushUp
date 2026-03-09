import Shared
import UIKit

/// UIApplicationDelegate that initialises the Koin dependency-injection graph
/// before any KMP-managed object is accessed.
///
/// Koin must be started exactly once, before the first SwiftUI scene is
/// rendered. Placing the call here (rather than in the `@main` struct's
/// `init()`) keeps the entry point clean and makes the initialisation
/// order explicit.
///
/// The delegate is wired into the app via `@UIApplicationDelegateAdaptor`
/// in `PushUpApp`.
final class AppDelegate: NSObject, UIApplicationDelegate {

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        // Initialise the Koin DI graph. This must run before any
        // KMP-managed dependency (use cases, repositories, etc.) is accessed.
        KoinIOSKt.doInitKoin()

        // Notification setup runs asynchronously so it does not block launch.
        Task { @MainActor in
            await setupNotifications()
        }

        return true
    }

    // MARK: - Notification Setup

    /// Requests notification authorisation on first launch and reschedules
    /// any previously enabled notifications.
    ///
    /// Also suppresses today's recurring notifications if the user has
    /// already completed a workout, and clears the badge count.
    @MainActor
    private func setupNotifications() async {
        let manager = NotificationManager.shared

        // Clear the badge count every time the app launches.
        manager.clearBadge()

        // Request authorisation. The system only shows the dialog once;
        // subsequent calls are no-ops when the status is already determined.
        let granted = await manager.requestAuthorisationIfNeeded()

        // If permission is granted and the user had previously enabled
        // notifications in Settings, reschedule all recurring notifications.
        // This handles the case where the OS purged pending notifications
        // (e.g. after a device restart or app update).
        if granted {
            let defaults = UserDefaults.standard
            let notificationsEnabled = defaults.bool(forKey: SettingsKeys.notificationsEnabled)
            if notificationsEnabled {
                let hour = defaults.object(forKey: SettingsKeys.notificationHour) != nil
                    ? defaults.integer(forKey: SettingsKeys.notificationHour)
                    : 8
                let minute = defaults.integer(forKey: SettingsKeys.notificationMinute)
                await manager.enableAllNotifications(hour: hour, minute: minute)
            }
        }

        // Suppress today's daily reminder and streak warning if the user
        // has already worked out today.
        manager.cancelTodaysNotificationsIfWorkedOut()
    }
}
