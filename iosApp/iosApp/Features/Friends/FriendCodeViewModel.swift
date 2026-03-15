import Foundation
import Shared

// MARK: - View-layer model

/// Privacy options shown in the picker, matching the backend enum.
enum FriendCodePrivacyOption: String, CaseIterable, Identifiable {
    case autoAccept      = "auto_accept"
    case requireApproval = "require_approval"
    case inactive        = "inactive"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .autoAccept:      return "Auto-Accept"
        case .requireApproval: return "Require Approval"
        case .inactive:        return "Inactive"
        }
    }

    var description: String {
        switch self {
        case .autoAccept:
            return "Anyone who uses your code is added as a friend immediately."
        case .requireApproval:
            return "Using your code sends a friend request that you must accept."
        case .inactive:
            return "Your code is disabled. Nobody can add you via code right now."
        }
    }

    var systemImage: String {
        switch self {
        case .autoAccept:      return "person.badge.plus"
        case .requireApproval: return "person.badge.clock"
        case .inactive:        return "slash.circle"
        }
    }

    /// Maps from the KMP domain enum.
    init(from kmpPrivacy: Shared.FriendCodePrivacy) {
        switch kmpPrivacy {
        case .autoAccept:      self = .autoAccept
        case .requireApproval: self = .requireApproval
        case .inactive:        self = .inactive
        default:               self = .requireApproval
        }
    }
}

// MARK: - FriendCodeViewModel

/// ViewModel for the Friend Code screen and the Enter Code sheet.
///
/// Owns:
/// - Loading and displaying the user's own friend code
/// - Updating the privacy setting
/// - Resetting the code
/// - Entering / scanning a friend code
///
/// All `@Published` mutations happen on the main actor. `FriendCodeBridge`
/// guarantees its callbacks are dispatched on `Dispatchers.Main`.
@MainActor
final class FriendCodeViewModel: ObservableObject {

    // MARK: Own code state

    @Published var code: String = ""
    @Published var privacy: FriendCodePrivacyOption = .requireApproval
    @Published var deepLink: String = ""
    @Published var isLoading: Bool = false
    @Published var loadError: String? = nil

    // MARK: Privacy update state

    @Published var isUpdatingPrivacy: Bool = false
    @Published var privacyUpdateError: String? = nil

    // MARK: Reset state

    @Published var isResetting: Bool = false
    @Published var showResetConfirm: Bool = false
    @Published var resetError: String? = nil

    // MARK: Enter code state

    @Published var enteredCode: String = ""
    @Published var isUsingCode: Bool = false
    @Published var useCodeError: String? = nil
    @Published var useCodeSuccess: UseFriendCodeSuccessInfo? = nil

    // MARK: - Load own code

    func loadMyCode() {
        guard !isLoading else { return }
        isLoading = true
        loadError = nil

        FriendCodeBridge.shared.getMyFriendCode(
            onResult: { [weak self] friendCode in
                guard let self else { return }
                self.applyCode(friendCode)
                self.isLoading = false
            },
            onError: { [weak self] error in
                guard let self else { return }
                self.loadError = error
                self.isLoading = false
            }
        )
    }

    // MARK: - Update privacy

    func updatePrivacy(_ option: FriendCodePrivacyOption) {
        guard !isUpdatingPrivacy else { return }
        isUpdatingPrivacy = true
        privacyUpdateError = nil

        FriendCodeBridge.shared.updatePrivacy(
            privacy: option.rawValue,
            onResult: { [weak self] friendCode in
                guard let self else { return }
                self.applyCode(friendCode)
                self.isUpdatingPrivacy = false
            },
            onError: { [weak self] error in
                guard let self else { return }
                self.privacyUpdateError = error
                self.isUpdatingPrivacy = false
            }
        )
    }

    // MARK: - Reset code

    func confirmReset() {
        showResetConfirm = true
    }

    func resetCode() {
        guard !isResetting else { return }
        isResetting = true
        resetError = nil

        FriendCodeBridge.shared.resetCode(
            onResult: { [weak self] friendCode in
                guard let self else { return }
                self.applyCode(friendCode)
                self.isResetting = false
            },
            onError: { [weak self] error in
                guard let self else { return }
                self.resetError = error
                self.isResetting = false
            }
        )
    }

    // MARK: - Use a friend code

    /// Called after a successful friend-code use so the friends list and
    /// leaderboard refresh automatically without the user pulling to reload.
    var onFriendAdded: (() -> Void)? = nil

    func useFriendCode() {
        let trimmed = enteredCode.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard !trimmed.isEmpty, !isUsingCode else { return }
        isUsingCode = true
        useCodeError = nil
        useCodeSuccess = nil

        FriendCodeBridge.shared.useFriendCode(
            code: trimmed,
            onResult: { [weak self] result in
                guard let self else { return }
                self.useCodeSuccess = UseFriendCodeSuccessInfo(
                    result: result.result,
                    ownerName: result.ownerProfile.displayName ?? result.ownerProfile.username ?? "Unknown"
                )
                self.enteredCode = ""
                self.isUsingCode = false
                // Auto-refresh the friends list and leaderboard when the code
                // resulted in an immediate friendship (auto_accept mode).
                // For pending requests we skip the refresh since nothing changed yet.
                if result.result == "added" {
                    self.onFriendAdded?()
                }
            },
            onError: { [weak self] error in
                guard let self else { return }
                self.useCodeError = error
                self.isUsingCode = false
            }
        )
    }

    func dismissUseCodeSuccess() { useCodeSuccess = nil }
    func dismissUseCodeError()   { useCodeError = nil }
    func dismissPrivacyError()   { privacyUpdateError = nil }
    func dismissResetError()     { resetError = nil }

    // MARK: - Private helpers

    private func applyCode(_ friendCode: Shared.FriendCode) {
        code     = friendCode.code
        privacy  = FriendCodePrivacyOption(from: friendCode.privacy)
        deepLink = friendCode.deepLink
    }
}

// MARK: - Success info

struct UseFriendCodeSuccessInfo {
    /// "added" or "pending"
    let result: String
    let ownerName: String

    var title: String {
        result == "added" ? "Friend Added!" : "Request Sent!"
    }

    var message: String {
        result == "added"
            ? "You and \(ownerName) are now friends."
            : "Your friend request to \(ownerName) is pending their approval."
    }
}
