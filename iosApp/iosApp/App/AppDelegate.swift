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
        return true
    }
}
