import SwiftUI
import FamilyControls
import ManagedSettings
import DeviceActivity

// MARK: - ScreenTimeAuthorizationStatus

/// The current authorization state for Screen Time / Family Controls.
enum ScreenTimeAuthorizationStatus: Equatable {
    case notDetermined
    case authorized
    case denied
    case unavailable  // iOS < 16 or non-iPhone device
}

// MARK: - ScreenTimeManager

/// Central service for all Screen Time functionality.
///
/// Responsibilities:
/// - Requesting FamilyControls authorization from the user
/// - Persisting the user's app/category selection (FamilyActivitySelection)
/// - Blocking selected apps via ManagedSettings when credit runs out
/// - Unblocking apps after a successful workout
/// - Starting/stopping DeviceActivity monitoring for usage tracking
///
/// **Reinstall-proof design:**
/// The DeviceActivity threshold is always computed as:
///   `cumulativeLimitSeconds = todaySystemUsageSeconds + availableSeconds`
///
/// `todaySystemUsageSeconds` is the OS-tracked cumulative usage since midnight
/// for the selected apps. This value is stored in the shared App Group container
/// by the DeviceActivityMonitorExtension whenever a threshold fires, and is
/// refreshed on every `startMonitoring` call. Because the OS tracks usage
/// independently of our app, reinstalling the app does NOT reset this value --
/// the system still knows how much time was spent today.
///
/// **Architecture note:** This is a singleton `@MainActor` ObservableObject.
/// It is injected into the SwiftUI environment at the root level so every
/// screen can observe authorization state and blocking state without prop-drilling.
///
/// **App Group:** All data shared with the DeviceActivity Extension is stored
/// in the shared App Group container: `group.com.flomks.pushup`
@MainActor
final class ScreenTimeManager: ObservableObject {

    // MARK: - Singleton

    static let shared = ScreenTimeManager()

    // MARK: - Published State

    /// Current FamilyControls authorization status.
    @Published private(set) var authorizationStatus: ScreenTimeAuthorizationStatus = .notDetermined

    /// Whether apps are currently blocked (shield active).
    @Published private(set) var isBlocking: Bool = false

    /// Whether a permission request is in flight.
    @Published private(set) var isRequestingAuthorization: Bool = false

    /// The user's saved app/category selection. Nil if no selection has been made.
    @Published private(set) var activitySelection: FamilyActivitySelection?

    /// Non-nil when an operation produced an error.
    @Published var errorMessage: String? = nil

    // MARK: - Private

    private let store = ManagedSettingsStore()
    private let activityCenter = DeviceActivityCenter()

    /// App Group UserDefaults shared with the DeviceActivity Extension.
    private let sharedDefaults = UserDefaults(suiteName: ScreenTimeConstants.appGroupID)

    private init() {
        loadPersistedState()
        refreshAuthorizationStatus()
    }

    // MARK: - Authorization

    /// Requests FamilyControls authorization from the user.
    ///
    /// Shows the system permission dialog. The result is reflected in
    /// `authorizationStatus`. Safe to call multiple times -- if already
    /// authorized, this is a no-op.
    func requestAuthorization() async {
        guard authorizationStatus != .authorized else { return }

        isRequestingAuthorization = true
        defer { isRequestingAuthorization = false }

        do {
            // .individual = single-user mode (no Family Sharing required).
            // This is the correct mode for a self-control app.
            try await AuthorizationCenter.shared.requestAuthorization(for: .individual)
            authorizationStatus = .authorized
            sharedDefaults?.set(true, forKey: ScreenTimeConstants.Keys.isAuthorized)

            // After authorization, immediately apply the correct state based on
            // the stored credit balance. This ensures blocking/monitoring starts
            // right away without requiring the user to reopen the app.
            reapplyBlockingState()
        } catch {
            authorizationStatus = .denied
            errorMessage = "Screen Time permission was denied. You can enable it in iOS Settings > Screen Time."
        }
    }

    /// Revokes FamilyControls authorization and clears all restrictions.
    func revokeAuthorization() async {
        // Unblock all apps before revoking
        unblockApps()
        stopMonitoring()

        AuthorizationCenter.shared.revokeAuthorization { [weak self] result in
            Task { @MainActor in
                switch result {
                case .success:
                    self?.authorizationStatus = .notDetermined
                    self?.sharedDefaults?.set(false, forKey: ScreenTimeConstants.Keys.isAuthorized)
                case .failure(let error):
                    self?.errorMessage = "Could not revoke authorization: \(error.localizedDescription)"
                }
            }
        }
    }

