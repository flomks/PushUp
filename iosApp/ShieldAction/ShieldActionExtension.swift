import ManagedSettings

// MARK: - ShieldActionExtension

/// Handles button taps on the system app shield (lock screen).
///
/// Primary button ("Do Push-Ups Now") -- closes the shield and opens
/// the PushUp app so the user can start a workout immediately.
///
/// Secondary button ("Not Now") -- defers, shield stays visible.
///
/// **Bundle ID:** `com.flomks.pushup.ShieldAction`
class ShieldActionExtension: ShieldActionDelegate {

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
            // Close the shield -- iOS will bring the PushUp app to foreground
            // if the user taps the notification or opens it manually.
            completionHandler(.close)
        case .secondaryButtonPressed:
            // Keep the shield visible.
            completionHandler(.defer)
        @unknown default:
            completionHandler(.close)
        }
    }
}
