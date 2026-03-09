import SwiftUI
import UserNotifications

// MARK: - CameraPosition

/// The preferred camera for workout pose detection.
enum CameraPosition: String, CaseIterable, Identifiable {
    case front = "front"
    case back  = "back"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .front: return "Front Camera"
        case .back:  return "Back Camera"
        }
    }

    var icon: AppIcon {
        switch self {
        case .front: return .cameraRotate
        case .back:  return .camera
        }
    }
}

// MARK: - AppearanceMode

/// The user's preferred color scheme.
enum AppearanceMode: String, CaseIterable, Identifiable {
    case system = "system"
    case light  = "light"
    case dark   = "dark"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .system: return "System"
        case .light:  return "Light"
        case .dark:   return "Dark"
        }
    }

    var icon: AppIcon {
        switch self {
        case .system: return .circleHalfFilled
        case .light:  return .sunMax
        case .dark:   return .moonFill
        }
    }

    /// The SwiftUI `ColorScheme` to apply, or `nil` for system default.
    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light:  return .light
        case .dark:   return .dark
        }
    }
}

// MARK: - SettingsKeys

/// Centralised `UserDefaults` key strings.
enum SettingsKeys {
    static let pushUpsPerMinute      = "settings.pushUpsPerMinute"
    static let qualityMultiplier     = "settings.qualityMultiplier"
    static let dailyCreditLimitMins  = "settings.dailyCreditLimitMins"
    static let cameraPosition        = "settings.cameraPosition"
    static let poseOverlay           = "settings.poseOverlay"
    static let notificationsEnabled  = "settings.notificationsEnabled"
    static let notificationHour      = "settings.notificationHour"
    static let notificationMinute    = "settings.notificationMinute"
    static let hapticFeedback        = "settings.hapticFeedback"
    static let soundEffects          = "settings.soundEffects"
    static let appearanceMode        = "settings.appearanceMode"
}

// MARK: - SettingsViewModel

/// Manages all persistent user preferences for the Settings screen.
///
/// Every property is backed by `UserDefaults` and published via `@Published`
/// so the SwiftUI view re-renders on every change. Values are persisted
/// immediately in each `didSet` observer.
///
/// **Defaults**
/// | Setting                  | Default        |
/// |--------------------------|----------------|
/// | Push-ups per minute      | 10             |
/// | Quality multiplier       | on             |
/// | Daily credit limit       | nil (disabled) |
/// | Camera position          | back           |
/// | Pose overlay             | on             |
/// | Notifications            | off            |
/// | Notification time        | 08:00          |
/// | Haptic feedback          | on             |
/// | Sound effects            | on             |
/// | Appearance               | system         |
@MainActor
final class SettingsViewModel: ObservableObject {

    // MARK: - Workout / Credit Settings

    /// Push-ups per minute used to calculate time credit. Range: 1–50.
    @Published var pushUpsPerMinute: Int {
        didSet { UserDefaults.standard.set(pushUpsPerMinute, forKey: SettingsKeys.pushUpsPerMinute) }
    }

    /// When enabled, the quality multiplier (form score) scales the earned credit.
    @Published var qualityMultiplierEnabled: Bool {
        didSet { UserDefaults.standard.set(qualityMultiplierEnabled, forKey: SettingsKeys.qualityMultiplier) }
    }

    /// Optional daily credit cap in minutes. `nil` means no limit.
    /// Stored as 0 to represent "disabled" in `UserDefaults`.
    @Published private var _dailyCreditLimitMins: Int {
        didSet { UserDefaults.standard.set(_dailyCreditLimitMins, forKey: SettingsKeys.dailyCreditLimitMins) }
    }

    /// The daily credit limit in minutes, or `nil` when disabled.
    var dailyCreditLimit: Int? {
        get { _dailyCreditLimitMins > 0 ? _dailyCreditLimitMins : nil }
        set {
            _dailyCreditLimitMins = newValue ?? 0
        }
    }

    /// Whether the daily credit limit is active.
    var dailyCreditLimitEnabled: Bool {
        get { _dailyCreditLimitMins > 0 }
        set {
            if newValue {
                // Enable with a sensible default if currently disabled.
                if _dailyCreditLimitMins <= 0 { _dailyCreditLimitMins = 60 }
            } else {
                _dailyCreditLimitMins = 0
            }
        }
    }

