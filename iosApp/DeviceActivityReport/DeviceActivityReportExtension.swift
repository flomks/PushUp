import DeviceActivity
import SwiftUI

// MARK: - DeviceActivityReportExtension
//
// This extension is the entry point for the Device Activity Report target.
// It registers one report scene identified by "com.flomks.pushup.usageReport".
//
// The system calls this extension whenever the main app embeds a
// DeviceActivityReport view with the matching context name. The extension
// receives the aggregated usage data from the OS and renders it as a
// SwiftUI view that is injected directly into the main app's view hierarchy.
//
// iOS 16.4+ required.
// Bundle ID: com.flomks.pushup.DeviceActivityReport

@main
struct PushUpDeviceActivityReportExtension: DeviceActivityReportExtension {

    var body: some DeviceActivityReportScene {
        DeviceActivityReport(.init("com.flomks.pushup.usageReport")) { context in
            AppUsageReportView(context: context)
        }
    }
}

// MARK: - AppUsageReportView

/// The SwiftUI view rendered inside the DeviceActivityReport container.
///
/// This view has privileged access to the actual per-app usage data from
/// the OS, including real app names, icons, and precise durations.
/// It is injected directly into the main app's view hierarchy by the system.
///
/// In addition to rendering the UI, it writes the usage data to the shared
/// App Group container so the main app can use it for threshold calculations.
struct AppUsageReportView: View {

    let context: DeviceActivityResults<DeviceActivityData>

    @State private var appEntries: [AppEntry] = []
    @State private var totalDuration: TimeInterval = 0
    @State private var isLoaded = false

    private let sharedDefaults = UserDefaults(suiteName: "group.com.flomks.pushup")

    var body: some View {
        Group {
            if !isLoaded {
                loadingView
            } else if appEntries.isEmpty {
                emptyView
            } else {
                appList
            }
        }
        .task {
            await loadData()
        }
    }

    // MARK: - App List

    private var appList: some View {
        VStack(spacing: 0) {
            ForEach(Array(appEntries.enumerated()), id: \.element.id) { index, entry in
                if index > 0 {
                    Divider()
                        .padding(.leading, 52)
                }
                appRow(entry: entry)
            }
        }
    }

    private func appRow(_ entry: AppEntry) -> some View {
        HStack(spacing: 12) {
            // App icon (real icon from the OS via Label)
            entry.label
                .labelStyle(.iconOnly)
                .frame(width: 36, height: 36)
                .clipShape(RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 3) {
                // App name (real name from the OS via Label)
                entry.label
                    .labelStyle(.titleOnly)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color.primary)
                    .lineLimit(1)

                // Usage bar
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(Color(.systemFill))
                            .frame(height: 4)

                        RoundedRectangle(cornerRadius: 2)
                            .fill(barColor(for: entry.duration))
                            .frame(
                                width: geo.size.width * barFraction(for: entry.duration),
                                height: 4
                            )
                    }
                }
                .frame(height: 4)
            }

            Spacer()

            Text(formatDuration(entry.duration))
                .font(.system(size: 13, weight: .semibold).monospacedDigit())
                .foregroundStyle(Color.primary)
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 16)
    }

    // MARK: - Loading / Empty

    private var loadingView: some View {
        HStack {
            Spacer()
            ProgressView()
                .progressViewStyle(.circular)
                .padding(.vertical, 20)
            Spacer()
        }
    }

    private var emptyView: some View {
        VStack(spacing: 8) {
            Image(systemName: "app.badge")
                .font(.system(size: 32, weight: .light))
                .foregroundStyle(Color.secondary)
            Text("No app usage recorded yet today.")
                .font(.system(size: 14))
                .foregroundStyle(Color.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.vertical, 24)
        .padding(.horizontal, 16)
    }

    // MARK: - Data Loading

    private func loadData() async {
        var entries: [AppEntry] = []
        var total: TimeInterval = 0
        var perAppJSON: [[String: Any]] = []

        for await data in context {
            for await segment in data.activitySegments {
                for await category in segment.categories {
                    let categoryName = category.category.localizedDisplayName ?? ""
                    for await app in category.applications {
                        let duration = app.totalActivityDuration
                        guard duration > 0 else { continue }

                        total += duration
                        entries.append(AppEntry(
                            id: app.application.bundleIdentifier ?? UUID().uuidString,
                            label: app.application.label,
                            duration: duration,
                            categoryName: categoryName
                        ))

                        // Collect data for App Group persistence
                        perAppJSON.append([
                            "bundleID": app.application.bundleIdentifier ?? "unknown",
                            "seconds": Int(duration),
                            "categoryToken": categoryName
                        ])
                    }
                }
            }
        }

        // Sort by duration descending
        entries.sort { $0.duration > $1.duration }

        await MainActor.run {
            self.appEntries = entries
            self.totalDuration = total
            self.isLoaded = true
        }

        // Persist to App Group for main app threshold calculations
        persistToAppGroup(perAppJSON: perAppJSON, totalSeconds: Int(total))
    }

    // MARK: - App Group Persistence

    private func persistToAppGroup(perAppJSON: [[String: Any]], totalSeconds: Int) {
        guard let data = try? JSONSerialization.data(withJSONObject: perAppJSON) else { return }
        sharedDefaults?.set(data, forKey: "screentime.perAppUsageData")

        let today = isoDateString(from: Date())
        sharedDefaults?.set(today, forKey: "screentime.todaySystemUsageDate")

        if totalSeconds > 0 {
            let existing = sharedDefaults?.integer(forKey: "screentime.todaySystemUsageSeconds") ?? 0
            if totalSeconds > existing {
                sharedDefaults?.set(totalSeconds, forKey: "screentime.todaySystemUsageSeconds")
            }
        }
    }

    // MARK: - Helpers

    private func barFraction(for duration: TimeInterval) -> CGFloat {
        guard totalDuration > 0 else { return 0 }
        return min(1.0, CGFloat(duration / totalDuration))
    }

    private func barColor(for duration: TimeInterval) -> Color {
        let fraction = duration / max(1, totalDuration)
        if fraction >= 0.5 { return .red }
        if fraction >= 0.3 { return .orange }
        return .blue
    }

    private func formatDuration(_ duration: TimeInterval) -> String {
        let seconds = Int(duration)
        if seconds < 60 { return "\(seconds)s" }
        let h = seconds / 3600
        let m = (seconds % 3600) / 60
        if h > 0 { return "\(h)h \(m)m" }
        return "\(m)m"
    }

    private func isoDateString(from date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter.string(from: date)
    }
}

// MARK: - AppEntry

/// A single app usage entry for display in the report view.
struct AppEntry: Identifiable {
    let id: String
    let label: Label<Text, Image>
    let duration: TimeInterval
    let categoryName: String
}
