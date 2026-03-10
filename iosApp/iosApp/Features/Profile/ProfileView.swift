import SwiftUI
import PhotosUI

// MARK: - ProfileView

/// User profile screen showing avatar, account info, lifetime statistics,
/// achievements placeholder, and account management actions.
///
/// **Layout**
/// ```
/// +-----------------------------------+
/// |  Profile                          |  <- navigation bar
/// |                                   |
/// |  [Avatar]  Name  Email  Since     |  <- hero header card
/// |                                   |
/// |  [Push-Ups] [Workouts] [Time]     |  <- stats grid
/// |                                   |
/// |  Achievements (placeholder)       |  <- achievements section
/// |                                   |
/// |  [Sign Out]                       |  <- account actions
/// |  [Delete Account]                 |
/// +-----------------------------------+
/// ```
///
/// **Features**
/// - Avatar upload from camera or photo library (stored in Supabase Storage)
/// - Editable display name with inline save and validation
/// - Read-only email and member-since date
/// - Lifetime stats: total push-ups, workouts, earned time
/// - Achievements section (placeholder for future implementation)
/// - Logout with immediate transition to auth flow
/// - Account deletion with confirmation alert
struct ProfileView: View {

    @StateObject private var viewModel = ProfileViewModel()

    @FocusState private var isNameFieldFocused: Bool

    private var showError: Binding<Bool> {
        Binding(
            get: { viewModel.errorMessage != nil },
            set: { if !$0 { viewModel.clearError() } }
        )
    }

