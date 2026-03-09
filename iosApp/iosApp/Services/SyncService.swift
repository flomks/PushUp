import Foundation
import os.log

// MARK: - SyncState

/// Represents the current state of the sync engine.
///
/// Used by the UI to display the appropriate sync indicator (spinning icon,
/// success checkmark, error badge, or idle state).
enum SyncState: Equatable {
    /// No sync operation is in progress and no errors exist.
    case idle

    /// A sync operation is currently running.
    case syncing

    /// The last sync completed successfully.
    /// Transitions back to `.idle` after a brief display period.
    case success

    /// The last sync failed. The associated message describes the error.
    case error(String)

    /// The device is offline. Data will be synced when connectivity returns.
    case offline
}

// MARK: - SyncService

/// Presentation-layer sync orchestrator for the PushUp iOS app.
///
/// **Responsibilities**
/// - Publishes reactive sync state (`syncState`, `unsyncedCount`, `lastSyncDate`)
///   for SwiftUI views to observe.
/// - Coordinates with `NetworkMonitor` to trigger automatic sync on reconnect.
/// - Provides a manual `syncNow()` entry point for the Settings screen.
/// - Tracks the number of unsynced workouts for the badge indicator.
///
/// **Architecture**
/// The KMP shared module contains `SyncManager` which orchestrates the actual
/// sync use-cases (`SyncWorkoutsUseCase`, `SyncTimeCreditUseCase`,
/// `SyncFromCloudUseCase`). This Swift service wraps that functionality and
/// adds:
/// 1. Reactive `@Published` state for SwiftUI.
/// 2. Automatic reconnect-triggered sync via `NetworkMonitor.onReconnect`.
/// 3. Periodic background sync scheduling.
/// 4. Unsynced-data counting for the badge indicator.
///
/// In the current implementation, the sync operations are simulated because
/// the KMP `SyncManager` requires authenticated Supabase credentials which
/// are not yet configured. The architecture is fully wired so that replacing
/// the simulation with real KMP calls requires only removing the `Task.sleep`
/// stubs and uncommenting the `DIHelper.shared` calls.
///
/// **Threading**
/// All public methods and properties are `@MainActor`-isolated.
///
/// **Lifecycle**
/// Created as a singleton (`SyncService.shared`) and started in `AppDelegate`.
@MainActor
final class SyncService: ObservableObject {

    // MARK: - Singleton

    static let shared = SyncService()

    // MARK: - Published State

    /// The current sync state, observed by `SyncIndicator` and `OfflineBanner`.
    @Published private(set) var syncState: SyncState = .idle

    /// Number of workouts that have not yet been synced to the cloud.
    /// Displayed as a badge in the navigation bar and Settings screen.
    @Published private(set) var unsyncedCount: Int = 0

    /// The date of the last successful sync, or `nil` if no sync has completed.
    @Published private(set) var lastSyncDate: Date? = nil

    /// `true` while a sync operation is in progress. Convenience accessor
    /// for views that only need to know if syncing is active.
    var isSyncing: Bool { syncState == .syncing }

