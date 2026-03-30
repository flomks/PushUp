import DeviceActivity
import FamilyControls
import ManagedSettings
import SwiftUI

// MARK: - DeviceActivityReport.Context

extension DeviceActivityReport.Context {
    /// The context name used by the main app when embedding the report:
    ///   `DeviceActivityReport(.init("com.flomks.pushup.usageReport"), filter: ...)`
    static let pushUpUsageReport = Self("com.flomks.pushup.usageReport")
}

// MARK: - AppUsageConfiguration

/// The processed usage data passed from the report scene to the view.
///
/// `makeConfiguration` runs in the extension process with full access to
/// OS usage data. It extracts per-app entries and writes them to the
/// shared App Group container for the main app to use in threshold calculations.
struct AppUsageConfiguration: Sendable {
    /// Per-app usage entries, sorted by duration descending.
    let entries: [AppUsageEntry]
    /// Total usage duration across all tracked apps.
    let totalDuration: TimeInterval
}

// MARK: - AppUsageEntry

/// A single app's usage data for display in the report view.
///
/// Stores an `ApplicationToken` so `TotalActivityView` can render the real
/// app icon via `Label(token)`. `ApplicationToken` is `Token<Application>`,
/// which is `Codable`, `Hashable`, and safe to pass across the actor boundary
/// between `makeConfiguration` and the SwiftUI view.
struct AppUsageEntry: Identifiable, Sendable {
    /// The app's bundle identifier (used as stable ID).
    let id: String
    /// Localized display name from the OS (e.g. "Instagram").
    let displayName: String
    /// Total usage duration for this app today.
    let duration: TimeInterval
    /// The category this app belongs to (e.g. "Social Networking").
    let categoryName: String
    /// The opaque application token -- used to render the real app icon
    /// via `Label(token)` inside the DeviceActivityReport extension view.
    let token: ApplicationToken
}

// MARK: - AppUsageReport

/// The DeviceActivityReportScene that processes OS usage data.
///
/// `makeConfiguration` is called by the system with the aggregated usage
/// data. It runs asynchronously in the extension process and has full
/// access to real app names, icons, and durations.
struct AppUsageReport: DeviceActivityReportScene {

    let context: DeviceActivityReport.Context = .pushUpUsageReport
    let content: (AppUsageConfiguration) -> AppUsageReportView

    func makeConfiguration(
        representing data: DeviceActivityResults<DeviceActivityData>
    ) async -> AppUsageConfiguration {

        var entries: [AppUsageEntry] = []
        var totalDuration: TimeInterval = 0
        var perAppJSON: [[String: Any]] = []

        for await activityData in data {
            for await segment in activityData.activitySegments {
                for await category in segment.categories {
                    let categoryName = category.category.localizedDisplayName ?? ""
                    for await appActivity in category.applications {
                        let duration = appActivity.totalActivityDuration
                        let app = appActivity.application
                        // ApplicationToken is required to render the app icon via
                        // Label(token). Skip entries where the token is unavailable.
                        guard let appToken = app.token else { continue }
                        let bundleID = app.bundleIdentifier ?? UUID().uuidString
                        let displayName = app.localizedDisplayName ?? bundleID

                        // Include all apps (even 0-duration) so the full selected
                        // list is shown. Only add to totalDuration if actually used.
                        if duration > 0 {
                            totalDuration += duration
                        }

                        entries.append(AppUsageEntry(
                            id: bundleID,
                            displayName: displayName,
                            duration: duration,
                            categoryName: categoryName,
                            token: appToken
                        ))

                        if duration > 0 {
                            perAppJSON.append([
                                "bundleID": bundleID,
                                "seconds": Int(duration),
                                "categoryToken": categoryName
                            ])
                        }
                    }
                }
            }
        }

        // Sort by duration descending
        entries.sort { $0.duration > $1.duration }

        // Persist to App Group for main app threshold calculations.
        // This is the authoritative OS-tracked usage value -- reinstall-proof.
        persistToAppGroup(perAppJSON: perAppJSON, totalSeconds: Int(totalDuration))

        return AppUsageConfiguration(entries: entries, totalDuration: totalDuration)
    }

    // MARK: - App Group Persistence

    private func persistToAppGroup(perAppJSON: [[String: Any]], totalSeconds: Int) {
        guard let defaults = UserDefaults(suiteName: "group.com.flomks.pushup") else { return }

        if let data = try? JSONSerialization.data(withJSONObject: perAppJSON) {
            defaults.set(data, forKey: "screentime.perAppUsageData")
        }

        let today = isoDateString(from: Date())
        defaults.set(today, forKey: "screentime.todaySystemUsageDate")

        if totalSeconds > 0 {
            let existing = defaults.integer(forKey: "screentime.todaySystemUsageSeconds")
            if totalSeconds > existing {
                defaults.set(totalSeconds, forKey: "screentime.todaySystemUsageSeconds")
            }
        }
    }

    private static let isoFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

    private func isoDateString(from date: Date) -> String {
        Self.isoFormatter.string(from: date)
    }
}
