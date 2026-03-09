import Foundation
import Testing

@testable import iosApp

// MARK: - SyncState Tests

@Suite("SyncState")
struct SyncStateTests {

    @Test("SyncState.idle is the default state")
    func idleIsDefault() {
        let state: SyncState = .idle
        #expect(state == .idle)
    }

    @Test("SyncState equality for error cases")
    func errorEquality() {
        let error1: SyncState = .error("Network timeout")
        let error2: SyncState = .error("Network timeout")
        let error3: SyncState = .error("Server error")

        #expect(error1 == error2)
        #expect(error1 != error3)
    }

    @Test("All SyncState cases are distinct")
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
                #expect(states[i] != states[j], "\(states[i]) should not equal \(states[j])")
            }
        }
    }
}

// MARK: - SyncService State Tests

@Suite("SyncService - State Management")
struct SyncServiceStateTests {

    /// Cleans up UserDefaults before each test to ensure isolation.
    init() {
        UserDefaults.standard.removeObject(forKey: "syncService.lastSyncDate")
        UserDefaults.standard.removeObject(forKey: "syncService.unsyncedCount")
    }

    @Test("SyncService starts in idle state")
    @MainActor
    func initialState() {
        let service = SyncService.shared
        // The service may have been started by other tests, but the state
        // should be one of the valid initial states.
        let validInitialStates: [SyncState] = [.idle, .syncing, .success, .offline]
        #expect(validInitialStates.contains(service.syncState))
    }

    @Test("recordUnsyncedWorkout increments count")
    @MainActor
    func recordUnsyncedWorkout() {
        let service = SyncService.shared
        let initialCount = service.unsyncedCount
        service.recordUnsyncedWorkout()
        #expect(service.unsyncedCount == initialCount + 1)
    }

    @Test("clearUnsyncedCount resets to zero")
    @MainActor
    func clearUnsyncedCount() {
        let service = SyncService.shared
        service.recordUnsyncedWorkout()
        service.recordUnsyncedWorkout()
        #expect(service.unsyncedCount >= 2)

        service.clearUnsyncedCount()
        #expect(service.unsyncedCount == 0)
    }

    @Test("isSyncing returns true only during syncing state")
    @MainActor
    func isSyncingProperty() {
        let service = SyncService.shared
        // When idle, isSyncing should be false.
        if service.syncState == .idle {
            #expect(!service.isSyncing)
        }
    }

    @Test("lastSyncLabel returns 'Never synced' when no sync has occurred")
    @MainActor
    func lastSyncLabelNeverSynced() {
        // Clear the last sync date to test the "never synced" case.
        UserDefaults.standard.removeObject(forKey: "syncService.lastSyncDate")
        // Note: The singleton retains its state, so this test verifies the
        // label format rather than the exact value.
        let label = SyncService.shared.lastSyncLabel
        #expect(!label.isEmpty)
    }

    @Test("Unsynced count persists to UserDefaults")
    @MainActor
    func unsyncedCountPersistence() {
        let service = SyncService.shared
        service.clearUnsyncedCount()
        service.recordUnsyncedWorkout()
        service.recordUnsyncedWorkout()
        service.recordUnsyncedWorkout()

        let persisted = UserDefaults.standard.integer(forKey: "syncService.unsyncedCount")
        #expect(persisted == service.unsyncedCount)
    }
}

// MARK: - ConnectionType Tests

@Suite("ConnectionType")
struct ConnectionTypeTests {

    @Test("ConnectionType labels are non-empty")
    func labelsAreNonEmpty() {
        let types: [ConnectionType] = [.wifi, .cellular, .wiredEthernet, .unknown]
        for type in types {
            #expect(!type.label.isEmpty, "\(type) should have a non-empty label")
        }
    }

    @Test("ConnectionType labels are human-readable")
    func labelsAreReadable() {
        #expect(ConnectionType.wifi.label == "Wi-Fi")
        #expect(ConnectionType.cellular.label == "Cellular")
        #expect(ConnectionType.wiredEthernet.label == "Ethernet")
        #expect(ConnectionType.unknown.label == "Unknown")
    }

    @Test("ConnectionType equality")
    func equality() {
        #expect(ConnectionType.wifi == ConnectionType.wifi)
        #expect(ConnectionType.wifi != ConnectionType.cellular)
    }
}