    // MARK: - Private

    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "com.pushup",
        category: "SyncService"
    )

    /// Timer for periodic background sync.
    private var periodicSyncTimer: Timer?

    /// Interval between periodic sync attempts (15 minutes).
    private static let periodicSyncInterval: TimeInterval = 15 * 60

    /// Duration to show the success state before returning to idle.
    private static let successDisplayDuration: UInt64 = 2_000_000_000 // 2 seconds

    // MARK: - UserDefaults Keys

    private static let lastSyncDateKey = "syncService.lastSyncDate"
    private static let unsyncedCountKey = "syncService.unsyncedCount"

    // MARK: - Init

    private init() {
        // Restore persisted state.
        lastSyncDate = UserDefaults.standard.object(forKey: Self.lastSyncDateKey) as? Date
        unsyncedCount = UserDefaults.standard.integer(forKey: Self.unsyncedCountKey)
    }

    // MARK: - Public API

    /// Starts the sync service: wires up the network reconnect handler and
    /// begins periodic background sync.
    ///
    /// Call this once from `AppDelegate.application(_:didFinishLaunchingWithOptions:)`.
    func start() {
        // Wire up automatic sync on network reconnect.
        NetworkMonitor.shared.onReconnect = { [weak self] in
            Task { @MainActor [weak self] in
                self?.logger.info("Network reconnected. Triggering automatic sync.")
                await self?.syncNow()
            }
        }

        // Update offline state based on current connectivity.
        updateOfflineState()

        // Start periodic background sync.
        startPeriodicSync()

        // Trigger an initial sync if online.
        if NetworkMonitor.shared.isConnected {
            Task { await syncNow() }
        }

        logger.info("SyncService started.")
    }

    /// Triggers a manual sync operation.
    ///
    /// This is the primary entry point for:
    /// - The manual "Sync Now" button in Settings.
    /// - Automatic reconnect-triggered sync.
    /// - Periodic background sync.
    ///
    /// If a sync is already in progress, this call is a no-op.
    func syncNow() async {
        guard syncState != .syncing else {
            logger.debug("Sync already in progress. Skipping.")
            return
        }

        guard NetworkMonitor.shared.isConnected else {
            syncState = .offline
            logger.info("Cannot sync: device is offline.")
            return
        }

        syncState = .syncing
        logger.info("Starting sync operation...")

        do {
            // ---------------------------------------------------------------
            // KMP SyncManager integration point.
            //
            // When Supabase credentials are configured, replace the simulation
            // below with:
            //
            //   let syncManager = DIHelper.shared.syncManager()
            //   let result = try await withCheckedThrowingContinuation { cont in
            //       syncManager.syncAll { result, error in
            //           if let error { cont.resume(throwing: error) }
            //           else { cont.resume(returning: result) }
            //       }
            //   }
            //
            // For now, simulate a sync operation with a short delay.
            // ---------------------------------------------------------------
            try await Task.sleep(nanoseconds: 1_500_000_000)

            // Simulate successful sync: clear unsynced count.
            unsyncedCount = 0
            persistUnsyncedCount()

            lastSyncDate = Date()
            UserDefaults.standard.set(lastSyncDate, forKey: Self.lastSyncDateKey)

            syncState = .success
            logger.info("Sync completed successfully.")

            // Return to idle after a brief success display.
            try? await Task.sleep(nanoseconds: Self.successDisplayDuration)
            if syncState == .success {
                syncState = .idle
            }

        } catch is CancellationError {
            syncState = .idle
            logger.debug("Sync cancelled.")
        } catch {
            syncState = .error(error.localizedDescription)
            logger.error("Sync failed: \(error.localizedDescription)")

            // Return to idle after displaying the error briefly.
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            if case .error = syncState {
                syncState = .idle
            }
        }
    }

    /// Records that a workout was completed locally and has not yet been synced.
    ///
    /// Call this from `WorkoutViewModel` after a session is saved to the local DB.
    /// The count is displayed as a badge on the sync indicator.
    func recordUnsyncedWorkout() {
        unsyncedCount += 1
        persistUnsyncedCount()
        logger.debug("Unsynced workout recorded. Total unsynced: \(self.unsyncedCount)")

        // Attempt immediate sync if online.
        if NetworkMonitor.shared.isConnected {
            Task { await syncNow() }
        }
    }

    /// Resets the unsynced count to zero. Called after a successful full sync.
    func clearUnsyncedCount() {
        unsyncedCount = 0
        persistUnsyncedCount()
    }

    /// Returns a human-readable string describing when the last sync occurred.
    var lastSyncLabel: String {
        guard let date = lastSyncDate else {
            return "Never synced"
        }

        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return "Last sync: \(formatter.localizedString(for: date, relativeTo: Date()))"
    }

    // MARK: - Private Methods

    /// Updates `syncState` to `.offline` if the device has no connectivity,
    /// or back to `.idle` if it was previously offline and is now connected.
    private func updateOfflineState() {
        if !NetworkMonitor.shared.isConnected {
            syncState = .offline
        } else if syncState == .offline {
            syncState = .idle
        }
    }

    /// Starts a repeating timer that triggers `syncNow()` at regular intervals.
    private func startPeriodicSync() {
        periodicSyncTimer?.invalidate()
        periodicSyncTimer = Timer.scheduledTimer(
            withTimeInterval: Self.periodicSyncInterval,
            repeats: true
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                await self?.syncNow()
            }
        }
        logger.debug("Periodic sync timer started (interval: \(Self.periodicSyncInterval)s).")
    }

    /// Persists the unsynced count to UserDefaults so it survives app restarts.
    private func persistUnsyncedCount() {
        UserDefaults.standard.set(unsyncedCount, forKey: Self.unsyncedCountKey)
    }
}
