import Shared
import SwiftUI
import PhotosUI

// MARK: - AvatarVisibilityOption

/// Swift-side mirror of the KMP AvatarVisibility enum.
/// Controls who can see a user's avatar.
enum AvatarVisibilityOption: String, CaseIterable, Identifiable {
    case everyone     = "everyone"
    case friendsOnly  = "friends_only"
    case nobody       = "nobody"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .everyone:    return "Everyone"
        case .friendsOnly: return "Friends only"
        case .nobody:      return "Nobody (show initials)"
        }
    }

    var icon: String {
        switch self {
        case .everyone:    return "globe"
        case .friendsOnly: return "person.2.fill"
        case .nobody:      return "eye.slash"
        }
    }
}

// MARK: - ProfileError

/// Typed errors surfaced by the profile flow.
enum ProfileError: LocalizedError {
    case displayNameEmpty
    case displayNameTooLong
    case avatarUploadFailed(String)
    case avatarTooLarge
    case saveFailed(String)
    case deleteFailed(String)
    case loadFailed(String)

    var errorDescription: String? {
        switch self {
        case .displayNameEmpty:
            return "Display name cannot be empty."
        case .displayNameTooLong:
            return "Display name must be \(ProfileValidation.maxDisplayNameLength) characters or fewer."
        case .avatarUploadFailed(let msg):
            return "Avatar upload failed: \(msg)"
        case .avatarTooLarge:
            return "Image is too large. Please choose a smaller photo."
        case .saveFailed(let msg):
            return "Could not save changes: \(msg)"
        case .deleteFailed(let msg):
            return "Could not delete account: \(msg)"
        case .loadFailed(let msg):
            return "Could not load profile: \(msg)"
        }
    }
}

// MARK: - ProfileStats

/// Lifetime account statistics shown on the profile screen.
struct ProfileStats: Equatable {
    let totalPushUps: Int
    let totalWorkouts: Int
    let totalEarnedMinutes: Int
}

// MARK: - LevelInfo

/// Account-wide XP / level state shown in the level card on the profile screen.
struct LevelInfo: Equatable {
    /// Current level (1-based).
    let level: Int
    /// Total XP accumulated across all time.
    let totalXp: Int64
    /// XP accumulated within the current level.
    let xpIntoLevel: Int64
    /// XP needed to advance to the next level.
    let xpRequiredForNextLevel: Int64
    /// Progress fraction within the current level, in [0.0, 1.0).
    let levelProgress: Double
}

// MARK: - ExerciseLevelInfo

/// Per-exercise XP / level state for one exercise type.
struct ExerciseLevelInfo: Equatable, Identifiable {
    /// Stable identifier matching `WorkoutType.rawValue` (e.g. "pushUps").
    let exerciseTypeId: String
    let level: Int
    let totalXp: Int64
    let xpIntoLevel: Int64
    let xpRequiredForNextLevel: Int64
    let levelProgress: Double

    var id: String { exerciseTypeId }

    /// Resolves the matching `WorkoutType` for display metadata (icon, color, name).
    var workoutType: WorkoutType? {
        WorkoutType(rawValue: exerciseTypeId)
    }
}

// MARK: - Validation Constants

private enum ProfileValidation {
    /// Maximum allowed display name length.
    static let maxDisplayNameLength = 50

    /// Maximum avatar image dimension (pixels) before resizing.
    static let maxAvatarDimension: CGFloat = 512

    /// Maximum avatar file size in bytes (2 MB).
    static let maxAvatarBytes = 2 * 1_024 * 1_024

    /// JPEG compression quality for avatar uploads.
    static let avatarCompressionQuality: CGFloat = 0.8
}

// MARK: - ProfileViewModel

/// Manages all state and actions for the Profile screen.
///
/// Data is currently simulated with realistic stub values so the UI can be
/// built and previewed without a live backend. Replace the stub implementations
/// with real Supabase / KMP use-case calls once the backend is wired up.
///
/// **Responsibilities**
/// - Load and expose user profile data (display name, email, avatar, join date)
/// - Handle avatar selection from camera or photo library
/// - Upload avatar image to Supabase Storage (stubbed)
/// - Allow editing of display name with validation
/// - Expose account statistics (total push-ups, workouts, earned time)
/// - Handle logout and account deletion with confirmation
@MainActor
final class ProfileViewModel: ObservableObject {

    // MARK: - Published State

