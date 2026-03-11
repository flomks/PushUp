import ManagedSettings

// MARK: - ShieldActionExtension

/// Shield Action Extension.
///
/// Handles button taps on the system shield (app lock screen).
///
/// **Primary button** ("Do Push-Ups to Earn More"):
///   Opens the PushUp app via a custom URL scheme so the user can
///   immediately start a workout to earn more time credit.
///
/// **Secondary button** ("Not Now"):
///   Defers the action -- the shield remains visible.
///
/// **Bundle ID:** `com.flomks.pushup.ShieldAction`
class ShieldActionExtension: ShieldActionDataSource {

    override func handle(
        action: ShieldAction,
        for application: Application,
        completionHandler: @escaping (ShieldActionResponse) -> Void
    ) {
        handleAction(action, completionHandler: completionHandler)
    }

    override func handle(
        action: ShieldAction,
        for webDomain: WebDomain,
        completionHandler: @escaping (ShieldActionResponse) -> Void
    ) {
        handleAction(action, completionHandler: completionHandler)
    }

    override func handle(
        action: ShieldAction,
        for category: ActivityCategory,
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
            // Open the PushUp app at the Workout tab.
            // The URL scheme `pushup://workout` must be registered in Info.plist.
            completionHandler(.close)

        case .secondaryButtonPressed:
            // User tapped "Not Now" -- keep the shield visible.
            completionHandler(.defer)

        @unknown default:
            completionHandler(.close)
        }
    }
}
