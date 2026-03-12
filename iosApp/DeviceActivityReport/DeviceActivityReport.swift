import DeviceActivity
import SwiftUI

// MARK: - DeviceActivityReport Extension Entry Point
//
// Registers the report scene that the main app embeds via:
//   DeviceActivityReport(.init("com.flomks.pushup.usageReport"), filter: ...)
//
// The system calls AppUsageReport.makeConfiguration() with the OS usage data,
// then renders AppUsageReportView with the resulting AppUsageConfiguration.
//
// Bundle ID: com.flomks.pushup.DeviceActivityReport
// Minimum deployment: iOS 16.4

@main
struct PushUpDeviceActivityReport: DeviceActivityReportExtension {
    var body: some DeviceActivityReportScene {
        AppUsageReport { configuration in
            AppUsageReportView(configuration: configuration)
        }
    }
}
