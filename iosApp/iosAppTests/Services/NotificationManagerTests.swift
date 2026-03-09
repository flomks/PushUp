import Foundation
import Testing

@testable import iosApp

// MARK: - NotificationIdentifier Tests

/// Tests for the `NotificationIdentifier` constants and the pure-logic
/// helpers on `NotificationManager` that do not require `UNUserNotificationCenter`.
///
/// Note: Scheduling and authorisation methods cannot be unit-tested without
/// a real device or simulator because `UNUserNotificationCenter` is not
/// mockable. These tests focus on the testable surface: identifier constants,
/// `hasWorkedOutToday()`, `recordWorkoutToday()`, and input validation.
@Suite("NotificationIdentifier")
struct NotificationIdentifierTests {

    @Test("All identifiers are unique")
    func identifiersAreUnique() {
        let all = [
            NotificationIdentifier.dailyReminder,
            NotificationIdentifier.streakWarning,
            NotificationIdentifier.creditWarning,
            NotificationIdentifier.workoutComplete,
        ]
        let unique = Set(all)
        #expect(unique.count == all.count, "Notification identifiers must be unique")
    }

    @Test("All identifiers use reverse-DNS format")
    func identifiersUseReverseDNS() {
        let all = [
            NotificationIdentifier.dailyReminder,
            NotificationIdentifier.streakWarning,
            NotificationIdentifier.creditWarning,
            NotificationIdentifier.workoutComplete,
        ]
        for id in all {
            #expect(id.hasPrefix("com.pushup.notification."), "Identifier '\(id)' should use reverse-DNS prefix")
        }
    }

    @Test("allRecurring contains only daily reminder and streak warning")
    func allRecurringContainsCorrectIdentifiers() {
        let recurring = NotificationIdentifier.allRecurring
        #expect(recurring.contains(NotificationIdentifier.dailyReminder))
        #expect(recurring.contains(NotificationIdentifier.streakWarning))
        #expect(!recurring.contains(NotificationIdentifier.creditWarning))
        #expect(!recurring.contains(NotificationIdentifier.workoutComplete))
        #expect(recurring.count == 2)
    }
}

// MARK: - Workout Date Tracking Tests

@Suite("NotificationManager - Workout Date Tracking")
struct WorkoutDateTrackingTests {

    /// Cleans up UserDefaults before each test to ensure isolation.
    init() {
        UserDefaults.standard.removeObject(forKey: NotificationManager.lastWorkoutDateKey)
    }

    @Test("hasWorkedOutToday returns false when no workout recorded")
    @MainActor
    func noWorkoutRecorded() {
        let manager = NotificationManager.shared
        #expect(!manager.hasWorkedOutToday())
    }

    @Test("hasWorkedOutToday returns true after recordWorkoutToday")
    @MainActor
    func workoutRecordedToday() {
        let manager = NotificationManager.shared
        manager.recordWorkoutToday()
        #expect(manager.hasWorkedOutToday())
    }

    @Test("hasWorkedOutToday returns false for a different date")
    @MainActor
    func workoutRecordedDifferentDay() {
        // Write a date string for yesterday.
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: Date())!
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate]
        let yesterdayString = formatter.string(from: yesterday)
        UserDefaults.standard.set(yesterdayString, forKey: NotificationManager.lastWorkoutDateKey)

        let manager = NotificationManager.shared
        #expect(!manager.hasWorkedOutToday())
    }

    @Test("recordWorkoutToday overwrites previous date")
    @MainActor
    func recordOverwritesPrevious() {
        // Write yesterday's date first.
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: Date())!
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate]
        let yesterdayString = formatter.string(from: yesterday)
        UserDefaults.standard.set(yesterdayString, forKey: NotificationManager.lastWorkoutDateKey)

        #expect(!NotificationManager.shared.hasWorkedOutToday())

        NotificationManager.shared.recordWorkoutToday()
        #expect(NotificationManager.shared.hasWorkedOutToday())
    }
}

// MARK: - SettingsKeys Consistency Tests

@Suite("SettingsKeys - Notification Keys")
struct SettingsKeysNotificationTests {

    @Test("Notification settings keys are non-empty and prefixed")
    func keysAreValid() {
        let keys = [
            SettingsKeys.notificationsEnabled,
            SettingsKeys.notificationHour,
            SettingsKeys.notificationMinute,
        ]
        for key in keys {
            #expect(!key.isEmpty)
            #expect(key.hasPrefix("settings."), "Key '\(key)' should use 'settings.' prefix")
        }
    }
}