    /// Refreshes the authorization status from the system.
    func refreshAuthorizationStatus() {
        // AuthorizationCenter.shared.authorizationStatus is available iOS 16+
        // We check the persisted flag as a fast path.
        let wasAuthorized = sharedDefaults?.bool(forKey: ScreenTimeConstants.Keys.isAuthorized) ?? false
        if wasAuthorized {
            authorizationStatus = .authorized
        }
        // The actual system status is reflected via the requestAuthorization result.
        // There is no synchronous API to query it without triggering a dialog.
    }

    // MARK: - App Selection

    /// Saves the user's FamilyActivitySelection to the App Group container.
    ///
    /// The selection is encoded as JSON and stored in the shared UserDefaults
    /// so the DeviceActivity Extension can read it without IPC.
    func saveSelection(_ selection: FamilyActivitySelection) {
        activitySelection = selection

        guard let data = try? JSONEncoder().encode(selection) else {
            errorMessage = "Could not save app selection."
            return
        }
        sharedDefaults?.set(data, forKey: ScreenTimeConstants.Keys.activitySelection)

        // Re-apply shield immediately if already blocking (e.g. selection changed
        // while credit was already exhausted).
        if isBlocking {
            applyShield(selection: selection)
            return
        }

        // Check current credit balance. If credit is zero, block immediately
        // without waiting for DashboardViewModel to emit a credit update.
        // This ensures apps are blocked the moment the user saves a selection
        // when they have no credit -- no second app-open required.
        let storedCredit = sharedDefaults?.integer(forKey: ScreenTimeConstants.Keys.availableSeconds) ?? 0
        if storedCredit <= 0 {
            applyShield(selection: selection)
            isBlocking = true
            sharedDefaults?.set(true, forKey: ScreenTimeConstants.Keys.isBlocking)
            // Start monitoring with threshold=1 so the extension records usage.
            stopMonitoring()
            startMonitoring(availableSeconds: 1)
        } else {
            // Credit available -- just (re)start monitoring with the new selection.
            stopMonitoring()
            startMonitoring(availableSeconds: storedCredit)
        }
    }

    /// Clears the saved app selection and removes all restrictions.
    func clearSelection() {
        activitySelection = nil
        sharedDefaults?.removeObject(forKey: ScreenTimeConstants.Keys.activitySelection)
        unblockApps()
    }

    // MARK: - Blocking

    /// Activates the app shield for the saved selection.
    ///
    /// Call this when the user's time credit reaches zero.
    /// Does nothing if no selection has been saved or authorization is missing.
    func blockApps() {
        guard authorizationStatus == .authorized,
              let selection = activitySelection else { return }

        applyShield(selection: selection)
        isBlocking = true
        sharedDefaults?.set(true, forKey: ScreenTimeConstants.Keys.isBlocking)
    }

    /// Removes the app shield, restoring access to all apps.
    ///
    /// Call this after a successful workout that earns new time credit.
    func unblockApps() {
        store.shield.applications = nil
        store.shield.applicationCategories = nil
        store.shield.webDomains = nil
        isBlocking = false
        sharedDefaults?.set(false, forKey: ScreenTimeConstants.Keys.isBlocking)
    }

    // MARK: - DeviceActivity Monitoring

