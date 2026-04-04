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
/// |  [Activity] [Workouts] [Time]     |  <- stats grid
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
/// - Lifetime stats: total activity XP, workouts, earned time
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
            DashboardWidgetChrome.pageBackground
                .ignoresSafeArea()

            if viewModel.isLoading {
                initialLoadingView
            } else {
                scrollContent
            }
        }
        .preferredColorScheme(.dark)
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
        if viewModel.avatarImage != nil || viewModel.avatarURL != nil {
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
                exerciseLevelsSection
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
                usernameRow
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
                url: viewModel.avatarURL.flatMap { URL(string: $0) },
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

    // MARK: - Username Row

    @FocusState private var isUsernameFieldFocused: Bool

    private var usernameRow: some View {
        VStack(alignment: .leading, spacing: AppSpacing.xs) {
            // Label row
            HStack(spacing: AppSpacing.xs) {
                Image(systemName: "at")
                    .font(.system(size: AppSpacing.iconSizeSmall, weight: .semibold))
                    .foregroundStyle(AppColors.secondary)
                    .frame(width: AppSpacing.iconSizeMedium)

                Text("Username")
                    .font(AppTypography.caption1)
                    .foregroundStyle(AppColors.textSecondary)

                Spacer()
            }

            // Input + availability indicator + save button
            HStack(spacing: AppSpacing.xs) {
                Text("@")
                    .font(AppTypography.bodySemibold)
                    .foregroundStyle(DashboardWidgetChrome.labelMuted)

                TextField("your_username", text: $viewModel.usernameInput)
                    .font(AppTypography.bodySemibold)
                    .foregroundStyle(DashboardWidgetChrome.labelPrimary)
                    .focused($isUsernameFieldFocused)
                    .submitLabel(.done)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .textContentType(.username)
                    .onChange(of: viewModel.usernameInput) { _, _ in
                        viewModel.onUsernameInputChanged()
                    }
                    .onSubmit {
                        isUsernameFieldFocused = false
                        guard viewModel.canSaveUsername else { return }
                        Task { await viewModel.saveUsername() }
                    }

                // Availability indicator
                usernameAvailabilityIndicator

                // Save button (shown when there's a valid, available change)
                if viewModel.canSaveUsername {
                    saveUsernameButton
                }
            }
            .padding(.horizontal, AppSpacing.sm)
            .frame(height: AppSpacing.buttonHeightSecondary)
            .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: AppSpacing.cornerRadiusChip))
            .overlay(
                RoundedRectangle(cornerRadius: AppSpacing.cornerRadiusChip)
                    .stroke(Color.white.opacity(0.10), lineWidth: 1)
            )

            // Validation / availability message
            if let localError = viewModel.usernameValidationError, !viewModel.usernameInput.isEmpty {
                Text(localError)
                    .font(AppTypography.caption2)
                    .foregroundStyle(AppColors.error)
                    .padding(.leading, AppSpacing.xs)
                    .transition(.opacity)
            } else if let checkError = viewModel.usernameCheckError {
                Text("Could not check: \(checkError)")
                    .font(AppTypography.caption2)
                    .foregroundStyle(AppColors.textSecondary)
                    .padding(.leading, AppSpacing.xs)
                    .transition(.opacity)
            } else if let available = viewModel.isUsernameAvailable, viewModel.hasUnsavedUsernameChange {
                Text(available ? "Username is available!" : "Username is already taken.")
                    .font(AppTypography.caption2)
                    .foregroundStyle(available ? AppColors.success : AppColors.error)
                    .padding(.leading, AppSpacing.xs)
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: viewModel.isUsernameAvailable)
    }

    @ViewBuilder
    private var usernameAvailabilityIndicator: some View {
        let trimmed = viewModel.usernameInput.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty || !viewModel.hasUnsavedUsernameChange {
            EmptyView()
        } else if viewModel.isCheckingUsername {
            ProgressView()
                .scaleEffect(0.75)
                .frame(width: 18, height: 18)
        } else if let available = viewModel.isUsernameAvailable {
            Image(systemName: available ? "checkmark.circle.fill" : "xmark.circle.fill")
                .foregroundStyle(available ? AppColors.success : AppColors.error)
                .font(.system(size: 16))
                .transition(.scale.combined(with: .opacity))
        }
    }

    private var saveUsernameButton: some View {
        Button {
            isUsernameFieldFocused = false
            Task { await viewModel.saveUsername() }
        } label: {
            Group {
                if viewModel.isSavingUsername {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .tint(AppColors.secondary)
                        .scaleEffect(0.75)
                } else {
                    Image(systemName: AppIcon.checkmark.rawValue)
                        .font(.system(size: AppSpacing.iconSizeSmall, weight: .bold))
                        .foregroundStyle(AppColors.secondary)
                }
            }
        }
        .frame(width: AppSpacing.minimumTapTarget, height: AppSpacing.minimumTapTarget)
        .disabled(viewModel.isSavingUsername)
        .transition(.scale.combined(with: .opacity))
        .accessibilityLabel("Save username")
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
                    .foregroundStyle(DashboardWidgetChrome.labelSecondary)

                Spacer()
            }

            HStack(spacing: AppSpacing.xs) {
                TextField("Display Name", text: $viewModel.displayName)
                    .font(AppTypography.bodySemibold)
                    .foregroundStyle(DashboardWidgetChrome.labelPrimary)
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
            .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: AppSpacing.cornerRadiusChip))
            .overlay(
                RoundedRectangle(cornerRadius: AppSpacing.cornerRadiusChip)
                    .stroke(Color.white.opacity(0.10), lineWidth: 1)
            )

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
                .fill(Color.white.opacity(0.06))
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

    // MARK: - Exercise Levels Section

    @ViewBuilder
    private var exerciseLevelsSection: some View {
        if let levels = viewModel.exerciseLevels, !levels.isEmpty {
            VStack(alignment: .leading, spacing: AppSpacing.sm) {
                sectionHeader("Exercise Levels", icon: .boltFill)

                LazyVGrid(
                    columns: [
                        GridItem(.flexible(), spacing: AppSpacing.sm),
                        GridItem(.flexible(), spacing: AppSpacing.sm),
                    ],
                    spacing: AppSpacing.sm
                ) {
                    ForEach(levels) { info in
                        ExerciseLevelCell(info: info)
                    }
                }
            }
        }
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
                value: formatLargeNumber(stats.totalActivityXp),
                label: "Activity XP",
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
                    .fill(Color.white.opacity(0.05))
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
                        .fill(Color.black.opacity(0.45))
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
                .foregroundStyle(DashboardWidgetChrome.labelPrimary)
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
                .foregroundStyle(DashboardWidgetChrome.labelPrimary)
        }
        .padding(.horizontal, AppSpacing.md)
        .padding(.vertical, AppSpacing.xs)
        .background(Color.white.opacity(0.06), in: Capsule())
        .overlay(
            Capsule()
                .stroke(Color.white.opacity(0.10), lineWidth: 1)
        )
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
                .foregroundStyle(DashboardWidgetChrome.labelSecondary)
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
                    .foregroundStyle(DashboardWidgetChrome.labelPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)

                Text(label)
                    .font(AppTypography.caption2)
                    .foregroundStyle(DashboardWidgetChrome.labelSecondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
            }
            .frame(maxWidth: .infinity)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(label): \(value)")
        }
    }
}