    var body: some View {
        ZStack {
            AppColors.backgroundPrimary
                .ignoresSafeArea()

            if viewModel.isLoading {
                initialLoadingView
            } else {
                scrollContent
            }
        }
        .navigationTitle("Profile")
        .navigationBarTitleDisplayMode(.large)
        .task { await viewModel.loadData() }
        // Error alert
        .alert("Error", isPresented: showError) {
            Button("OK", role: .cancel) { viewModel.clearError() }
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
        // Delete account confirmation
        .alert("Delete Account", isPresented: $viewModel.showDeleteConfirmation) {
            Button("Delete", role: .destructive) {
                Task { await viewModel.deleteAccount() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This action is permanent and cannot be undone. All your data, workouts, and time credit will be deleted.")
        }
        // Avatar source picker
        .confirmationDialog(
            "Change Profile Photo",
            isPresented: $viewModel.showAvatarSourcePicker,
            titleVisibility: .visible
        ) {
            avatarSourceDialogButtons
        }
        // Camera sheet
        .sheet(isPresented: $viewModel.showCamera) {
            CameraImagePicker { image in
                Task { await viewModel.uploadAvatar(image) }
            }
            .ignoresSafeArea()
        }
        // Photo library picker
        .photosPicker(
            isPresented: $viewModel.showPhotoPicker,
            selection: $viewModel.selectedPhotoItem,
            matching: .images,
            photoLibrary: .shared()
        )
    }

    // MARK: - Avatar Source Dialog Buttons

    @ViewBuilder
    private var avatarSourceDialogButtons: some View {
        if UIImagePickerController.isSourceTypeAvailable(.camera) {
            Button("Take Photo") {
                viewModel.showCamera = true
            }
        }
        Button("Choose from Library") {
            viewModel.showPhotoPicker = true
        }
        if viewModel.avatarImage != nil {
            Button("Remove Photo", role: .destructive) {
                Task { await viewModel.removeAvatar() }
            }
        }
        Button("Cancel", role: .cancel) {}
    }

    // MARK: - Scroll Content

    private var scrollContent: some View {
        ScrollView {
            LazyVStack(spacing: AppSpacing.md) {
                headerCard
                levelCard
                statsSection
                achievementsSection
                accountActionsSection
            }
            .padding(.horizontal, AppSpacing.screenHorizontal)
            .padding(.top, AppSpacing.sm)
            .padding(.bottom, AppSpacing.screenVerticalBottom)
        }
        .scrollDismissesKeyboard(.interactively)
        .overlay(alignment: .top) {
            successToastOverlay
        }
    }

    // MARK: - Success Toast Overlay

    @ViewBuilder
    private var successToastOverlay: some View {
        if let message = viewModel.successMessage {
            successToast(message)
                .transition(.move(edge: .top).combined(with: .opacity))
                .padding(.top, AppSpacing.sm)
        }
    }

    // MARK: - Header Card

    private var headerCard: some View {
        Card {
            VStack(spacing: AppSpacing.lg) {
                avatarSection
                Divider()
                displayNameRow
                profileInfoRow(
                    icon: .envelope,
                    label: "Email",
                    value: viewModel.email,
                    tint: AppColors.info
                )
                profileInfoRow(
                    icon: .calendarBadgeCheckmark,
                    label: "Member since",
                    value: viewModel.memberSinceText,
                    tint: AppColors.success
                )
            }
        }
    }

    // MARK: - Avatar Section

    private var avatarSection: some View {
        VStack(spacing: AppSpacing.sm) {
            AvatarPickerButton(
                image: viewModel.avatarImage,
                initials: viewModel.initials,
                isUploading: viewModel.isUploadingAvatar,
                size: 96
            ) {
                isNameFieldFocused = false
                viewModel.showAvatarSourcePicker = true
            }

            if viewModel.isUploadingAvatar {
                Text("Uploading...")
                    .font(AppTypography.caption1)
                    .foregroundStyle(AppColors.textSecondary)
            }
        }
    }

    // MARK: - Display Name Row

    private var displayNameRow: some View {
        VStack(alignment: .leading, spacing: AppSpacing.xs) {
            HStack(spacing: AppSpacing.xs) {
                Image(systemName: AppIcon.personFill.rawValue)
                    .font(.system(size: AppSpacing.iconSizeSmall, weight: .semibold))
                    .foregroundStyle(AppColors.primary)
                    .frame(width: AppSpacing.iconSizeMedium)

                Text("Display Name")
                    .font(AppTypography.caption1)
                    .foregroundStyle(AppColors.textSecondary)

                Spacer()
            }

            HStack(spacing: AppSpacing.xs) {
                TextField("Display Name", text: $viewModel.displayName)
                    .font(AppTypography.bodySemibold)
                    .foregroundStyle(AppColors.textPrimary)
                    .focused($isNameFieldFocused)
                    .submitLabel(.done)
                    .onSubmit {
                        isNameFieldFocused = false
                        guard viewModel.isDisplayNameValid else { return }
                        Task { await viewModel.saveDisplayName() }
                    }
                    .textContentType(.name)
                    .autocorrectionDisabled()

                if viewModel.hasUnsavedNameChange && viewModel.isDisplayNameValid {
                    saveNameButton
                }
            }
            .padding(.horizontal, AppSpacing.sm)
            .frame(height: AppSpacing.buttonHeightSecondary)
            .background(AppColors.backgroundTertiary)
            .clipShape(RoundedRectangle(cornerRadius: AppSpacing.cornerRadiusChip))

            // Inline validation error
            if let error = viewModel.displayNameError {
                Text(error)
                    .font(AppTypography.caption2)
                    .foregroundStyle(AppColors.error)
                    .padding(.leading, AppSpacing.xs)
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: viewModel.displayNameError)
    }

    private var saveNameButton: some View {
        Button {
            isNameFieldFocused = false
            Task { await viewModel.saveDisplayName() }
        } label: {
            Group {
                if viewModel.isSavingName {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .tint(AppColors.primary)
                        .scaleEffect(0.75)
                } else {
                    Image(systemName: AppIcon.checkmark.rawValue)
                        .font(.system(size: AppSpacing.iconSizeSmall, weight: .bold))
                        .foregroundStyle(AppColors.primary)
                }
            }
        }
        .frame(width: AppSpacing.minimumTapTarget, height: AppSpacing.minimumTapTarget)
        .disabled(viewModel.isSavingName)
        .transition(.scale.combined(with: .opacity))
        .animation(.spring(response: 0.3), value: viewModel.hasUnsavedNameChange)
        .accessibilityLabel("Save display name")
    }

    // MARK: - Profile Info Row

    private func profileInfoRow(
        icon: AppIcon,
        label: String,
        value: String,
        tint: Color
    ) -> some View {
        HStack(spacing: AppSpacing.xs) {
            Image(systemName: icon.rawValue)
                .font(.system(size: AppSpacing.iconSizeSmall, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: AppSpacing.iconSizeMedium)

            VStack(alignment: .leading, spacing: AppSpacing.xxs) {
                Text(label)
                    .font(AppTypography.caption1)
                    .foregroundStyle(AppColors.textSecondary)

                Text(value)
                    .font(AppTypography.bodySemibold)
                    .foregroundStyle(AppColors.textPrimary)
            }

            Spacer()
        }
    }

    // MARK: - Level Card

    /// Hero card showing the user's current level, XP progress bar, and totals.
    /// Matches the Compose `LevelCard` design from ProfileScreen.kt.
    @ViewBuilder
    private var levelCard: some View {
        if let info = viewModel.levelInfo {
            levelCardContent(info)
        } else if viewModel.isLoading {
            // Skeleton placeholder while loading
            RoundedRectangle(cornerRadius: AppSpacing.cornerRadiusCard)
                .fill(AppColors.primary.opacity(0.12))
                .frame(height: 160)
                .redacted(reason: .placeholder)
        }
        // When levelInfo is nil and not loading (e.g. not authenticated), show nothing.
    }

    private func levelCardContent(_ info: LevelInfo) -> some View {
        ZStack {
            // Gradient background matching the primary container feel from Compose
            RoundedRectangle(cornerRadius: AppSpacing.cornerRadiusCard)
                .fill(
                    LinearGradient(
                        colors: [AppColors.primary.opacity(0.85), AppColors.primary],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            VStack(alignment: .leading, spacing: AppSpacing.sm) {

                // Top row: "Level N" label + star badge
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Level")
                            .font(AppTypography.caption1)
                            .foregroundStyle(.white.opacity(0.75))

                        Text("\(info.level)")
                            .font(.system(size: 52, weight: .black, design: .rounded))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                    }

                    Spacer()

                    // Star badge circle
                    ZStack {
                        Circle()
                            .fill(.white.opacity(0.2))
                            .frame(width: 56, height: 56)

                        Image(systemName: "star.fill")
                            .font(.system(size: 26, weight: .semibold))
                            .foregroundStyle(.white)
                            .symbolRenderingMode(.hierarchical)
                    }
                }

                // XP progress label
                Text("XP Progress")
                    .font(AppTypography.caption1)
                    .foregroundStyle(.white.opacity(0.75))

                // Progress bar
                LevelProgressBar(progress: info.levelProgress)

                // XP numbers row
                HStack {
                    Text("\(info.xpIntoLevel) XP")
                        .font(AppTypography.caption2)
                        .foregroundStyle(.white.opacity(0.8))

                    Spacer()

                    Text("\(info.xpRequiredForNextLevel) XP to next level")
                        .font(AppTypography.caption2)
                        .foregroundStyle(.white.opacity(0.8))
                }

                // Total XP
                Text("Total XP: \(info.totalXp)")
                    .font(AppTypography.captionSemibold)
                    .foregroundStyle(.white)
            }
            .padding(AppSpacing.md)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Level \(info.level). \(info.xpIntoLevel) of \(info.xpRequiredForNextLevel) XP to next level. Total XP: \(info.totalXp).")
    }

    // MARK: - Stats Section

    private var statsSection: some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            sectionHeader("Account Statistics", icon: .chartBarFill)

            if let stats = viewModel.stats {
                statsGrid(stats)
            } else {
                statsLoadingPlaceholder
            }
        }
    }

    private func statsGrid(_ stats: ProfileStats) -> some View {
        LazyVGrid(
            columns: Array(
                repeating: GridItem(.flexible()),
                count: 3
            ),
            spacing: AppSpacing.sm
        ) {
            ProfileStatCell(
                value: formatLargeNumber(stats.totalPushUps),
                label: "Push-Ups",
                icon: .figureStrengthTraining,
                tint: AppColors.primary
            )

            ProfileStatCell(
                value: "\(stats.totalWorkouts)",
                label: "Workouts",
                icon: .flameFill,
                tint: AppColors.secondary
            )

            ProfileStatCell(
                value: formatMinutes(stats.totalEarnedMinutes),
                label: "Time Earned",
                icon: .clockBadgeCheckmark,
                tint: AppColors.success
            )
        }
    }

    private var statsLoadingPlaceholder: some View {
        HStack(spacing: AppSpacing.sm) {
            ForEach(0..<3, id: \.self) { _ in
                RoundedRectangle(cornerRadius: AppSpacing.cornerRadiusCard)
                    .fill(AppColors.backgroundSecondary)
                    .frame(height: 80)
                    .redacted(reason: .placeholder)
            }
        }
    }

    // MARK: - Achievements Section

    private var achievementsSection: some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            sectionHeader("Achievements", icon: .starFill)

            Card(hasShadow: false) {
                VStack(spacing: AppSpacing.md) {
                    Image(systemName: AppIcon.starFill.rawValue)
                        .font(.system(size: AppSpacing.iconSizeXL, weight: .light))
                        .foregroundStyle(AppColors.textTertiary)
                        .symbolRenderingMode(.hierarchical)

                    VStack(spacing: AppSpacing.xxs) {
                        Text("Coming Soon")
                            .font(AppTypography.headline)
                            .foregroundStyle(AppColors.textPrimary)

                        Text("Achievements and badges will appear here once you reach milestones.")
                            .font(AppTypography.caption1)
                            .foregroundStyle(AppColors.textSecondary)
                            .multilineTextAlignment(.center)
                    }
                }
                .padding(.vertical, AppSpacing.lg)
                .frame(maxWidth: .infinity)
            }
        }
    }

    // MARK: - Account Actions Section

    private var accountActionsSection: some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            sectionHeader("Account", icon: .personFill)

            VStack(spacing: AppSpacing.xs) {
                SecondaryButton("Sign Out", icon: .arrowRightSquare) {
                    viewModel.signOut()
                }

                deleteAccountButton
            }
        }
    }