    // MARK: - Camera Settings

    /// The preferred camera for pose detection.
    @Published private var _cameraPositionRaw: String {
        didSet { UserDefaults.standard.set(_cameraPositionRaw, forKey: SettingsKeys.cameraPosition) }
    }

    var cameraPosition: CameraPosition {
        get { CameraPosition(rawValue: _cameraPositionRaw) ?? .back }
        set {
            _cameraPositionRaw = newValue.rawValue
        }
    }

    /// Whether the skeleton / pose overlay is shown during workouts.
    @Published var poseOverlayEnabled: Bool {
        didSet { UserDefaults.standard.set(poseOverlayEnabled, forKey: SettingsKeys.poseOverlay) }
    }

    // MARK: - Notification Settings

    /// Whether daily reminder notifications are enabled.
    @Published var notificationsEnabled: Bool {
        didSet { UserDefaults.standard.set(notificationsEnabled, forKey: SettingsKeys.notificationsEnabled) }
    }

    /// Hour component of the daily reminder time (0–23).
    @Published var notificationHour: Int {
        didSet { UserDefaults.standard.set(notificationHour, forKey: SettingsKeys.notificationHour) }
    }

    /// Minute component of the daily reminder time (0–59).
    @Published var notificationMinute: Int {
        didSet { UserDefaults.standard.set(notificationMinute, forKey: SettingsKeys.notificationMinute) }
    }

    // MARK: - Feedback Settings

    /// Whether haptic feedback is triggered on rep detection and UI events.
    @Published var hapticFeedbackEnabled: Bool {
        didSet { UserDefaults.standard.set(hapticFeedbackEnabled, forKey: SettingsKeys.hapticFeedback) }
    }

    /// Whether sound effects play during workouts.
    @Published var soundEffectsEnabled: Bool {
        didSet { UserDefaults.standard.set(soundEffectsEnabled, forKey: SettingsKeys.soundEffects) }
    }

    // MARK: - Appearance

    @Published private var _appearanceModeRaw: String {
        didSet { UserDefaults.standard.set(_appearanceModeRaw, forKey: SettingsKeys.appearanceMode) }
    }

    /// The user's preferred color scheme.
    var appearanceMode: AppearanceMode {
        get { AppearanceMode(rawValue: _appearanceModeRaw) ?? .system }
        set {
            _appearanceModeRaw = newValue.rawValue
        }
    }

    // MARK: - Notification Authorization State

    /// Whether the system has granted notification permission.
    @Published private(set) var notificationAuthorizationStatus: UNAuthorizationStatus = .notDetermined

    /// Whether a notification permission request is in flight.
    @Published private(set) var isRequestingNotificationPermission: Bool = false

    /// Non-nil when an operation produced an error.
    @Published var errorMessage: String? = nil

    // MARK: - Derived

    /// Human-readable label for the current notification time.
    var notificationTimeLabel: String {
        let h = notificationHour
        let m = notificationMinute
        let period = h < 12 ? "AM" : "PM"
        let displayHour = h == 0 ? 12 : (h > 12 ? h - 12 : h)
        return String(format: "%d:%02d %@", displayHour, m, period)
    }

    /// A `Date` representing today at the configured notification time.
    /// Used to drive the `DatePicker`.
    var notificationTime: Date {
        get {
            var components = Calendar.current.dateComponents([.year, .month, .day], from: Date())
            components.hour   = notificationHour
            components.minute = notificationMinute
            return Calendar.current.date(from: components) ?? Date()
        }
        set {
            let components = Calendar.current.dateComponents([.hour, .minute], from: newValue)
            notificationHour   = components.hour   ?? 8
            notificationMinute = components.minute ?? 0
        }
    }

    /// The stepper range for push-ups per minute.
    static let pushUpsPerMinuteRange = 1...50

    /// Available daily credit limit options in minutes.
    static let dailyCreditLimitOptions: [Int] = [30, 45, 60, 90, 120, 180, 240]

    // MARK: - Init

