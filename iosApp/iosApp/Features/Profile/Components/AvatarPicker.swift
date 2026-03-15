import SwiftUI

// MARK: - AvatarView

/// Circular avatar display with three display modes:
///
/// 1. **Local image** (`image` parameter) — shown immediately, used after
///    the user picks a photo from camera/library before it is uploaded.
/// 2. **Remote URL** (`url` parameter) — loaded asynchronously via AsyncImage.
///    Shows a shimmer placeholder while loading and falls back to initials on error.
/// 3. **Initials fallback** — shown when both `image` and `url` are nil, or
///    when the remote image fails to load.
///
/// Priority: local `image` > remote `url` > initials.
///
/// Usage:
/// ```swift
/// // Own profile (local UIImage after picking):
/// AvatarView(image: viewModel.avatarImage, initials: viewModel.initials, size: 96)
///
/// // Friend in search results (remote URL):
/// AvatarView(url: URL(string: item.avatarUrl), initials: item.initials, size: 44)
/// ```
struct AvatarView: View {

    /// A locally held UIImage (e.g. just picked from camera). Takes priority over `url`.
    var image: UIImage? = nil
    /// A remote URL to load asynchronously.
    var url: URL? = nil
    let initials: String
    let size: CGFloat

    private var fontSize: CGFloat { size * 0.36 }

    var body: some View {
        Group {
            if let image {
                // Local image — show immediately (no network needed).
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else if let url {
                // Remote URL — load asynchronously.
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .empty:
                        // Loading: show a subtle shimmer placeholder.
                        shimmerView
                    case .success(let loaded):
                        loaded
                            .resizable()
                            .scaledToFill()
                    case .failure:
                        // Network error or bad URL: fall back to initials.
                        initialsView
                    @unknown default:
                        initialsView
                    }
                }
            } else {
                initialsView
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .accessibilityHidden(true)
    }

    // MARK: - Sub-views

    private var initialsView: some View {
        ZStack {
            Circle()
                .fill(
                    LinearGradient(
                        colors: [AppColors.primary, AppColors.primary.opacity(0.7)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            Text(initials)
                .font(.system(size: fontSize, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
        }
    }

    private var shimmerView: some View {
        Circle()
            .fill(AppColors.backgroundSecondary)
            .overlay(
                Circle()
                    .fill(AppColors.textTertiary.opacity(0.15))
            )
    }
}

// MARK: - AvatarPickerButton

/// Interactive avatar that shows the current image (or initials fallback),
/// an upload-progress overlay, and a camera-badge edit indicator.
///
/// Tapping the button triggers the `onTap` closure so the parent view can
/// present the source-selection action sheet.
///
/// Usage:
/// ```swift
/// AvatarPickerButton(
///     image: viewModel.avatarImage,
///     initials: viewModel.initials,
///     isUploading: viewModel.isUploadingAvatar,
///     size: 96
/// ) {
///     viewModel.showAvatarSourcePicker = true
/// }
/// ```
struct AvatarPickerButton: View {

    let image: UIImage?
    let initials: String
    let isUploading: Bool
    var size: CGFloat = 96
    let onTap: () -> Void

    private var badgeSize: CGFloat { size * 0.32 }

    var body: some View {
        Button(action: onTap) {
            ZStack(alignment: .bottomTrailing) {
                AvatarView(image: image, initials: initials, size: size)
                    .overlay(uploadOverlay)
                    .shadow(
                        color: AppColors.primary.opacity(0.25),
                        radius: 12, x: 0, y: 4
                    )

                if !isUploading {
                    cameraBadge
                }
            }
        }
        .buttonStyle(ScaleButtonStyle())
        .accessibilityLabel("Change profile photo")
        .accessibilityHint("Opens options to take a photo or choose from library")
        .disabled(isUploading)
    }

    // MARK: - Sub-views

    @ViewBuilder
    private var uploadOverlay: some View {
        if isUploading {
            ZStack {
                Circle()
                    .fill(Color.black.opacity(0.45))

                ProgressView()
                    .progressViewStyle(.circular)
                    .tint(.white)
                    .scaleEffect(0.9)
            }
        }
    }

    private var cameraBadge: some View {
        ZStack {
            Circle()
                .fill(AppColors.primary)
                .frame(width: badgeSize, height: badgeSize)

            Image(systemName: AppIcon.camera.rawValue)
                .font(.system(size: badgeSize * 0.48, weight: .semibold))
                .foregroundStyle(.white)
        }
        .shadow(color: Color.black.opacity(0.2), radius: 4, x: 0, y: 2)
        .offset(x: 2, y: 2)
    }
}

// MARK: - CameraImagePicker

/// A `UIViewControllerRepresentable` wrapper around `UIImagePickerController`
/// for capturing a photo with the device camera.
///
/// Usage:
/// ```swift
/// .sheet(isPresented: $showCamera) {
///     CameraImagePicker { image in
///         Task { await viewModel.uploadAvatar(image) }
///     }
/// }
/// ```
struct CameraImagePicker: UIViewControllerRepresentable {

    @Environment(\.dismiss) private var dismiss

    let onImagePicked: (UIImage) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onImagePicked: onImagePicked, dismiss: dismiss)
    }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.allowsEditing = true
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(
        _ uiViewController: UIImagePickerController,
        context: Context
    ) {}

    // MARK: - Coordinator

    final class Coordinator: NSObject,
        UIImagePickerControllerDelegate,
        UINavigationControllerDelegate
    {
        private let onImagePicked: (UIImage) -> Void
        private let dismiss: DismissAction

        init(
            onImagePicked: @escaping (UIImage) -> Void,
            dismiss: DismissAction
        ) {
            self.onImagePicked = onImagePicked
            self.dismiss = dismiss
        }

        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            let image = (info[.editedImage] ?? info[.originalImage]) as? UIImage
            dismiss()
            if let image {
                onImagePicked(image)
            }
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            dismiss()
        }
    }
}

// MARK: - Previews

#if DEBUG
#Preview("AvatarView - Initials") {
    VStack(spacing: AppSpacing.lg) {
        AvatarView(image: nil, initials: "AJ", size: 96)
        AvatarView(image: nil, initials: "M", size: 64)
        AvatarView(image: nil, initials: "?", size: 48)
    }
    .padding()
    .background(AppColors.backgroundPrimary)
}

#Preview("AvatarPickerButton") {
    VStack(spacing: AppSpacing.lg) {
        AvatarPickerButton(
            image: nil,
            initials: "AJ",
            isUploading: false,
            size: 96
        ) {}

        AvatarPickerButton(
            image: nil,
            initials: "AJ",
            isUploading: true,
            size: 96
        ) {}
    }
    .padding()
    .background(AppColors.backgroundPrimary)
}
#endif
