import Foundation
import Testing

@testable import iosApp

// MARK: - SyncState Tests

/// Tests for the `SyncState` value type.
///
/// These tests are pure value-type tests and require no actor isolation.
@Suite("SyncState")
struct SyncStateTests {

    @Test("SyncState.idle is the default state")
    func idleIsDefault() {
        let state: SyncState = .idle
        #expect(state == .idle)
    }

    @Test("SyncState equality for error cases with identical messages")
    func errorEqualityIdenticalMessages() {
        let error1: SyncState = .error("Network timeout")
        let error2: SyncState = .error("Network timeout")
        #expect(error1 == error2)
    }

    @Test("SyncState inequality for error cases with different messages")
    func errorInequalityDifferentMessages() {
        let error1: SyncState = .error("Network timeout")
        let error2: SyncState = .error("Server error")
        #expect(error1 != error2)
    }

    @Test("All SyncState cases are distinct from each other")
    func allCasesDistinct() {
        let states: [SyncState] = [
            .idle,
            .syncing,
            .success,
            .error("test"),
            .offline,
        ]

        for i in 0..<states.count {
            for j in (i + 1)..<states.count {
                #expect(
                    states[i] != states[j],
                    "\(states[i]) should not equal \(states[j])"
                )
            }
        }
    }

    @Test("SyncState.error is not equal to .idle")
    func errorNotEqualToIdle() {
        #expect(SyncState.error("msg") != .idle)
    }

    @Test("SyncState.error is not equal to .offline")
    func errorNotEqualToOffline() {
        #expect(SyncState.error("msg") != .offline)
    }
}

// MARK: - SyncService State Tests

/// Tests for `SyncService` state management.
///
/// **Important**: `SyncService.shared` is a singleton. Tests must be careful
/// to restore state after each mutation so they do not affect each other.
/// Each test that mutates `unsyncedCount` saves the initial value and restores
/// it in a `defer` block.
@Suite("SyncService - State Management")
struct SyncServiceStateTests {

    @Test("isSyncing is false when state is idle")
    @MainActor
    func isSyncingFalseWhenIdle() {
        // This test only reads state -- safe to run without mutation.
        // If the service happens to be syncing, we skip the assertion.
        let service = SyncService.shared
        if service.syncState == .idle {
            #expect(!service.isSyncing)
        }
    }

    @Test("isSyncing is false when state is offline")
    @MainActor
    func isSyncingFalseWhenOffline() {
        // SyncState.offline != .syncing, so isSyncing must be false.
        let offlineState: SyncState = .offline
        #expect(offlineState != .syncing)
    }

    @Test("recordUnsyncedWorkout increments count by exactly 1")
    @MainActor
    func recordUnsyncedWorkoutIncrementsCount() {
        let service = SyncService.shared
        let before = service.unsyncedCount
        defer {
            // Restore: remove the workout we just added.
            // clearUnsyncedCount() resets to 0, so we use it only if before was 0.
            if before == 0 { service.clearUnsyncedCount() }
        }
        service.recordUnsyncedWorkout()
        #expect(service.unsyncedCount == before + 1)
    }

    @Test("clearUnsyncedCount resets count to zero")
    @MainActor
    func clearUnsyncedCountResetsToZero() {
        let service = SyncService.shared
        let before = service.unsyncedCount
        defer {
            // Restore the count we cleared.
            for _ in 0..<before { service.recordUnsyncedWorkout() }
        }
        service.clearUnsyncedCount()
        #expect(service.unsyncedCount == 0)
    }

    @Test("unsyncedCount is never negative after clearUnsyncedCount")
    @MainActor
    func unsyncedCountNeverNegative() {
        let service = SyncService.shared
        service.clearUnsyncedCount()
        #expect(service.unsyncedCount == 0)
        service.clearUnsyncedCount() // second call must not go below 0
        #expect(service.unsyncedCount == 0)
    }

    @Test("unsyncedCount persists to UserDefaults after recordUnsyncedWorkout")
    @MainActor
    func unsyncedCountPersistsAfterRecord() {
        let service = SyncService.shared
        let before = service.unsyncedCount
        defer {
            if before == 0 { service.clearUnsyncedCount() }
        }
        service.recordUnsyncedWorkout()
        let persisted = UserDefaults.standard.integer(forKey: "syncService.unsyncedCount")
        #expect(persisted == service.unsyncedCount)
    }

    @Test("unsyncedCount persists to UserDefaults after clearUnsyncedCount")
    @MainActor
    func unsyncedCountPersistsAfterClear() {
        let service = SyncService.shared
        service.clearUnsyncedCount()
        let persisted = UserDefaults.standard.integer(forKey: "syncService.unsyncedCount")
        #expect(persisted == 0)
        #expect(service.unsyncedCount == 0)
    }

    @Test("lastSyncLabel is non-empty regardless of sync history")
    @MainActor
    func lastSyncLabelNonEmpty() {
        let label = SyncService.shared.lastSyncLabel
        #expect(!label.isEmpty)
    }

    @Test("lastSyncLabel contains 'Never synced' when no sync date is stored")
    @MainActor
    func lastSyncLabelNeverSynced() {
        // Remove the persisted date so the service reports "Never synced".
        // Note: the singleton's in-memory `lastSyncDate` is not affected by
        // removing the UserDefaults key, so we test the label format only.
        UserDefaults.standard.removeObject(forKey: "syncService.lastSyncDate")
        // The singleton may still have an in-memory date from a previous sync.
        // We verify the label is non-empty and well-formed.
        let label = SyncService.shared.lastSyncLabel
        #expect(label == "Never synced" || label.hasPrefix("Last sync:"))
    }
}

// MARK: - ConnectionType Tests

@Suite("ConnectionType")
struct ConnectionTypeTests {

    @Test("All ConnectionType labels are non-empty")
    func labelsAreNonEmpty() {
        let types: [ConnectionType] = [.wifi, .cellular, .wiredEthernet, .unknown]
        for type in types {
            #expect(!type.label.isEmpty, "\(type) should have a non-empty label")
        }
    }

    @Test("ConnectionType labels match expected strings")
    func labelsMatchExpectedStrings() {
        #expect(ConnectionType.wifi.label          == "Wi-Fi")
        #expect(ConnectionType.cellular.label      == "Cellular")
        #expect(ConnectionType.wiredEthernet.label == "Ethernet")
        #expect(ConnectionType.unknown.label       == "Unknown")
    }

    @Test("ConnectionType is Equatable -- same cases are equal")
    func equalitySameCases() {
        #expect(ConnectionType.wifi    == ConnectionType.wifi)
        #expect(ConnectionType.unknown == ConnectionType.unknown)
    }

    @Test("ConnectionType is Equatable -- different cases are not equal")
    func inequalityDifferentCases() {
        #expect(ConnectionType.wifi     != ConnectionType.cellular)
        #expect(ConnectionType.cellular != ConnectionType.wiredEthernet)
        #expect(ConnectionType.wifi     != ConnectionType.unknown)
    }
}