    private var deleteAccountButton: some View {
        DestructiveButton(
            "Delete Account",
            icon: .trash
        ) {
            viewModel.showDeleteConfirmation = true
        }
        .disabled(viewModel.isDeletingAccount)
        .overlay {
            if viewModel.isDeletingAccount {
                ZStack {
                    RoundedRectangle(cornerRadius: AppSpacing.cornerRadiusButton)
                        .fill(AppColors.backgroundSecondary.opacity(0.6))
                    ProgressView()
                        .progressViewStyle(.circular)
                        .tint(AppColors.error)
                }
            }
        }
    }

    // MARK: - Section Header

    private func sectionHeader(_ title: String, icon: AppIcon) -> some View {
        HStack(spacing: AppSpacing.xs) {
            Image(systemName: icon.rawValue)
                .font(.system(size: AppSpacing.iconSizeSmall, weight: .semibold))
                .foregroundStyle(AppColors.primary)

            Text(title)
                .font(AppTypography.title3)
                .foregroundStyle(AppColors.textPrimary)
        }
        .padding(.top, AppSpacing.xs)
        .accessibilityAddTraits(.isHeader)
    }

    // MARK: - Success Toast

    private func successToast(_ message: String) -> some View {
        HStack(spacing: AppSpacing.xs) {
            Image(systemName: AppIcon.checkmarkCircleFill.rawValue)
                .font(.system(size: AppSpacing.iconSizeSmall, weight: .semibold))
                .foregroundStyle(AppColors.success)

            Text(message)
                .font(AppTypography.captionSemibold)
                .foregroundStyle(AppColors.textPrimary)
        }
        .padding(.horizontal, AppSpacing.md)
        .padding(.vertical, AppSpacing.xs)
        .background(AppColors.backgroundSecondary)
        .clipShape(Capsule())
        .shadow(color: Color.black.opacity(0.12), radius: 8, x: 0, y: 4)
    }

