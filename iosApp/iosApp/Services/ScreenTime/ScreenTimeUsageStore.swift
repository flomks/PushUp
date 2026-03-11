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

// MARK: - ScreenTimeUsageStore

/// Reads and writes Screen Time usage data from the shared App Group container.
///
/// The DeviceActivity Extension writes usage records when thresholds are hit.
/// The main app reads them to display statistics in the Screen Time Stats view.
///
/// All operations are synchronous and lightweight -- the data set is small
/// (one record per day, max ~365 records per year).
final class ScreenTimeUsageStore {

    // MARK: - Singleton

    static let shared = ScreenTimeUsageStore()

    // MARK: - Private

    private let defaults: UserDefaults?

    private init() {
        defaults = UserDefaults(suiteName: ScreenTimeConstants.appGroupID)
    }

    // MARK: - Read

    /// Returns all stored usage records, sorted by date descending (newest first).
    func allRecords() -> [AppUsageRecord] {
        guard let data = defaults?.data(forKey: ScreenTimeConstants.Keys.usageData),
              let records = try? JSONDecoder().decode([AppUsageRecord].self, from: data)
        else { return [] }
        return records.sorted { $0.date > $1.date }
    }

    /// Returns the usage record for today, or nil if none exists yet.
    func todayRecord() -> AppUsageRecord? {
        let today = isoDateString(from: Date())
        return allRecords().first { $0.date == today }
    }

    /// Returns usage records for the last `days` days (including today).
    func records(forLastDays days: Int) -> [AppUsageRecord] {
        let calendar = Calendar.current
        let cutoff = calendar.date(byAdding: .day, value: -(days - 1), to: Date()) ?? Date()
        let cutoffString = isoDateString(from: cutoff)
        return allRecords().filter { $0.date >= cutoffString }
    }

    /// Total seconds used across all tracked apps today.
    var todayUsageSeconds: Int {
        todayRecord()?.totalSeconds ?? 0
    }

    /// Total seconds used across all tracked apps in the last 7 days.
    var weeklyUsageSeconds: Int {
        records(forLastDays: 7).reduce(0) { $0 + $1.totalSeconds }
    }

    // MARK: - Write

    /// Saves or updates the usage record for today.
    ///
    /// Called by the DeviceActivity Extension when a threshold event fires.
    func saveRecord(_ record: AppUsageRecord) {
        var records = allRecords()

        // Replace existing record for the same date, or append.
        if let index = records.firstIndex(where: { $0.date == record.date }) {
            records[index] = record
        } else {
            records.append(record)
        }

        // Keep only the last 90 days to avoid unbounded growth.
        let cutoff = isoDateString(from: Calendar.current.date(
            byAdding: .day, value: -90, to: Date()) ?? Date()
        )
        records = records.filter { $0.date >= cutoff }

        guard let data = try? JSONEncoder().encode(records) else { return }
        defaults?.set(data, forKey: ScreenTimeConstants.Keys.usageData)
    }

    /// Clears all stored usage records.
    func clearAll() {
        defaults?.removeObject(forKey: ScreenTimeConstants.Keys.usageData)
    }

    // MARK: - Helpers

    private func isoDateString(from date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter.string(from: date)
    }
}
