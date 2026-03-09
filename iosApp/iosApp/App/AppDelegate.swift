import Shared
import UIKit
import UserNotifications

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

        // Request notification authorisation on first launch.
        // The system only shows the permission dialog once; subsequent calls
        // are no-ops when the status is already determined.
        Task { @MainActor in
            let granted = await NotificationManager.shared.requestAuthorisationIfNeeded()

            // If permission was just granted and the user had previously
            // enabled notifications in Settings, reschedule all notifications
            // (handles the case where the user reinstalls the app).
            if granted {
                let defaults = UserDefaults.standard
                let notificationsEnabled = defaults.bool(forKey: SettingsKeys.notificationsEnabled)
                if notificationsEnabled {
                    let hour = defaults.object(forKey: SettingsKeys.notificationHour) != nil
                        ? defaults.integer(forKey: SettingsKeys.notificationHour)
                        : 8
                    let minute = defaults.integer(forKey: SettingsKeys.notificationMinute)
                    await NotificationManager.shared.enableAllNotifications(
                        hour: hour,
                        minute: minute
                    )
                }
            }
        }

        return true
    }
}
