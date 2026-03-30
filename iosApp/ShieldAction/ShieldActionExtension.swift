import ManagedSettings
import Foundation
import UserNotifications

// MARK: - ShieldActionExtension

/// Handles button taps on the system app shield (lock screen).
///
/// Primary button ("Train Now"):
///   1. Sets a flag in the App Group so the main app navigates to Workout on launch.
///   2. Fires an immediate local notification so the user can tap it to open the app.
///   3. Closes the shield (returns to Home Screen).
///
/// ShieldActionDelegate runs in a sandboxed extension process -- UIApplication is
/// not available, so we cannot open a URL directly. The notification banner is the
/// fastest path for the user to reach the app.
///
/// Secondary button ("Not Now") -- defers, shield stays visible.
///
/// **Bundle ID:** `com.flomks.pushup.ShieldAction`
class ShieldActionExtension: ShieldActionDelegate {

    private let sharedDefaults = UserDefaults(suiteName: "group.com.flomks.pushup")

    override func handle(
        action: ShieldAction,
        for application: ApplicationToken,
        completionHandler: @escaping (ShieldActionResponse) -> Void
    ) {
        handleAction(action, completionHandler: completionHandler)
    }

    override func handle(
        action: ShieldAction,
        for webDomain: WebDomainToken,
        completionHandler: @escaping (ShieldActionResponse) -> Void
    ) {
        handleAction(action, completionHandler: completionHandler)
    }

    override func handle(
        action: ShieldAction,
        for category: ActivityCategoryToken,
        completionHandler: @escaping (ShieldActionResponse) -> Void
    ) {
        handleAction(action, completionHandler: completionHandler)
    }

    // MARK: - Shared Handler

    private func handleAction(
        _ action: ShieldAction,
        completionHandler: @escaping (ShieldActionResponse) -> Void
    ) {
        switch action {
        case .primaryButtonPressed:
            sharedDefaults?.set(true, forKey: "shield.shouldOpenWorkout")
            sharedDefaults?.synchronize()
            sendWorkoutNotification()
            completionHandler(.close)

        case .secondaryButtonPressed:
            completionHandler(.defer)

        @unknown default:
            completionHandler(.close)
        }
    }

    // MARK: - Notification

    private func sendWorkoutNotification() {
        let content = UNMutableNotificationContent()
        content.title = "Ready to train?"
        content.body = "Tap to open PushUp and start your workout."
        content.sound = .default
        content.userInfo = ["action": "openWorkout"]

        let request = UNNotificationRequest(
            identifier: "shield.openWorkout",
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request) { _ in }
    }
}
