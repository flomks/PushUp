import SwiftUI
import UIKit

/// Root entry point of the PushUp iOS application.
///
/// Koin is initialised in `AppDelegate.application(_:didFinishLaunchingWithOptions:)`
/// before the first SwiftUI scene is rendered, ensuring all KMP-managed
/// dependencies are available when the UI starts.
@main
struct PushUpApp: App {

    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