    /// The user's current display name (editable).
    @Published var displayName: String = ""

    /// The user's current username (editable, unique).
    @Published var usernameInput: String = ""

    /// Whether the username entered is available (nil = not yet checked or unchanged).
    @Published private(set) var isUsernameAvailable: Bool? = nil

    /// Whether an availability check is in progress.
    @Published private(set) var isCheckingUsername: Bool = false

    /// Non-nil when the availability check failed due to a network error.
    @Published private(set) var usernameCheckError: String? = nil

    /// Whether a username save is in progress.
    @Published private(set) var isSavingUsername: Bool = false

    /// The user's email address (read-only).
    @Published private(set) var email: String = ""

    /// The date the user registered (formatted for display).
    @Published private(set) var memberSinceText: String = ""

    /// A locally held UIImage (just picked from camera/library, before upload).
    /// Takes priority over `avatarURL` in the UI.
    @Published private(set) var avatarImage: UIImage? = nil

    /// The effective avatar URL synced from the server (custom > OAuth).
    /// Used to load the avatar via AsyncImage when no local image is held.
    @Published private(set) var avatarURL: String? = nil

    /// Who can see this user's avatar.
    @Published var avatarVisibility: AvatarVisibilityOption = .everyone

    /// Whether an avatar visibility save is in progress.
    @Published private(set) var isSavingAvatarVisibility: Bool = false

    /// Lifetime account statistics.
    @Published private(set) var stats: ProfileStats? = nil

    /// Current account-wide XP / level state. `nil` while loading or when not authenticated.
    @Published private(set) var levelInfo: LevelInfo? = nil

    /// Per-exercise level data. `nil` while loading; empty array if no data available.
    @Published private(set) var exerciseLevels: [ExerciseLevelInfo]? = nil

    /// Whether the initial data load is in progress.
    @Published private(set) var isLoading: Bool = false

    /// Whether an avatar upload is in progress.
    @Published private(set) var isUploadingAvatar: Bool = false

    /// Whether a display name save is in progress.
    @Published private(set) var isSavingName: Bool = false

    /// Whether account deletion is in progress.
    @Published private(set) var isDeletingAccount: Bool = false

    /// Non-nil when an operation failed. Cleared by the view on alert dismiss.
    @Published var errorMessage: String? = nil

    /// Non-nil when an operation succeeded. Cleared automatically after a delay.
    @Published var successMessage: String? = nil

    /// Controls the delete-account confirmation alert.
    @Published var showDeleteConfirmation: Bool = false

    /// Controls the avatar source action sheet.
    @Published var showAvatarSourcePicker: Bool = false

    /// Controls the camera sheet.
    @Published var showCamera: Bool = false

    /// Controls the photo library picker sheet.
    @Published var showPhotoPicker: Bool = false

    /// The selected `PhotosPickerItem` from the system photo picker.
    @Published var selectedPhotoItem: PhotosPickerItem? = nil {
        didSet {
            guard let item = selectedPhotoItem else { return }
            Task { await loadSelectedPhoto(item) }
        }
    }

    // MARK: - Derived

    /// The user's initials derived from `displayName`, used as avatar fallback.
    var initials: String {
        let parts = displayName
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .components(separatedBy: .whitespaces)
            .filter { !$0.isEmpty }
        switch parts.count {
        case 0:
            return "?"
        case 1:
            return String(parts[0].prefix(2)).uppercased()
        default:
            let first = parts[0].prefix(1)
            let last = parts[parts.count - 1].prefix(1)
            return "\(first)\(last)".uppercased()
        }
    }

    /// Returns `true` when the display name field has a non-empty value
    /// that differs from the currently saved name.
    var hasUnsavedNameChange: Bool {
        let trimmed = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmed.isEmpty && trimmed != savedDisplayName
    }

    /// Inline validation error for the display name field.
    var displayNameError: String? {
        let trimmed = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty && !displayName.isEmpty {
            return ProfileError.displayNameEmpty.errorDescription
        }
        if trimmed.count > ProfileValidation.maxDisplayNameLength {
            return ProfileError.displayNameTooLong.errorDescription
        }
        return nil
    }

    /// Whether the display name passes all validation rules.
    var isDisplayNameValid: Bool {
        let trimmed = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmed.isEmpty
            && trimmed.count <= ProfileValidation.maxDisplayNameLength
    }

    // MARK: - Username Derived

