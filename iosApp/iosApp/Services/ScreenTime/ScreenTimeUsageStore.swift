import Foundation

// MARK: - AppUsageRecord

/// A single app usage record for one day.
///
/// Stored in the App Group container so both the main app and the
/// DeviceActivity Extension can read and write usage data.
struct AppUsageRecord: Codable, Identifiable {

    /// Stable identifier: ISO date string "yyyy-MM-dd".
    var id: String { date }

    /// ISO date string "yyyy-MM-dd".
    let date: String

    /// Total usage in seconds for the tracked apps on this day.
    let totalSeconds: Int

    /// Usage breakdown per category token (opaque string key).
    let categoryBreakdown: [String: Int]

    /// Number of times the shield was triggered on this day.
    let shieldTriggerCount: Int

    /// Whether the daily credit was fully consumed on this day.
    let creditExhausted: Bool
}

// MARK: - PerAppUsageRecord

/// Per-app usage data for a single app on a given day.
///
/// Written by the DeviceActivityReport extension and read by the main app
/// to display per-app usage statistics in the Stats screen.
struct PerAppUsageRecord: Codable, Identifiable {

    /// Stable identifier: bundle ID.
    var id: String { bundleID }

    /// The app's bundle identifier (e.g. "com.apple.mobilesafari").
    let bundleID: String

    /// Total usage in seconds for this app today.
    let seconds: Int

    /// The category name this app belongs to (e.g. "Social Networking").
    let categoryToken: String
}

// MARK: - ScreenTimeUsageStore

/// Reads and writes Screen Time usage data from the shared App Group container.
///
/// The DeviceActivity Extension writes usage records when thresholds are hit.
/// The DeviceActivityReport extension writes per-app usage data.
/// The main app reads them to display statistics in the Screen Time Stats view.
///
/// All operations are synchronous and lightweight -- the data set is small
/// (one record per day, max ~365 records per year).
///
/// Uses a short-lived cache to avoid redundant JSON decoding when multiple
/// computed properties are accessed in the same run-loop cycle.
final class ScreenTimeUsageStore {

    // MARK: - Singleton

    static let shared = ScreenTimeUsageStore()

    // MARK: - Cached DateFormatter

    private static let isoFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

    // MARK: - Records Cache

    /// Short-lived cache for `allRecords()`. Invalidated after 1 second so
    /// repeated reads within the same run-loop cycle (e.g. `todayRecord()`
    /// → `allRecords()`, `todayUsageSeconds` → `todayRecord()` → `allRecords()`)
    /// don't each decode the full JSON blob from UserDefaults.
    private var cachedRecords: [AppUsageRecord]?
    private var cacheTimestamp: Date = .distantPast
    private static let cacheTTL: TimeInterval = 1.0

    private func invalidateCache() {
        cachedRecords = nil
        cacheTimestamp = .distantPast
    }

    // MARK: - Private

    private let defaults: UserDefaults?

    private init() {
        defaults = UserDefaults(suiteName: ScreenTimeConstants.appGroupID)
    }

    // MARK: - Read: Daily Records

    /// Returns all stored usage records, sorted by date descending (newest first).
    func allRecords() -> [AppUsageRecord] {
        let now = Date()
        if let cached = cachedRecords, now.timeIntervalSince(cacheTimestamp) < Self.cacheTTL {
            return cached
        }

        guard let data = defaults?.data(forKey: ScreenTimeConstants.Keys.usageData),
              let records = try? JSONDecoder().decode([AppUsageRecord].self, from: data)
        else {
            cachedRecords = []
            cacheTimestamp = now
            return []
        }
        let sorted = records.sorted { $0.date > $1.date }
        cachedRecords = sorted
        cacheTimestamp = now
        return sorted
    }

    /// Returns the usage record for today, or nil if none exists yet.
    func todayRecord() -> AppUsageRecord? {
        let today = Self.isoFormatter.string(from: Date())
        return allRecords().first { $0.date == today }
    }