    init() {
        let defaults = UserDefaults.standard

        // Load persisted values, falling back to sensible defaults.
        pushUpsPerMinute     = defaults.object(forKey: SettingsKeys.pushUpsPerMinute) != nil
            ? defaults.integer(forKey: SettingsKeys.pushUpsPerMinute)
            : 10
        qualityMultiplierEnabled = defaults.object(forKey: SettingsKeys.qualityMultiplier) != nil
            ? defaults.bool(forKey: SettingsKeys.qualityMultiplier)
            : true
        _dailyCreditLimitMins = defaults.integer(forKey: SettingsKeys.dailyCreditLimitMins)
        _cameraPositionRaw   = defaults.string(forKey: SettingsKeys.cameraPosition)
            ?? CameraPosition.back.rawValue
        poseOverlayEnabled   = defaults.object(forKey: SettingsKeys.poseOverlay) != nil
            ? defaults.bool(forKey: SettingsKeys.poseOverlay)
            : true
        notificationsEnabled = defaults.bool(forKey: SettingsKeys.notificationsEnabled)
        notificationHour     = defaults.object(forKey: SettingsKeys.notificationHour) != nil
            ? defaults.integer(forKey: SettingsKeys.notificationHour)
            : 8
        notificationMinute   = defaults.integer(forKey: SettingsKeys.notificationMinute)
        hapticFeedbackEnabled = defaults.object(forKey: SettingsKeys.hapticFeedback) != nil
            ? defaults.bool(forKey: SettingsKeys.hapticFeedback)
            : true
        soundEffectsEnabled  = defaults.object(forKey: SettingsKeys.soundEffects) != nil
            ? defaults.bool(forKey: SettingsKeys.soundEffects)
            : true
        _appearanceModeRaw   = defaults.string(forKey: SettingsKeys.appearanceMode)
            ?? AppearanceMode.system.rawValue
    }

    // MARK: - Actions

    /// Checks the current notification authorization status from the system.
    func refreshNotificationStatus() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        notificationAuthorizationStatus = settings.authorizationStatus
    }

    /// Requests notification authorization if not yet determined.
    /// Toggles `notificationsEnabled` based on the result.
    func requestNotificationPermission() async {
        guard notificationAuthorizationStatus == .notDetermined else {
            // Already determined -- if denied, open Settings app.
            if notificationAuthorizationStatus == .denied {
                openSystemSettings()
            }
            return
        }

        isRequestingNotificationPermission = true
        defer { isRequestingNotificationPermission = false }

        do {
            let granted = try await UNUserNotificationCenter.current()
                .requestAuthorization(options: [.alert, .badge, .sound])
            notificationsEnabled = granted
            await refreshNotificationStatus()
        } catch {
            errorMessage = "Could not request notification permission: \(error.localizedDescription)"
            notificationsEnabled = false
        }
    }

    /// Handles the notifications toggle being flipped by the user.
    func handleNotificationsToggle(_ enabled: Bool) async {
        if enabled {
            await requestNotificationPermission()
        } else {
            notificationsEnabled = false
        }
    }

    /// Increments push-ups per minute by 1, clamped to the valid range.
    func incrementPushUpsPerMinute() {
        pushUpsPerMinute = min(
            Self.pushUpsPerMinuteRange.upperBound,
            pushUpsPerMinute + 1
        )
    }

    /// Decrements push-ups per minute by 1, clamped to the valid range.
    func decrementPushUpsPerMinute() {
        pushUpsPerMinute = max(
            Self.pushUpsPerMinuteRange.lowerBound,
            pushUpsPerMinute - 1
        )
    }

    /// Clears the current error message.
    func clearError() {
        errorMessage = nil
    }

    // MARK: - Private Helpers

    /// Opens the iOS Settings app to the app's notification settings page.
    private func openSystemSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }
}

// MARK: - App Info

/// Static app metadata shown in the Info section.
enum AppInfo {
    /// The marketing version string from the bundle (e.g. "1.0.0").
    static var version: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }

    /// The build number from the bundle (e.g. "42").
    static var build: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
    }

    /// The full version + build string for display.
    static var versionString: String {
        "Version \(version) (\(build))"
    }

    /// Privacy policy URL.
    static let privacyPolicyURL = URL(string: "https://pushup.app/privacy")!

    /// Terms of service URL.
    static let termsOfServiceURL = URL(string: "https://pushup.app/terms")!

    /// Support / contact URL.
    static let supportURL = URL(string: "https://pushup.app/support")!
}