    /// Local format validation error for the username field (nil = valid or empty).
    var usernameValidationError: String? {
        let trimmed = usernameInput.trimmingCharacters(in: .whitespaces).lowercased()
        guard !trimmed.isEmpty else { return nil }
        if trimmed.count < 3  { return "At least 3 characters" }
        if trimmed.count > 20 { return "At most 20 characters" }
        if trimmed.range(of: #"^[a-z0-9_.]+$"#, options: .regularExpression) == nil {
            return "Letters, digits, underscores, and dots only"
        }
        if trimmed.hasPrefix(".") || trimmed.hasSuffix(".") { return "Cannot start or end with a dot" }
        if trimmed.contains("..") { return "Cannot contain consecutive dots" }
        return nil
    }

    /// Whether the username input passes all local validation rules.
    var isUsernameLocallyValid: Bool {
        let t = usernameInput.trimmingCharacters(in: .whitespaces).lowercased()
        guard t.count >= 3, t.count <= 20 else { return false }
        guard t.range(of: #"^[a-z0-9_.]+$"#, options: .regularExpression) != nil else { return false }
        guard !t.hasPrefix("."), !t.hasSuffix("."), !t.contains("..") else { return false }
        return true
    }

    /// Whether the username input differs from the currently saved username.
    var hasUnsavedUsernameChange: Bool {
        let trimmed = usernameInput.trimmingCharacters(in: .whitespaces).lowercased()
        return !trimmed.isEmpty && trimmed != savedUsername
    }

    /// Whether the Save button for username should be enabled.
    var canSaveUsername: Bool {
        hasUnsavedUsernameChange
            && isUsernameLocallyValid
            && isUsernameAvailable == true
            && !isSavingUsername
            && !isCheckingUsername
    }

    // MARK: - Private

    /// The last successfully saved display name. Used to detect unsaved changes.
    private var savedDisplayName: String = ""

    /// The last successfully saved username. Used to detect unsaved changes.
    private var savedUsername: String = ""

    /// Debounce task for username availability checks.
    private var usernameCheckTask: Task<Void, Never>? = nil

    /// Cancellable handle for the success-message auto-dismiss task.
    private var successDismissTask: Task<Void, Never>?

    /// KMP Flow observation job for live session updates.
    private var sessionObservationJob: Kotlinx_coroutines_coreJob?

    // MARK: - Init / Deinit

    init() {}

    deinit {
        sessionObservationJob?.cancel(cause: nil)
    }

    // MARK: - Actions

    /// Loads all profile data from the local KMP database. Called on first appear.
    func loadData() async {
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil

        if let user = await AuthService.shared.getCurrentUser() {
            applyUserData(user)
            startObservingStats(userId: user.id)
            await loadLevel(userId: user.id)
            await loadExerciseLevels(userId: user.id)
        } else {
            displayName = ""
            savedDisplayName = ""
            email = ""
            memberSinceText = ""
            stats = ProfileStats(totalPushUps: 0, totalWorkouts: 0, totalEarnedMinutes: 0)
            levelInfo = nil
            exerciseLevels = nil
        }

        isLoading = false
    }

    /// Refreshes the level cards. Can be called after a workout to show updated XP.
    func refreshLevel() async {
        guard let user = await AuthService.shared.getCurrentUser() else { return }
        await loadLevel(userId: user.id)
        await loadExerciseLevels(userId: user.id)
    }

    /// Saves the edited display name to the local database via the KMP layer.
    ///
    /// Writes the new name to the local SQLDelight User record immediately so
    /// it is never lost even if the app is killed before a cloud sync runs.
    /// The next sync cycle will propagate the change to the server.
    func saveDisplayName() async {
        let trimmed = displayName.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmed.isEmpty else {
            errorMessage = ProfileError.displayNameEmpty.errorDescription
            return
        }
        guard trimmed.count <= ProfileValidation.maxDisplayNameLength else {
            errorMessage = ProfileError.displayNameTooLong.errorDescription
            return
        }
        guard trimmed != savedDisplayName else { return }

        isSavingName = true
        errorMessage = nil

        let result = await AuthService.shared.updateDisplayName(trimmed)
        if result.isSuccess {
            savedDisplayName = trimmed
            displayName = trimmed
            showSuccess("Display name updated.")
        } else {
            errorMessage = ProfileError.saveFailed(
                result.errorMessage ?? "Unknown error"
            ).errorDescription
        }

        isSavingName = false
    }

    // MARK: - Username Actions

    /// Called whenever the username input changes. Resets availability and debounces the check.
    func onUsernameInputChanged() {
        isUsernameAvailable = nil
        usernameCheckError = nil
        usernameCheckTask?.cancel()

        let trimmed = usernameInput.trimmingCharacters(in: .whitespaces).lowercased()

        // If the user typed back their current username, no check needed.
        if trimmed == savedUsername {
            isUsernameAvailable = nil
            return
        }

        guard isUsernameLocallyValid else { return }

        usernameCheckTask = Task {
            try? await Task.sleep(nanoseconds: 500_000_000)
            guard !Task.isCancelled else { return }
            await checkUsernameAvailability(trimmed)
        }
    }

    private func checkUsernameAvailability(_ username: String) async {
        isCheckingUsername = true
        let result = await AuthService.shared.checkUsernameAvailability(username)
        isCheckingUsername = false

        let currentTrimmed = usernameInput.trimmingCharacters(in: .whitespaces).lowercased()
        guard currentTrimmed == username else { return }

        if let errorMsg = result.errorMessage {
            isUsernameAvailable = nil
            if !errorMsg.lowercased().contains("cancel") {
                usernameCheckError = errorMsg
            }
        } else {
            isUsernameAvailable = result.available
            usernameCheckError = nil
        }
    }

    /// Saves the new username. Validates locally, checks availability, then persists.
    func saveUsername() async {
        let trimmed = usernameInput.trimmingCharacters(in: .whitespaces).lowercased()
        guard trimmed != savedUsername else { return }
        guard isUsernameLocallyValid else { return }

        isSavingUsername = true
        errorMessage = nil

        let result = await AuthService.shared.setUsername(trimmed)
        isSavingUsername = false

        if result.isSuccess {
            savedUsername = trimmed
            usernameInput = trimmed
            isUsernameAvailable = nil
            showSuccess("Username updated.")
        } else {
            errorMessage = result.errorMessage ?? "Could not save username."
            // Re-check availability in case it was taken between check and submit.
            isUsernameAvailable = nil
        }
    }

    /// Handles a new avatar image selected from camera or photo library.
    /// Resizes, compresses, and uploads the image to Supabase Storage.
    func uploadAvatar(_ image: UIImage) async {
        isUploadingAvatar = true
        errorMessage = nil

        do {
            // Resize to a reasonable dimension before compression.
            let resized = Self.resizeImage(
                image,
                maxDimension: ProfileValidation.maxAvatarDimension
            )

            guard let imageData = resized.jpegData(
                compressionQuality: ProfileValidation.avatarCompressionQuality
            ) else {
                throw ProfileError.avatarUploadFailed("Could not compress image.")
            }

            guard imageData.count <= ProfileValidation.maxAvatarBytes else {
                throw ProfileError.avatarTooLarge
            }

            // TODO: Replace with real Supabase Storage upload when storage bucket is configured:
            //   let userId = (await AuthService.shared.getCurrentUser())?.id ?? "unknown"
            //   let fileName = "\(userId)/avatar.jpg"
            //   try await supabaseClient.storage
            //       .from("avatars")
            //       .upload(fileName, data: imageData, options: .init(contentType: "image/jpeg", upsert: true))
            //   let publicURL = try supabaseClient.storage.from("avatars").getPublicURL(path: fileName)
            //   let uploadedUrl = publicURL.absoluteString
            //
            // For now: store the image locally and persist the URL via SafeAuthBridge.
            // When real upload is wired up, replace the stub URL with the real one.
            _ = imageData
            try await Task.sleep(nanoseconds: 800_000_000)

            // Show the picked image immediately (optimistic UI).
            avatarImage = resized

            // Persist the avatar URL locally via KMP (will sync to server on next sync).
            // Replace "stub_url" with the real Supabase Storage URL once upload is wired.
            let stubUrl = "local://avatar_pending_upload"
            let result = await AuthService.shared.updateAvatar(stubUrl)
            if result.isSuccess {
                avatarURL = stubUrl
                showSuccess("Avatar updated.")
            } else {
                showSuccess("Avatar updated locally.")
            }
        } catch let error as ProfileError {
            errorMessage = error.errorDescription
        } catch is CancellationError {
            // Silently ignore cancellation.
        } catch {
            errorMessage = ProfileError.avatarUploadFailed(error.localizedDescription).errorDescription
        }

        isUploadingAvatar = false
    }

    /// Removes the current avatar image.
    func removeAvatar() async {
        isUploadingAvatar = true
        errorMessage = nil

        do {
            // TODO: Also delete from Supabase Storage when upload is wired.
            try await Task.sleep(nanoseconds: 400_000_000)

            avatarImage = nil
            avatarURL = nil

            // Clear the avatar URL in the local KMP database.
            _ = await AuthService.shared.updateAvatar(nil)
            showSuccess("Photo removed.")
        } catch is CancellationError {
            // Silently ignore cancellation.
        } catch {
            errorMessage = ProfileError.avatarUploadFailed(error.localizedDescription).errorDescription
        }

        isUploadingAvatar = false
    }

    /// Signs the current user out and returns to the unauthenticated state.
    ///
    /// Awaits the KMP logout (token clear + local DB cleanup) before posting
    /// the sign-out notification so the root view transitions back to the
    /// login screen only after the session is fully cleared.
    func signOut() {
        Task {
            // Release Screen Time shields BEFORE clearing the DB so a credit Flow
            // emission (available == 0) cannot re-apply blocking after unblock.
            await MainActor.run {
                ScreenTimeManager.shared.releaseRestrictionsForLogout()
            }
            await AuthService.shared.logout()
            NotificationCenter.default.post(name: .userDidSignOut, object: nil)
        }
    }

    /// Permanently deletes the user's account after confirmation.
    func deleteAccount() async {
        isDeletingAccount = true
        errorMessage = nil

        do {
            // Replace with real account deletion:
            //   try await supabaseClient.rpc("delete_user_account").execute()
            //   try await supabaseClient.auth.signOut()
            try await Task.sleep(nanoseconds: 1_500_000_000)
            await MainActor.run {
                ScreenTimeManager.shared.releaseRestrictionsForLogout()
            }
            NotificationCenter.default.post(name: .userDidSignOut, object: nil)
        } catch is CancellationError {
            // Silently ignore cancellation.
        } catch {
            errorMessage = ProfileError.deleteFailed(error.localizedDescription).errorDescription
        }

        isDeletingAccount = false
    }

    /// Clears the current error message. Called when the user dismisses the alert.
    func clearError() {
        errorMessage = nil
    }

    // MARK: - Private Helpers

    /// Loads the image data from a `PhotosPickerItem` and triggers the upload.
    private func loadSelectedPhoto(_ item: PhotosPickerItem) async {
        do {
            guard let data = try await item.loadTransferable(type: Data.self),
                  let image = UIImage(data: data) else {
                errorMessage = ProfileError.avatarUploadFailed(
                    "Could not read the selected image."
                ).errorDescription
                selectedPhotoItem = nil
                return
            }
            await uploadAvatar(image)
        } catch is CancellationError {
            // Silently ignore cancellation.
        } catch {
            errorMessage = ProfileError.avatarUploadFailed(
                error.localizedDescription
            ).errorDescription
        }
        // Reset so the same photo can be re-selected if needed.
        selectedPhotoItem = nil
    }

    /// Shows a success message and auto-clears it after 2.5 seconds.
    private func showSuccess(_ message: String) {
        successMessage = message
        // Cancel any previous dismiss task to avoid race conditions.
        successDismissTask?.cancel()
        successDismissTask = Task {
            try? await Task.sleep(nanoseconds: 2_500_000_000)
            guard !Task.isCancelled else { return }
            if successMessage == message {
                successMessage = nil
            }
        }
    }

    /// Resizes an image so its longest edge does not exceed `maxDimension`.
    /// Returns the original image if it is already within bounds.
    private static func resizeImage(
        _ image: UIImage,
        maxDimension: CGFloat
    ) -> UIImage {
        let size = image.size
        guard size.width > maxDimension || size.height > maxDimension else {
            return image
        }
        let scale: CGFloat
        if size.width > size.height {
            scale = maxDimension / size.width
        } else {
            scale = maxDimension / size.height
        }
        let newSize = CGSize(
            width: (size.width * scale).rounded(.down),
            height: (size.height * scale).rounded(.down)
        )
        let renderer = UIGraphicsImageRenderer(size: newSize)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: newSize))
        }
    }

    // MARK: - Avatar Visibility

    /// Saves the avatar visibility setting chosen by the user.
    func saveAvatarVisibility(_ option: AvatarVisibilityOption) async {
        isSavingAvatarVisibility = true
        let result = await AuthService.shared.updateAvatarVisibility(option.rawValue)
        isSavingAvatarVisibility = false
        if result.isSuccess {
            avatarVisibility = option
            showSuccess("Avatar visibility updated.")
        } else {
            errorMessage = result.errorMessage ?? "Could not update avatar visibility."
        }
    }

    // MARK: - Private Helpers

    /// Populates all published properties from a real KMP [User] object.
    private func applyUserData(_ user: User) {
        displayName = user.displayName
        savedDisplayName = user.displayName

        let currentUsername = user.username ?? ""
        usernameInput = currentUsername
        savedUsername = currentUsername

        email = user.email

        // Avatar: use the URL from the KMP User (resolved: custom > OAuth).
        // Only update avatarURL if we don't already have a locally held image
        // (which means the user just picked a photo and it hasn't been uploaded yet).
        if avatarImage == nil {
            avatarURL = user.avatarUrl
        }

        // Avatar visibility
        avatarVisibility = AvatarVisibilityOption(rawValue: user.avatarVisibility.toDbValue()) ?? .everyone

        // Format the member-since date from the KMP Instant (epoch seconds).
        let joinDate = Date(timeIntervalSince1970: Double(user.createdAt.epochSeconds))
        let formatter = DateFormatter()
        formatter.dateStyle = .long
        formatter.timeStyle = .none
        memberSinceText = formatter.string(from: joinDate)

        // Stats will be populated by the session observation Flow.
        // Show zero initially until the first emission arrives.
        if stats == nil {
            stats = ProfileStats(totalPushUps: 0, totalWorkouts: 0, totalEarnedMinutes: 0)
        }
    }

    /// Fetches the current XP / level state from the KMP LevelBridge.
    ///
    /// Uses a continuation to bridge the callback-based KMP API into async/await.
    /// On failure the level card is simply hidden (levelInfo stays nil) rather
    /// than surfacing an error -- level data is non-critical.
    private func loadLevel(userId: String) async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            LevelBridge.shared.getUserLevel(
                userId: userId,
                onResult: { [weak self] result in
                    self?.levelInfo = LevelInfo(
                        level: Int(result.level),
                        totalXp: result.totalXp,
                        xpIntoLevel: result.xpIntoLevel,
                        xpRequiredForNextLevel: result.xpRequiredForNextLevel,
                        levelProgress: result.levelProgress
                    )
                    continuation.resume()
                },
                onError: { [weak self] _ in
                    // Non-critical: hide the level card silently on error.
                    self?.levelInfo = nil
                    continuation.resume()
                }
            )
        }
    }

    /// Fetches per-exercise XP / level data from the KMP LevelBridge.
    private func loadExerciseLevels(userId: String) async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            LevelBridge.shared.getExerciseLevels(
                userId: userId,
                onResult: { [weak self] results in
                    self?.exerciseLevels = results.map { r in
                        ExerciseLevelInfo(
                            exerciseTypeId: r.exerciseTypeId,
                            level: Int(r.level),
                            totalXp: r.totalXp,
                            xpIntoLevel: r.xpIntoLevel,
                            xpRequiredForNextLevel: r.xpRequiredForNextLevel,
                            levelProgress: r.levelProgress
                        )
                    }
                    continuation.resume()
                },
                onError: { [weak self] _ in
                    self?.exerciseLevels = nil
                    continuation.resume()
                }
            )
        }
    }

    /// Starts observing workout sessions to compute live profile statistics.
    private func startObservingStats(userId: String) {
        guard sessionObservationJob == nil else { return }

        sessionObservationJob = DataBridge.shared.observeSessions(userId: userId) { [weak self] sessions in
            guard let self else { return }
            let completed = sessions.filter { $0.endedAt != nil }
            let totalPushUps = completed.reduce(0) { $0 + Int($1.pushUpCount) }
            let totalEarned  = completed.reduce(0) { $0 + Int($1.earnedTimeCreditSeconds) }
            self.stats = ProfileStats(
                totalPushUps: totalPushUps,
                totalWorkouts: completed.count,
                totalEarnedMinutes: totalEarned / 60
            )
        }
    }
}

// MARK: - Notification Names

extension Notification.Name {
    /// Posted when the user signs out or deletes their account.
    /// The root `PushUpApp` / `ContentView` observes this to transition
    /// back to the authentication flow.
    static let userDidSignOut = Notification.Name("userDidSignOut")
}