    /// Returns usage records for the last `days` days (including today).
    func records(forLastDays days: Int) -> [AppUsageRecord] {
        let calendar = Calendar.current
        let cutoff = calendar.date(byAdding: .day, value: -(days - 1), to: Date()) ?? Date()
        let cutoffString = Self.isoFormatter.string(from: cutoff)
        return allRecords().filter { $0.date >= cutoffString }
    }

    /// Total seconds used across all tracked apps today.
    var todayUsageSeconds: Int {
        let systemUsage = todaySystemUsageSeconds
        if systemUsage > 0 { return systemUsage }
        return todayRecord()?.totalSeconds ?? 0
    }

    /// Total seconds used across all tracked apps in the last 7 days.
    var weeklyUsageSeconds: Int {
        records(forLastDays: 7).reduce(0) { $0 + $1.totalSeconds }
    }

    // MARK: - Read: System Usage (Reinstall-proof)

    /// The OS-tracked cumulative usage for the selected apps today.
    ///
    /// This value is written by the DeviceActivityMonitorExtension and
    /// DeviceActivityReport extension. It survives app reinstall because
    /// the OS tracks usage independently of our UserDefaults.
    ///
    /// Returns 0 if no value has been recorded yet today.
    var todaySystemUsageSeconds: Int {
        let today = Self.isoFormatter.string(from: Date())
        let storedDate = defaults?.string(forKey: ScreenTimeConstants.Keys.todaySystemUsageDate) ?? ""
        guard storedDate == today else { return 0 }
        return defaults?.integer(forKey: ScreenTimeConstants.Keys.todaySystemUsageSeconds) ?? 0
    }

    // MARK: - Read: Per-App Usage

    /// Returns per-app usage records for today, sorted by usage descending.
    ///
    /// Written by the DeviceActivityReport extension. Returns an empty array
    /// if the extension has not yet written any data.
    func todayPerAppUsage() -> [PerAppUsageRecord] {
        guard let data = defaults?.data(forKey: ScreenTimeConstants.Keys.perAppUsageData),
              let records = try? JSONDecoder().decode([PerAppUsageRecord].self, from: data)
        else {
            return parseLegacyPerAppData()
        }
        return records.sorted { $0.seconds > $1.seconds }
    }

    /// Parses the raw JSON format written by the DeviceActivityReport extension.
    private func parseLegacyPerAppData() -> [PerAppUsageRecord] {
        guard let data = defaults?.data(forKey: ScreenTimeConstants.Keys.perAppUsageData),
              let raw = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]]
        else { return [] }

        return raw.compactMap { dict -> PerAppUsageRecord? in
            guard let bundleID = dict["bundleID"] as? String,
                  let seconds = dict["seconds"] as? Int
            else { return nil }
            let category = dict["categoryToken"] as? String ?? ""
            return PerAppUsageRecord(bundleID: bundleID, seconds: seconds, categoryToken: category)
        }.sorted { $0.seconds > $1.seconds }
    }

    // MARK: - Write

    /// Saves or updates the usage record for today.
    ///
    /// Called by the DeviceActivity Extension when a threshold event fires.
    func saveRecord(_ record: AppUsageRecord) {
        var records = allRecords()

        if let index = records.firstIndex(where: { $0.date == record.date }) {
            records[index] = record
        } else {
            records.append(record)
        }

        let cutoff = Self.isoFormatter.string(from: Calendar.current.date(
            byAdding: .day, value: -90, to: Date()) ?? Date()
        )
        records = records.filter { $0.date >= cutoff }

        guard let data = try? JSONEncoder().encode(records) else { return }
        defaults?.set(data, forKey: ScreenTimeConstants.Keys.usageData)
        invalidateCache()
    }

    /// Clears all stored usage records.
    func clearAll() {
        defaults?.removeObject(forKey: ScreenTimeConstants.Keys.usageData)
        defaults?.removeObject(forKey: ScreenTimeConstants.Keys.perAppUsageData)
        defaults?.removeObject(forKey: ScreenTimeConstants.Keys.todaySystemUsageSeconds)
        defaults?.removeObject(forKey: ScreenTimeConstants.Keys.todaySystemUsageDate)
        invalidateCache()
    }
}