    /// Starts monitoring app usage for the current selection.
    ///
    /// Sets up a daily schedule that fires callbacks in the
    /// DeviceActivity Extension when thresholds are reached.
    ///
    /// **Reinstall-proof threshold calculation:**
    /// The DeviceActivityEvent threshold is cumulative usage since midnight.
    /// We read `screentime.todaySystemUsageSeconds` from the App Group container,
    /// which is written by the DeviceActivityMonitorExtension on every threshold
    /// event. This value reflects actual OS-tracked usage and is NOT reset by
    /// reinstalling the app (the OS tracks it independently).
    ///
    /// If no system usage value is stored yet (first run of the day), we fall
    /// back to the legacy `startOfDaySeconds` snapshot approach, which is safe
    /// for the first run but vulnerable to reinstall. The system usage value
    /// will be populated on the first threshold event.
    ///
    /// - Parameter availableSeconds: The current time credit in seconds.
    ///   Used to set the blocking threshold.
    func startMonitoring(availableSeconds: Int) {
        guard authorizationStatus == .authorized,
              let selection = activitySelection,
              !selection.applicationTokens.isEmpty || !selection.categoryTokens.isEmpty
        else { return }

        // Store available seconds so the Extension can read it.
        sharedDefaults?.set(availableSeconds, forKey: ScreenTimeConstants.Keys.availableSeconds)

        // MARK: Reinstall-proof cumulative threshold calculation
        //
        // The DeviceActivityEvent.threshold measures CUMULATIVE usage since
        // midnight, not remaining time. To block after `availableSeconds` more
        // usage, we must add the usage already accumulated today.
        //
        // Priority order for "already used today":
        //   1. todaySystemUsageSeconds -- written by the extension from the OS
        //      DeviceActivity report. Survives reinstall because the OS tracks
        //      usage independently of our UserDefaults.
        //   2. startOfDaySeconds snapshot -- legacy fallback. Vulnerable to
        //      reinstall but used when no system usage value is available yet.
        //
        // Example (reinstall scenario):
        //   User used 60 min today, reinstalls app, earns 30 min workout.
        //   DB credit = 30 min (earned), todaySystemUsageSeconds = 3600 (60 min).
        //   cumulativeLimitSeconds = 3600 + 1800 = 5400 (90 min total).
        //   System fires when cumulative usage hits 90 min, i.e. 30 more min.
        //   Correct! The reinstall did not help the user bypass the limit.

        let todaySystemUsage = sharedDefaults?.integer(forKey: ScreenTimeConstants.Keys.todaySystemUsageSeconds) ?? 0

        let alreadyUsedToday: Int
        if todaySystemUsage > 0 {
            // Use the authoritative OS-tracked value.
            alreadyUsedToday = todaySystemUsage
        } else {
            // Fallback: use the start-of-day snapshot.
            // Only set once per calendar day to avoid overwriting mid-day.
            let calendar = Calendar.current
            let lastSnapshotDate = sharedDefaults?.object(forKey: ScreenTimeConstants.Keys.startOfDayDate) as? Date
            if lastSnapshotDate == nil || !calendar.isDateInToday(lastSnapshotDate!) {
                sharedDefaults?.set(availableSeconds, forKey: ScreenTimeConstants.Keys.startOfDaySeconds)
                sharedDefaults?.set(Date(), forKey: ScreenTimeConstants.Keys.startOfDayDate)
            }
            let startOfDaySeconds = sharedDefaults?.integer(forKey: ScreenTimeConstants.Keys.startOfDaySeconds) ?? availableSeconds
            alreadyUsedToday = max(0, startOfDaySeconds - availableSeconds)
        }

        let cumulativeLimitSeconds = alreadyUsedToday + availableSeconds

        // Warning threshold: 5 minutes before the limit (minimum 1 minute).
        let cumulativeWarningSeconds = max(60, cumulativeLimitSeconds - 300)

        let schedule = DeviceActivitySchedule(
            intervalStart: DateComponents(hour: 0, minute: 0),
            intervalEnd: DateComponents(hour: 23, minute: 59),
            repeats: true
        )

        do {
            try activityCenter.startMonitoring(
                ScreenTimeConstants.activityName,
                during: schedule,
                events: [
                    ScreenTimeConstants.Events.warning: DeviceActivityEvent(
                        applications: selection.applicationTokens,
                        categories: selection.categoryTokens,
                        webDomains: selection.webDomainTokens,
                        threshold: makeComponents(seconds: cumulativeWarningSeconds)
                    ),
                    ScreenTimeConstants.Events.limitReached: DeviceActivityEvent(
                        applications: selection.applicationTokens,
                        categories: selection.categoryTokens,
                        webDomains: selection.webDomainTokens,
                        threshold: makeComponents(seconds: cumulativeLimitSeconds)
                    )
                ]
            )
        } catch {
            // startMonitoring throws if the activity is already registered.
            // Callers must call stopMonitoring() first to update the threshold.
        }
    }

    /// Stops all DeviceActivity monitoring.
    func stopMonitoring() {
        activityCenter.stopMonitoring([ScreenTimeConstants.activityName])
    }

    // MARK: - Private Helpers

    private func applyShield(selection: FamilyActivitySelection) {
        store.shield.applications = selection.applicationTokens.isEmpty
            ? nil
            : selection.applicationTokens
        store.shield.applicationCategories = selection.categoryTokens.isEmpty
            ? nil
            : ShieldSettings.ActivityCategoryPolicy.specific(selection.categoryTokens)
        store.shield.webDomains = selection.webDomainTokens.isEmpty
            ? nil
            : selection.webDomainTokens
    }

    private func loadPersistedState() {
        // Restore saved selection first so it is available when we re-apply the shield.
        if let data = sharedDefaults?.data(forKey: ScreenTimeConstants.Keys.activitySelection),
           let selection = try? JSONDecoder().decode(FamilyActivitySelection.self, from: data) {
            activitySelection = selection
        }

        // Restore blocking state. If the app was killed while blocking was active,
        // the ManagedSettingsStore shield is reset by the system. Re-apply it now
        // so the shield is immediately active again after relaunch.
        let wasBlocking = sharedDefaults?.bool(forKey: ScreenTimeConstants.Keys.isBlocking) ?? false
        if wasBlocking, let selection = activitySelection {
            applyShield(selection: selection)
            isBlocking = true
        } else {
            isBlocking = false
        }

        // Note: reapplyBlockingState() is NOT called here because
        // loadPersistedState() runs in init() before the KMP database is ready.
        // The shield is re-applied above from the persisted isBlocking flag.
        // Full re-arming (including DeviceActivity monitoring) happens via:
        //   - AppDelegate.rearmScreenTimeMonitoring() on cold launch
        //   - MainTabView.onAppear → reapplyBlockingState() after login
        //   - DashboardViewModel credit observer once the DB emits
    }

