import ManagedSettings
import Foundation

// MARK: - ShieldActionExtension

/// Handles button taps on the system app shield (lock screen).
///
/// Primary button ("Do Push-Ups Now") -- sets a flag in the shared App Group
/// UserDefaults so the main app navigates directly to the Workout tab when
/// it next becomes active, then closes the shield.
///
/// Note: ShieldActionDelegate runs in a sandboxed extension process.
/// UIApplication.shared is not available, so we cannot open a URL directly.
/// Instead we write a flag to the shared App Group container. The main app
/// reads this flag in onReceive(.willEnterForeground) and switches to the
/// Workout tab automatically.
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
            // Signal the main app to navigate to the Workout tab.
            // The main app reads this flag when it enters the foreground.
            sharedDefaults?.set(true, forKey: "shield.shouldOpenWorkout")
            sharedDefaults?.synchronize()
            completionHandler(.close)

        case .secondaryButtonPressed:
            completionHandler(.defer)

        @unknown default:
            completionHandler(.close)
        }
    }
}
