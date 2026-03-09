import SwiftUI
import PhotosUI

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

    /// The user's email address (read-only).
    @Published private(set) var email: String = ""

    /// The date the user registered (formatted for display).
    @Published private(set) var memberSinceText: String = ""

    /// The currently displayed avatar image. `nil` shows the initials fallback.
    @Published private(set) var avatarImage: UIImage? = nil

    /// The URL string of the avatar stored in Supabase Storage.
    @Published private(set) var avatarURL: String? = nil

    /// Lifetime account statistics.
    @Published private(set) var stats: ProfileStats? = nil

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

    // MARK: - Private

    /// The last successfully saved display name. Used to detect unsaved changes.
    private var savedDisplayName: String = ""

    /// Cancellable handle for the success-message auto-dismiss task.
    private var successDismissTask: Task<Void, Never>?

    // MARK: - Init

    init() {}

    // MARK: - Actions

    /// Loads all profile data. Called on first appear.
    func loadData() async {
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil

        do {
            // Simulate network / database latency.
            // Replace with real Supabase profile fetch:
            //   let profile = try await supabaseClient.from("profiles")
            //       .select()
            //       .eq("id", value: currentUserId)
            //       .single()
            //       .execute()
            //       .value as ProfileRow
            try await Task.sleep(nanoseconds: 800_000_000)
            applyStubData()
        } catch is CancellationError {
            // Task was cancelled (e.g. view disappeared) -- do not set error.
        } catch {
            errorMessage = ProfileError.loadFailed(error.localizedDescription).errorDescription
        }

        isLoading = false
    }

    /// Saves the edited display name to the backend.
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

        do {
            // Replace with real Supabase update:
            //   try await supabaseClient.from("profiles")
            //       .update(["display_name": trimmed])
            //       .eq("id", value: currentUserId)
            //       .execute()
            try await Task.sleep(nanoseconds: 600_000_000)
            savedDisplayName = trimmed
            displayName = trimmed
            showSuccess("Display name updated.")
        } catch is CancellationError {
            // Silently ignore cancellation.
        } catch {
            errorMessage = ProfileError.saveFailed(error.localizedDescription).errorDescription
        }

        isSavingName = false
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

            // Replace with real Supabase Storage upload:
            //   let fileName = "\(currentUserId)/avatar.jpg"
            //   try await supabaseClient.storage
            //       .from("avatars")
            //       .upload(fileName, data: imageData, options: .init(contentType: "image/jpeg", upsert: true))
            //   let publicURL = try supabaseClient.storage.from("avatars").getPublicURL(path: fileName)
            //   try await supabaseClient.from("profiles")
            //       .update(["avatar_url": publicURL.absoluteString])
            //       .eq("id", value: currentUserId)
            //       .execute()
            _ = imageData
            try await Task.sleep(nanoseconds: 1_200_000_000)

            avatarImage = resized
            avatarURL = "https://storage.supabase.co/avatars/stub.jpg"
            showSuccess("Avatar updated.")
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
            // Replace with real Supabase Storage delete:
            //   let fileName = "\(currentUserId)/avatar.jpg"
            //   try await supabaseClient.storage.from("avatars").remove(paths: [fileName])
            //   try await supabaseClient.from("profiles")
            //       .update(["avatar_url": NSNull()])
            //       .eq("id", value: currentUserId)
            //       .execute()
            try await Task.sleep(nanoseconds: 600_000_000)

            avatarImage = nil
            avatarURL = nil
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
    /// Replace the stub with a real Supabase sign-out call:
    /// ```swift
    /// try await supabaseClient.auth.signOut()
    /// ```
    func signOut() {
        // Notify the root app state to transition back to the auth flow.
        // In a real app this would call the shared AuthViewModel / AppState.
        NotificationCenter.default.post(name: .userDidSignOut, object: nil)
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

    /// Populates all published properties with realistic stub data.
    private func applyStubData() {
        displayName = "Alex Johnson"
        savedDisplayName = "Alex Johnson"
        email = "alex.johnson@example.com"

        // Format the member-since date.
        let joinDate = Calendar.current.date(
            byAdding: .month, value: -7, to: Date()
        ) ?? Date()
        let formatter = DateFormatter()
        formatter.dateStyle = .long
        formatter.timeStyle = .none
        memberSinceText = formatter.string(from: joinDate)

        stats = ProfileStats(
            totalPushUps: 3_847,
            totalWorkouts: 142,
            totalEarnedMinutes: 1_154
        )

        // avatarImage stays nil to show the initials fallback by default.
        // In a real app, load from avatarURL via AsyncImage or SDWebImage.
    }
}

// MARK: - Notification Names

extension Notification.Name {
    /// Posted when the user signs out or deletes their account.
    /// The root `PushUpApp` / `ContentView` observes this to transition
    /// back to the authentication flow.
    static let userDidSignOut = Notification.Name("userDidSignOut")
}
