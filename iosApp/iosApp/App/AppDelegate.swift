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

        // Notification setup runs asynchronously so it does not block launch.
        Task { @MainActor in
            await setupNotifications()
        }

        // Start the sync service: wires up network reconnect handling and
        // periodic background sync. Must run after Koin is initialised.
        Task { @MainActor in
            SyncService.shared.start()
        }

        // Re-arm the DeviceActivity threshold on every launch.
        //
        // REINSTALL-PROOF LOGIC:
        // On a fresh install (or reinstall), the App Group UserDefaults may
        // have been cleared. However, the OS-tracked cumulative usage for
        // today is stored in `screentime.todaySystemUsageSeconds` by the
        // DeviceActivityMonitorExtension, which runs in a separate process
        // and is NOT cleared on reinstall.
        //
        // The ScreenTimeManager.startMonitoring() method reads this value
        // and uses it as the authoritative "already used today" offset when
        // computing the DeviceActivity threshold. This ensures that reinstalling
        // the app does not allow the user to bypass the daily limit.
        //
        // Example:
        //   User used 60 min today, reinstalls app, earns 30 min workout.
        //   DB credit = 30 min (earned from workout).
        //   todaySystemUsageSeconds = 3600 (60 min, from extension).
        //   cumulativeLimitSeconds = 3600 + 1800 = 5400 (90 min total).
        //   System fires when cumulative usage hits 90 min = 30 more min.
        //   The reinstall did NOT help the user bypass the limit.
        Task { @MainActor in
            await rearmScreenTimeMonitoring()
        }

        return true
    }

    // MARK: - Screen Time Re-arming

    /// Re-arms the DeviceActivity threshold using the stored credit balance.
    ///
    /// Called on every launch to ensure the threshold is always set correctly,
    /// even after a reinstall or after the app was killed.
    @MainActor
    private func rearmScreenTimeMonitoring() async {
        let screenTime = ScreenTimeManager.shared
        let sharedDefaults = UserDefaults(suiteName: "group.com.flomks.pushup")

        let storedCredit = sharedDefaults?.integer(forKey: "screentime.availableSeconds") ?? 0

        guard screenTime.authorizationStatus == .authorized,
              screenTime.activitySelection != nil else { return }

        if storedCredit > 0 {
            // Credit available -- set threshold and start monitoring.
            screenTime.stopMonitoring()
            screenTime.startMonitoring(availableSeconds: storedCredit)
        } else {
            // Credit is zero (or not yet stored) -- block apps immediately
            // and start monitoring with threshold=1 so the extension records
            // usage data even while blocked.
            screenTime.blockApps()
            screenTime.stopMonitoring()
            screenTime.startMonitoring(availableSeconds: 1)
        }
    }

    // MARK: - Remote Notification Registration

    /// Called by iOS after a successful APNs registration.
    /// Forwards the token to the backend so the server can deliver pushes.
    func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        let tokenString = deviceToken.map { String(format: "%02x", $0) }.joined()
        Task {
            await PushNotificationService.shared.registerToken(tokenString)
        }
    }

    /// Called by iOS when APNs registration fails (e.g. no network, simulator).
    func application(
        _ application: UIApplication,
        didFailToRegisterForRemoteNotificationsWithError error: Error
    ) {
        // Non-fatal: the app works without push notifications.
        // The next launch will retry registration automatically.
        print("[PushNotifications] APNs registration failed: \(error.localizedDescription)")
    }

    /// Called when the user taps a push notification while the app is in the
    /// background or terminated. Forwards to NotificationManager for routing.
    func application(
        _ application: UIApplication,
        didReceiveRemoteNotification userInfo: [AnyHashable: Any],
        fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void
    ) {
        NotificationManager.shared.handleRemotePush(userInfo: userInfo)
        completionHandler(.newData)
    }

    // MARK: - Notification Setup

    /// Requests notification authorisation on first launch and reschedules
    /// any previously enabled notifications.
    ///
    /// Also suppresses today's recurring notifications if the user has
    /// already completed a workout, and clears the badge count.
    /// Registers for remote (APNs) notifications so the backend can deliver
    /// push notifications for friend requests and other social events.
    @MainActor
    private func setupNotifications() async {
        let manager = NotificationManager.shared

        // Clear the badge count every time the app launches.
        manager.clearBadge()

        // Request authorisation. The system only shows the dialog once;
        // subsequent calls are no-ops when the status is already determined.
        let granted = await manager.requestAuthorisationIfNeeded()

        if granted {
            // Register for remote (APNs) push notifications.
            // The token is delivered to AppDelegate.didRegisterForRemoteNotifications.
            UIApplication.shared.registerForRemoteNotifications()

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

    // MARK: - Helpers

    private func isoDateString(from date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter.string(from: date)
    }
}