    // MARK: - Initial Loading View

    private var initialLoadingView: some View {
        VStack(spacing: AppSpacing.lg) {
            ProgressView()
                .progressViewStyle(.circular)
                .tint(AppColors.primary)
                .scaleEffect(1.4)

            Text("Loading Profile...")
                .font(AppTypography.subheadline)
                .foregroundStyle(AppColors.textSecondary)
        }
    }

    // MARK: - Formatters

    private func formatLargeNumber(_ value: Int) -> String {
        if value >= 10_000 {
            let k = Double(value) / 1_000.0
            return String(format: "%.1fk", k)
        }
        if value >= 1_000 {
            let formatted = NumberFormatter.localizedString(
                from: NSNumber(value: value),
                number: .decimal
            )
            return formatted
        }
        return "\(value)"
    }

    private func formatMinutes(_ minutes: Int) -> String {
        if minutes >= 60 {
            let h = minutes / 60
            let m = minutes % 60
            return m > 0 ? "\(h)h \(m)m" : "\(h)h"
        }
        return "\(minutes)m"
    }
}

// MARK: - LevelProgressBar

/// Thin rounded progress bar used inside the level card.
///
/// Renders a track with a filled indicator whose width is proportional to
/// [progress] (0.0 = empty, 1.0 = full). Animates smoothly when the value changes.
struct LevelProgressBar: View {

    /// Progress fraction in [0.0, 1.0).
    let progress: Double

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                // Track
                Capsule()
                    .fill(.white.opacity(0.2))
                    .frame(height: 10)

                // Fill
                Capsule()
                    .fill(.white)
                    .frame(
                        width: max(0, geo.size.width * CGFloat(min(progress, 1.0))),
                        height: 10
                    )
                    .animation(.easeInOut(duration: 0.4), value: progress)
            }
        }
        .frame(height: 10)
    }
}

// MARK: - ProfileStatCell

/// Compact stat cell used in the 3-column statistics grid on the profile screen.
struct ProfileStatCell: View {

    let value: String
    let label: String
    let icon: AppIcon
    let tint: Color

    var body: some View {
        Card(padding: AppSpacing.sm) {
            VStack(spacing: AppSpacing.xs) {
                Image(systemName: icon.rawValue)
                    .font(.system(size: AppSpacing.iconSizeMedium, weight: .semibold))
                    .foregroundStyle(tint)
                    .symbolRenderingMode(.hierarchical)

                Text(value)
                    .font(AppTypography.title3)
                    .foregroundStyle(AppColors.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)

                Text(label)
                    .font(AppTypography.caption2)
                    .foregroundStyle(AppColors.textSecondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
            }
            .frame(maxWidth: .infinity)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(label): \(value)")
        }
    }
}

// MARK: - Previews

#if DEBUG
#Preview("ProfileView - Loaded") {
    NavigationStack {
        ProfileView()
    }
}

#Preview("ProfileView - Dark") {
    NavigationStack {
        ProfileView()
    }
    .preferredColorScheme(.dark)
}
#endif
