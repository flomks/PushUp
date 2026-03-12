import DeviceActivity
import SwiftUI

// MARK: - DeviceActivityReportExtension

/// DeviceActivity Report Extension.
///
/// This extension renders a SwiftUI view inside the system-provided
/// `DeviceActivityReport` container. It receives the aggregated usage
/// data from the OS and displays per-app usage statistics.
///
/// The extension also writes per-app usage data to the shared App Group
/// container so the main app can display it in the Stats screen without
/// needing to embed the report view.
///
/// **iOS 16.4+ required** for `DeviceActivityReportExtension`.
///
/// **Bundle ID:** `com.flomks.pushup.DeviceActivityReport`
@main
struct DeviceActivityReportExtension: DeviceActivityReportExtension {

    var body: some DeviceActivityReportScene {
        DeviceActivityReport(.init("com.flomks.pushup.usageReport")) { context in
            UsageReportView(context: context)
        }
    }
}

// MARK: - UsageReportView

/// SwiftUI view rendered inside the DeviceActivityReport container.
///
/// Displays per-app usage for the current day and writes the data
/// to the shared App Group container for the main app to read.
struct UsageReportView: View {

    let context: DeviceActivityResults<DeviceActivityData>

    private let sharedDefaults = UserDefaults(suiteName: "group.com.flomks.pushup")

    var body: some View {
        // This view is rendered inside the system report container.
        // We use it primarily to extract and persist usage data.
        // The actual UI is rendered in the main app via ScreenTimeAppUsageView.
        Color.clear
            .task {
                await persistUsageData()
            }
    }

    // MARK: - Data Persistence

    /// Extracts per-app usage from the DeviceActivityResults and writes
    /// it to the shared App Group container.
    ///
    /// The main app reads this data to display per-app usage statistics
    /// in the Stats screen and Dashboard.
    private func persistUsageData() async {
        var perAppRecords: [[String: Any]] = []
        var totalSeconds = 0

        for await data in context {
            for await activitySegment in data.activitySegments {
                for await categoryActivity in activitySegment.categories {
                    for await appActivity in categoryActivity.applications {
                        let bundleID = appActivity.application.bundleIdentifier ?? "unknown"
                        let seconds = Int(appActivity.totalActivityDuration)
                        totalSeconds += seconds

                        let record: [String: Any] = [
                            "bundleID": bundleID,
                            "seconds": seconds,
                            "categoryToken": categoryActivity.category.localizedDisplayName ?? ""
                        ]
                        perAppRecords.append(record)
                    }
                }
            }
        }

        // Write per-app data to shared container.
        if let data = try? JSONSerialization.data(withJSONObject: perAppRecords) {
            sharedDefaults?.set(data, forKey: "screentime.perAppUsageData")
        }

        // Update the authoritative system usage total.
        // This is the most accurate value available -- directly from the OS.
        let today = isoDateString(from: Date())
        let storedDate = sharedDefaults?.string(forKey: "screentime.todaySystemUsageDate") ?? ""
        if storedDate != today {
            sharedDefaults?.set(today, forKey: "screentime.todaySystemUsageDate")
        }
        if totalSeconds > 0 {
            let existing = sharedDefaults?.integer(forKey: "screentime.todaySystemUsageSeconds") ?? 0
            if totalSeconds > existing {
                sharedDefaults?.set(totalSeconds, forKey: "screentime.todaySystemUsageSeconds")
            }
        }
    }

    private func isoDateString(from date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter.string(from: date)
    }
}
