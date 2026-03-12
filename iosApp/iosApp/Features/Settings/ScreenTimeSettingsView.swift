import SwiftUI
import FamilyControls

// MARK: - ScreenTimeSettingsView

/// Full-screen settings view for Screen Time / App Blocking configuration.
///
/// Presented as a navigation destination from the Settings screen.
///
/// **Sections**
/// 1. Authorization -- request / revoke FamilyControls permission
/// 2. App Selection -- FamilyActivityPicker to choose which apps to block
/// 3. Blocking Status -- current shield state, manual override
/// 4. How It Works -- explanation card
struct ScreenTimeSettingsView: View {

    @ObservedObject private var manager = ScreenTimeManager.shared

    /// Controls the FamilyActivityPicker sheet.
    @State private var showAppPicker = false

    /// Local copy of the selection for the picker binding.
    @State private var pickerSelection = FamilyActivitySelection()

    /// Controls the revoke confirmation dialog.
    @State private var showRevokeConfirmation = false

    private var showError: Binding<Bool> {
        Binding(
            get: { manager.errorMessage != nil },
            set: { if !$0 { manager.clearError() } }
        )
    }

    var body: some View {
        List {
            authorizationSection
            if manager.authorizationStatus == .authorized {
                appSelectionSection
                blockingStatusSection
            }
            howItWorksSection
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Screen Time")
        .navigationBarTitleDisplayMode(.large)
        .familyActivityPicker(isPresented: $showAppPicker, selection: $pickerSelection)
        .onChange(of: pickerSelection) { newSelection in
            manager.saveSelection(newSelection)
        }
        .onAppear {
            // Sync picker state with persisted selection
            if let saved = manager.activitySelection {
                pickerSelection = saved
            }
        }
        .alert("Error", isPresented: showError) {
            Button("OK", role: .cancel) { manager.clearError() }
        } message: {
            Text(manager.errorMessage ?? "")
        }
        .confirmationDialog(
            "Disable Screen Time?",
            isPresented: $showRevokeConfirmation,
            titleVisibility: .visible
        ) {
            Button("Disable & Remove All Restrictions", role: .destructive) {
                Task { await manager.revokeAuthorization() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will remove all app restrictions and clear your app selection. Your workout history and time credit are not affected.")
        }
    }

    // MARK: - Authorization Section

    private var authorizationSection: some View {
        Section {
            switch manager.authorizationStatus {
            case .notDetermined, .denied:
                // Permission not yet granted -- show request button
                VStack(alignment: .leading, spacing: AppSpacing.sm) {
                    HStack(spacing: AppSpacing.sm) {
                        SettingsIconView(icon: .checkmarkShieldFill, color: AppColors.primary)

                        VStack(alignment: .leading, spacing: 2) {
                            Text("Screen Time Permission")
                                .font(AppTypography.body)
                                .foregroundStyle(AppColors.textPrimary)
                            Text(manager.authorizationStatus == .denied
                                 ? "Permission denied -- tap to open Settings"
                                 : "Required to block apps")
                                .font(AppTypography.caption1)
                                .foregroundStyle(manager.authorizationStatus == .denied
                                                 ? AppColors.error
                                                 : AppColors.textSecondary)
                        }

                        Spacer()

                        if manager.isRequestingAuthorization {
                            ProgressView()
                                .progressViewStyle(.circular)
                                .scaleEffect(0.8)
                        } else {
                            Image(icon: .chevronRight)
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(AppColors.textTertiary)
                        }
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        if manager.authorizationStatus == .denied {
                            openSystemSettings()
                        } else {
                            Task { await manager.requestAuthorization() }
                        }
                    }
                }
                .padding(.vertical, AppSpacing.xxs)

            case .authorized:
                // Permission granted -- show status + revoke option
                HStack(spacing: AppSpacing.sm) {
                    SettingsIconView(icon: .checkmarkShieldFill, color: AppColors.success)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Screen Time Permission")
                            .font(AppTypography.body)
                            .foregroundStyle(AppColors.textPrimary)
                        Text("Authorized")
                            .font(AppTypography.caption1)
                            .foregroundStyle(AppColors.success)
                    }

                    Spacer()

                    Button("Disable") {
                        showRevokeConfirmation = true
                    }
                    .font(AppTypography.caption1)
                    .foregroundStyle(AppColors.error)
                    .buttonStyle(.plain)
                }
                .padding(.vertical, AppSpacing.xxs)

            case .unavailable:
                HStack(spacing: AppSpacing.sm) {
                    SettingsIconView(icon: .xmarkShieldFill, color: AppColors.textSecondary)
                    Text("Screen Time is not available on this device.")
                        .font(AppTypography.body)
                        .foregroundStyle(AppColors.textSecondary)
                }
                .padding(.vertical, AppSpacing.xxs)
            }

        } header: {
            SettingsSectionHeader("Permission")
        } footer: {
            if manager.authorizationStatus == .notDetermined {
                Text("PushUp needs Screen Time permission to block selected apps when your time credit runs out.")
            }
        }
    }

    // MARK: - App Selection Section

    private var appSelectionSection: some View {
        Section {
            // App picker button
            Button {
                showAppPicker = true
            } label: {
                HStack(spacing: AppSpacing.sm) {
                    SettingsIconView(icon: .appBadgeFill, color: .purple)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Select Apps to Block")
                            .font(AppTypography.body)
                            .foregroundStyle(AppColors.textPrimary)
                        Text(selectionSummary)
                            .font(AppTypography.caption1)
                            .foregroundStyle(AppColors.textSecondary)
                    }

                    Spacer()

                    Image(icon: .chevronRight)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(AppColors.textTertiary)
                }
                .padding(.vertical, AppSpacing.xxs)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Select apps to block. \(selectionSummary)")

            // Today's App Usage -- navigates to per-app detail view
            if hasSelection {
                NavigationLink {
                    ScreenTimeAppDetailView()
                } label: {
                    HStack(spacing: AppSpacing.sm) {
                        SettingsIconView(icon: .hourglassBottomHalf, color: AppColors.info)

                        VStack(alignment: .leading, spacing: 2) {
                            Text("Today's App Usage")
                                .font(AppTypography.body)
                                .foregroundStyle(AppColors.textPrimary)
                            Text("See how long each app was used today")
                                .font(AppTypography.caption1)
                                .foregroundStyle(AppColors.textSecondary)
                        }

                        Spacer()
                    }
                    .padding(.vertical, AppSpacing.xxs)
                }
            }

            // Clear selection button (only shown when selection exists)
            if hasSelection {
                Button(role: .destructive) {
                    manager.clearSelection()
                    pickerSelection = FamilyActivitySelection()
                } label: {
                    HStack(spacing: AppSpacing.sm) {
                        SettingsIconView(icon: .xmarkShieldFill, color: AppColors.error)
                        Text("Clear App Selection")
                            .font(AppTypography.body)
                            .foregroundStyle(AppColors.error)
                    }
                    .padding(.vertical, AppSpacing.xxs)
                }
                .buttonStyle(.plain)
            }

        } header: {
            SettingsSectionHeader("App Selection")
        } footer: {
            Text("Choose which apps and categories are blocked when your time credit reaches zero. Social media, streaming, and games are common choices.")
        }
    }

    // MARK: - Blocking Status Section

    private var blockingStatusSection: some View {
        Section {
            // Current blocking state
            HStack(spacing: AppSpacing.sm) {
                SettingsIconView(
                    icon: manager.isBlocking ? .lockApp : .checkmarkShield,
                    color: manager.isBlocking ? AppColors.error : AppColors.success
                )

                VStack(alignment: .leading, spacing: 2) {
                    Text("App Blocking")
                        .font(AppTypography.body)
                        .foregroundStyle(AppColors.textPrimary)
                    Text(manager.isBlocking ? "Active -- apps are blocked" : "Inactive -- apps are accessible")
                        .font(AppTypography.caption1)
                        .foregroundStyle(manager.isBlocking ? AppColors.error : AppColors.success)
                }

                Spacer()

                // Status indicator dot
                Circle()
                    .fill(manager.isBlocking ? AppColors.error : AppColors.success)
                    .frame(width: 8, height: 8)
            }
            .padding(.vertical, AppSpacing.xxs)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("App blocking is \(manager.isBlocking ? "active" : "inactive")")

            // Manual unblock (emergency override)
            if manager.isBlocking {
                Button {
                    manager.unblockApps()
                } label: {
                    HStack(spacing: AppSpacing.sm) {
                        SettingsIconView(icon: .shieldSlashFill, color: AppColors.warning)
                        Text("Unblock Apps Temporarily")
                            .font(AppTypography.body)
                            .foregroundStyle(AppColors.textPrimary)
                        Spacer()
                    }
                    .padding(.vertical, AppSpacing.xxs)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Unblock apps temporarily")
            }

        } header: {
            SettingsSectionHeader("Status")
        } footer: {
            if manager.isBlocking {
                Text("Apps are currently blocked. Complete a workout to earn more time credit and restore access.")
                    .foregroundStyle(AppColors.warning)
            } else {
                Text("Apps will be blocked automatically when your time credit reaches zero.")
            }
        }
    }

    // MARK: - How It Works Section

    private var howItWorksSection: some View {
        Section {
            VStack(alignment: .leading, spacing: AppSpacing.sm) {
                howItWorksStep(
                    number: "1",
                    title: "Do Push-Ups",
                    description: "Each push-up earns you time credit based on your configured rate."
                )
                Divider()
                howItWorksStep(
                    number: "2",
                    title: "Use Your Apps",
                    description: "Your time credit counts down while you use the selected apps."
                )
                Divider()
                howItWorksStep(
                    number: "3",
                    title: "Credit Runs Out",
                    description: "When credit reaches zero, selected apps are blocked automatically."
                )
                Divider()
                howItWorksStep(
                    number: "4",
                    title: "Earn More",
                    description: "Do another workout to earn more credit and restore access."
                )
            }
            .padding(.vertical, AppSpacing.xxs)

        } header: {
            SettingsSectionHeader("How It Works")
        }
    }

    private func howItWorksStep(number: String, title: String, description: String) -> some View {
        HStack(alignment: .top, spacing: AppSpacing.sm) {
            Text(number)
                .font(AppTypography.captionSemibold)
                .foregroundStyle(AppColors.textOnPrimary)
                .frame(width: 22, height: 22)
                .background(AppColors.primary, in: Circle())

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(AppTypography.bodySemibold)
                    .foregroundStyle(AppColors.textPrimary)
                Text(description)
                    .font(AppTypography.caption1)
                    .foregroundStyle(AppColors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: - Helpers

    private var hasSelection: Bool {
        guard let selection = manager.activitySelection else { return false }
        return !selection.applicationTokens.isEmpty
            || !selection.categoryTokens.isEmpty
            || !selection.webDomainTokens.isEmpty
    }

    private var selectionSummary: String {
        guard let selection = manager.activitySelection else {
            return "No apps selected"
        }
        let appCount = selection.applicationTokens.count
        let catCount = selection.categoryTokens.count
        if appCount == 0 && catCount == 0 {
            return "No apps selected"
        }
        var parts: [String] = []
        if appCount > 0 { parts.append("\(appCount) app\(appCount == 1 ? "" : "s")") }
        if catCount > 0 { parts.append("\(catCount) categor\(catCount == 1 ? "y" : "ies")") }
        return parts.joined(separator: ", ")
    }

    private func openSystemSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }
}

// MARK: - ScreenTimeSettingsRow

/// Compact row for the Settings screen that navigates to ScreenTimeSettingsView.
struct ScreenTimeSettingsRow: View {

    @ObservedObject private var manager = ScreenTimeManager.shared

    var body: some View {
        NavigationLink {
            ScreenTimeSettingsView()
        } label: {
            HStack(spacing: AppSpacing.sm) {
                SettingsIconView(icon: .hourglassFill, color: .purple)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Screen Time & App Blocking")
                        .font(AppTypography.body)
                        .foregroundStyle(AppColors.textPrimary)
                    Text(screenTimeStatusLabel)
                        .font(AppTypography.caption1)
                        .foregroundStyle(screenTimeStatusColor)
                }

                Spacer()

                // Blocking indicator badge
                if manager.isBlocking {
                    Text("Blocking")
                        .font(AppTypography.caption2)
                        .foregroundStyle(AppColors.textOnPrimary)
                        .padding(.horizontal, AppSpacing.xs)
                        .padding(.vertical, 3)
                        .background(AppColors.error, in: Capsule())
                }
            }
            .padding(.vertical, AppSpacing.xxs)
        }
        .accessibilityLabel("Screen Time and App Blocking. \(screenTimeStatusLabel)")
    }

    private var screenTimeStatusLabel: String {
        switch manager.authorizationStatus {
        case .notDetermined: return "Tap to set up"
        case .authorized:
            if manager.isBlocking { return "Apps are currently blocked" }
            if let selection = manager.activitySelection,
               (!selection.applicationTokens.isEmpty || !selection.categoryTokens.isEmpty) {
                return "Active -- monitoring usage"
            }
            return "Authorized -- no apps selected"
        case .denied:        return "Permission denied"
        case .unavailable:   return "Not available"
        }
    }

    private var screenTimeStatusColor: Color {
        switch manager.authorizationStatus {
        case .notDetermined: return AppColors.textSecondary
        case .authorized:    return manager.isBlocking ? AppColors.error : AppColors.success
        case .denied:        return AppColors.error
        case .unavailable:   return AppColors.textSecondary
        }
    }
}

// MARK: - Previews

#if DEBUG
#Preview("ScreenTimeSettingsView - Not Authorized") {
    NavigationStack {
        ScreenTimeSettingsView()
    }
}

#Preview("ScreenTimeSettingsView - Dark") {
    NavigationStack {
        ScreenTimeSettingsView()
    }
    .preferredColorScheme(.dark)
}
#endif