    /// Applies the correct blocking/monitoring state based on the stored
    /// credit balance in the App Group container.
    ///
    /// Reads `screentime.availableSeconds` and either:
    ///   - Blocks apps + starts monitoring (credit = 0)
    ///   - Unblocks apps + starts monitoring with threshold (credit > 0)
    ///
    /// Called from:
    /// - `requestAuthorization()` after the user grants permission
    /// - `MainTabView.onAppear` to immediately re-arm after login (before
    ///   the DashboardViewModel credit observer has a chance to fire)
    /// - `AppDelegate.rearmScreenTimeMonitoring()` on cold launch
    ///
    /// Safe to call multiple times — no-ops when unauthorized or no selection.
    func reapplyBlockingState() {
        guard let selection = activitySelection,
              !selection.applicationTokens.isEmpty || !selection.categoryTokens.isEmpty
        else { return }

        let storedCredit = sharedDefaults?.integer(forKey: ScreenTimeConstants.Keys.availableSeconds) ?? 0

        stopMonitoring()

        if storedCredit <= 0 {
            // No credit -- block immediately and monitor with threshold=1
            // so the extension records usage data.
            if !isBlocking {
                applyShield(selection: selection)
                isBlocking = true
                sharedDefaults?.set(true, forKey: ScreenTimeConstants.Keys.isBlocking)
            }
            startMonitoring(availableSeconds: 1)
        } else {
            // Credit available -- ensure unblocked and start monitoring.
            if isBlocking {
                store.shield.applications = nil
                store.shield.applicationCategories = nil
                store.shield.webDomains = nil
                isBlocking = false
                sharedDefaults?.set(false, forKey: ScreenTimeConstants.Keys.isBlocking)
            }
            startMonitoring(availableSeconds: storedCredit)
        }
    }

    private func makeComponents(seconds: Int) -> DateComponents {
        let hours = seconds / 3600
        let minutes = (seconds % 3600) / 60
        let secs = seconds % 60
        return DateComponents(hour: hours, minute: minutes, second: secs)
    }

    // MARK: - Error Handling

    func clearError() {
        errorMessage = nil
    }
}

// MARK: - ScreenTimeConstants

/// Shared constants used by the main app and all Screen Time extensions.
///
/// These values must match exactly between the main target and the
/// DeviceActivity / Shield extensions.
enum ScreenTimeConstants {

    /// The App Group identifier. Must match the entitlement in all targets.
    static let appGroupID = "group.com.flomks.pushup"

    /// The DeviceActivity name used to identify our monitoring session.
    static let activityName = DeviceActivityName("com.flomks.pushup.daily")

    // MARK: - Event Names

    enum Events {
        /// Fired when 80% of the credit has been consumed (warning).
        static let warning = DeviceActivityEvent.Name("com.flomks.pushup.warning")
        /// Fired when 100% of the credit has been consumed (block).
        static let limitReached = DeviceActivityEvent.Name("com.flomks.pushup.limitReached")
    }

    // MARK: - UserDefaults Keys (shared via App Group)

    enum Keys {
        static let isAuthorized            = "screentime.isAuthorized"
        static let activitySelection       = "screentime.activitySelection"
        static let isBlocking              = "screentime.isBlocking"
        static let availableSeconds        = "screentime.availableSeconds"
        static let startOfDaySeconds       = "screentime.startOfDaySeconds"
        static let startOfDayDate          = "screentime.startOfDayDate"
        static let usageData               = "screentime.usageData"

        /// Cumulative usage seconds for the selected apps today, as reported
        /// by the OS DeviceActivity system. Written by the extension on every
        /// threshold event. Survives app reinstall because the OS tracks usage
        /// independently of our UserDefaults.
        static let todaySystemUsageSeconds = "screentime.todaySystemUsageSeconds"

        /// ISO date string "yyyy-MM-dd" for the day when todaySystemUsageSeconds
        /// was last written. Used to reset the value at midnight.
        static let todaySystemUsageDate    = "screentime.todaySystemUsageDate"

        /// Per-app usage data for today. JSON array of PerAppUsageRecord.
        static let perAppUsageData         = "screentime.perAppUsageData"
    }
}
