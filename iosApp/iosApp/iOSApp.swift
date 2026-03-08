import SwiftUI
import shared

@main
struct iOSApp: App {

    init() {
        // Initialise the Koin dependency-injection graph before any
        // KMP-managed object is accessed. This must run before the first
        // SwiftUI scene is rendered.
        KoinIOSKt.doInitKoin()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