// MARK: - ExerciseLevelCell

/// Compact card displaying the level and XP progress for a single exercise type.
struct ExerciseLevelCell: View {

    let info: ExerciseLevelInfo

    private var workoutType: WorkoutType? { info.workoutType }
    private var displayName: String { workoutType?.displayName ?? info.exerciseTypeId }
    private var icon: AppIcon { workoutType?.icon ?? .figureStrengthTraining }
    private var accentColor: Color { workoutType?.accentColor ?? AppColors.primary }

    var body: some View {
        Card(padding: AppSpacing.sm) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    ZStack {
                        Circle()
                            .fill(accentColor.opacity(0.15))
                            .frame(width: 32, height: 32)

                        Image(systemName: icon.rawValue)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(accentColor)
                    }

                    VStack(alignment: .leading, spacing: 1) {
                        Text(displayName)
                            .font(AppTypography.caption1)
                            .foregroundStyle(DashboardWidgetChrome.labelPrimary)
                            .lineLimit(1)

                        Text("Lv. \(info.level)")
                            .font(.system(size: 18, weight: .bold, design: .rounded))
                            .foregroundStyle(accentColor)
                    }

                    Spacer()
                }

                ExerciseLevelProgressBar(progress: info.levelProgress, tint: accentColor)

                HStack {
                    Text("\(info.xpIntoLevel) / \(info.xpRequiredForNextLevel) XP")
                        .font(AppTypography.caption2)
                        .foregroundStyle(DashboardWidgetChrome.labelSecondary)

                    Spacer()
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(displayName), Level \(info.level). \(info.xpIntoLevel) of \(info.xpRequiredForNextLevel) XP.")
    }
}

// MARK: - ExerciseLevelProgressBar

/// Thin rounded progress bar with a configurable tint color for exercise level cells.
struct ExerciseLevelProgressBar: View {

    let progress: Double
    let tint: Color

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(tint.opacity(0.15))
                    .frame(height: 6)

                Capsule()
                    .fill(tint)
                    .frame(
                        width: max(0, geo.size.width * CGFloat(min(progress, 1.0))),
                        height: 6
                    )
                    .animation(.easeInOut(duration: 0.4), value: progress)
            }
        }
        .frame(height: 6)
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
