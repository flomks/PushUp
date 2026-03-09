import SwiftUI

// MARK: - SettingsView

/// Settings screen for the PushUp app.
///
/// Follows the standard iOS grouped-list settings style with section headers
/// and footers. All preferences are persisted via `UserDefaults` in the
/// `SettingsViewModel` and survive app restarts.
///
/// The selected `AppearanceMode` is applied at the root level via
/// `.preferredColorScheme()` so it affects the entire app.
///
/// **Sections**
/// 1. Data Sync -- sync status, unsynced count badge, manual sync button (Task 3.14)
/// 2. Time Credit -- push-ups/min stepper, quality multiplier, daily limit
/// 3. Camera -- front/back preference, pose overlay toggle
/// 4. Notifications -- enable toggle, daily reminder time picker
/// 5. Feedback -- haptic feedback, sound effects
/// 6. Appearance -- system / light / dark mode picker
/// 7. Info -- time-credit formula explanation
/// 8. About -- version, build, privacy, terms, support links
struct SettingsView: View {

    @StateObject private var viewModel = SettingsViewModel()
    @ObservedObject private var syncService = SyncService.shared
    @ObservedObject private var networkMonitor = NetworkMonitor.shared

    /// Controls the daily credit limit picker sheet.
    @State private var showDailyLimitPicker = false

    /// Controls the notification time picker sheet.
    @State private var showNotificationTimePicker = false

    /// Controls the time-credit formula info sheet.
    @State private var showFormulaInfo = false

    private var showError: Binding<Bool> {
        Binding(
            get: { viewModel.errorMessage != nil },
            set: { if !$0 { viewModel.clearError() } }
        )
    }

    var body: some View {
        List {
            syncSection
            timeCreditSection
            cameraSection
            notificationsSection
            feedbackSection
            appearanceSection
            infoSection
            aboutSection
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.large)
        .task { await viewModel.refreshNotificationStatus() }
        .alert("Error", isPresented: showError) {
            Button("OK", role: .cancel) { viewModel.clearError() }
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
        .sheet(isPresented: $showDailyLimitPicker) {
            DailyLimitPickerSheet(viewModel: viewModel)
        }
        .sheet(isPresented: $showNotificationTimePicker) {
            NotificationTimePickerSheet(viewModel: viewModel)
        }
        .sheet(isPresented: $showFormulaInfo) {
            TimeCreditFormulaSheet()
        }
    }

    // MARK: - Sync Section

    private var syncSection: some View {
        Section {
            // Sync status row
            HStack(spacing: AppSpacing.sm) {
                SettingsIconView(icon: .arrowTriangle2Circlepath, color: AppColors.primary)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Sync Status")
                        .font(AppTypography.body)
                        .foregroundStyle(AppColors.textPrimary)

                    Text(syncStatusLabel)
                        .font(AppTypography.caption1)
                        .foregroundStyle(syncStatusColor)
                }

                Spacer()

                syncStatusIcon
            }
            .padding(.vertical, AppSpacing.xxs)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Sync status: \(syncStatusLabel)")

            // Unsynced workouts row (only shown when count > 0)
            if syncService.unsyncedCount > 0 {
                HStack(spacing: AppSpacing.sm) {
                    SettingsIconView(icon: .icloudAndArrowUp, color: .orange)

                    Text("Unsynced Workouts")
                        .font(AppTypography.body)
                        .foregroundStyle(AppColors.textPrimary)

                    Spacer()

                    Text("\(syncService.unsyncedCount)")
                        .font(AppTypography.bodySemibold)
                        .foregroundStyle(AppColors.warning)
                        .padding(.horizontal, AppSpacing.xs)
                        .padding(.vertical, AppSpacing.xxs)
                        .background(AppColors.warning.opacity(0.15), in: Capsule())
                }
                .padding(.vertical, AppSpacing.xxs)
                .accessibilityElement(children: .combine)
                .accessibilityLabel("\(syncService.unsyncedCount) workouts not yet synced")
            }

            // Manual sync button
            Button {
                Task { await syncService.syncNow() }
            } label: {
                HStack(spacing: AppSpacing.sm) {
                    SettingsIconView(icon: .arrowClockwise, color: .green)

                    Text("Sync Now")
                        .font(AppTypography.body)
                        .foregroundStyle(AppColors.textPrimary)

                    Spacer()

                    if syncService.isSyncing {
                        ProgressView()
                            .progressViewStyle(.circular)
                            .scaleEffect(0.8)
                    }
                }
                .padding(.vertical, AppSpacing.xxs)
            }
            .buttonStyle(.plain)
            .disabled(syncService.isSyncing || !networkMonitor.isConnected)
            .opacity(syncService.isSyncing || !networkMonitor.isConnected ? 0.5 : 1.0)
            .accessibilityLabel("Sync now")
            .accessibilityHint(networkMonitor.isConnected ? "Double tap to sync data" : "Not available while offline")

        } header: {
            SettingsSectionHeader("Data Sync")
        } footer: {
            Text(syncService.lastSyncLabel)
        }
    }

    /// Human-readable label for the current sync state.
    private var syncStatusLabel: String {
        if !networkMonitor.isConnected {
            return "Offline"
        }
        switch syncService.syncState {
        case .idle:
            return syncService.unsyncedCount > 0 ? "Pending" : "Up to date"
        case .syncing:
            return "Syncing..."
        case .success:
            return "Synced"
        case .error(let message):
            return "Error: \(message)"
        case .offline:
            return "Offline"
        }
    }

    /// Color for the sync status label.
    private var syncStatusColor: Color {
        if !networkMonitor.isConnected { return AppColors.textSecondary }
        switch syncService.syncState {
        case .idle:
            return syncService.unsyncedCount > 0 ? AppColors.warning : AppColors.success
        case .syncing:
            return AppColors.primary
        case .success:
            return AppColors.success
        case .error:
            return AppColors.error
        case .offline:
            return AppColors.textSecondary
        }
    }

    /// Icon for the sync status indicator in the settings row.
    @ViewBuilder
    private var syncStatusIcon: some View {
        switch syncService.syncState {
        case .idle:
            if !networkMonitor.isConnected {
                Image(icon: .wifiSlash)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(AppColors.textSecondary)
            } else if syncService.unsyncedCount > 0 {
                Image(icon: .exclamationmarkArrowTriangle2Circlepath)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(AppColors.warning)
            } else {
                Image(icon: .checkmarkCircleFill)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(AppColors.success)
            }
        case .syncing:
            ProgressView()
                .progressViewStyle(.circular)
                .scaleEffect(0.7)
        case .success:
            Image(icon: .checkmarkCircleFill)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(AppColors.success)
        case .error:
            Image(icon: .exclamationmarkTriangle)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(AppColors.error)
        case .offline:
            Image(icon: .wifiSlash)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(AppColors.textSecondary)
        }
    }

    // MARK: - Time Credit Section

    private var timeCreditSection: some View {
        Section {
            pushUpsPerMinuteRow

            SettingsToggleRow(
                icon: .starFill,
                iconColor: .orange,
                title: "Quality Multiplier",
                subtitle: "Form score scales earned credit",
                isOn: $viewModel.qualityMultiplierEnabled
            )

            dailyCreditLimitRow

        } header: {
            SettingsSectionHeader("Time Credit")
        } footer: {
            Text("Each push-up earns \(Self.formatCreditPerRep(viewModel.pushUpsPerMinute)) seconds of time credit at the configured rate.")
        }
    }

    private var pushUpsPerMinuteRow: some View {
        HStack(spacing: AppSpacing.sm) {
            SettingsIconView(icon: .figureStrengthTraining, color: AppColors.primary)

            VStack(alignment: .leading, spacing: 2) {
                Text("Push-Ups per Minute")
                    .font(AppTypography.body)
                    .foregroundStyle(AppColors.textPrimary)
                Text("Used to calculate time credit")
                    .font(AppTypography.caption1)
                    .foregroundStyle(AppColors.textSecondary)
            }

            Spacer()

            HStack(spacing: AppSpacing.xs) {
                Button {
                    viewModel.decrementPushUpsPerMinute()
                } label: {
                    Image(icon: .minus)
                        .font(.system(size: 14, weight: .semibold))
                        .frame(width: 28, height: 28)
                        .background(AppColors.backgroundTertiary)
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .disabled(viewModel.pushUpsPerMinute <= SettingsViewModel.pushUpsPerMinuteRange.lowerBound)
                .accessibilityLabel("Decrease push-ups per minute")

                Text("\(viewModel.pushUpsPerMinute)")
                    .font(AppTypography.bodySemibold)
                    .foregroundStyle(AppColors.textPrimary)
                    .monospacedDigit()
                    .frame(minWidth: 28, alignment: .center)
                    .accessibilityLabel("\(viewModel.pushUpsPerMinute) push-ups per minute")

                Button {
                    viewModel.incrementPushUpsPerMinute()
                } label: {
                    Image(icon: .plus)
                        .font(.system(size: 14, weight: .semibold))
                        .frame(width: 28, height: 28)
                        .background(AppColors.backgroundTertiary)
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .disabled(viewModel.pushUpsPerMinute >= SettingsViewModel.pushUpsPerMinuteRange.upperBound)
                .accessibilityLabel("Increase push-ups per minute")
            }
        }
        .padding(.vertical, AppSpacing.xxs)
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private var dailyCreditLimitRow: some View {
        HStack(spacing: AppSpacing.sm) {
            SettingsIconView(icon: .clockBadgePlus, color: .purple)

            VStack(alignment: .leading, spacing: 2) {
                Text("Daily Credit Limit")
                    .font(AppTypography.body)
                    .foregroundStyle(AppColors.textPrimary)
                Text("Maximum credit earned per day")
                    .font(AppTypography.caption1)
                    .foregroundStyle(AppColors.textSecondary)
            }

            Spacer()

            Toggle("", isOn: Binding(
                get: { viewModel.dailyCreditLimitEnabled },
                set: { viewModel.dailyCreditLimitEnabled = $0 }
            ))
            .labelsHidden()
            .tint(AppColors.primary)
        }
        .padding(.vertical, AppSpacing.xxs)
        .contentShape(Rectangle())

        if viewModel.dailyCreditLimitEnabled {
            Button {
                showDailyLimitPicker = true
            } label: {
                HStack {
                    Text("Limit")
                        .font(AppTypography.body)
                        .foregroundStyle(AppColors.textPrimary)
                    Spacer()
                    Text(Self.formatMinutes(viewModel.dailyCreditLimit ?? 60))
                        .font(AppTypography.body)
                        .foregroundStyle(AppColors.textSecondary)
                    Image(icon: .chevronRight)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(AppColors.textTertiary)
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Daily credit limit: \(Self.formatMinutes(viewModel.dailyCreditLimit ?? 60))")
        }
    }

    // MARK: - Camera Section

    private var cameraSection: some View {
        Section {
            Picker(selection: Binding(
                get: { viewModel.cameraPosition },
                set: { viewModel.cameraPosition = $0 }
            )) {
                ForEach(LensSide.allCases) { position in
                    Label(position.label, icon: position.icon)
                        .tag(position)
                }
            } label: {
                HStack(spacing: AppSpacing.sm) {
                    SettingsIconView(icon: .camera, color: .gray)
                    Text("Camera")
                        .font(AppTypography.body)
                        .foregroundStyle(AppColors.textPrimary)
                }
            }
            .pickerStyle(.navigationLink)

            SettingsToggleRow(
                icon: .eye,
                iconColor: .teal,
                title: "Pose Overlay",
                subtitle: "Show skeleton during workout",
                isOn: $viewModel.poseOverlayEnabled
            )

        } header: {
            SettingsSectionHeader("Camera")
        }
    }

    // MARK: - Notifications Section

    private var notificationsSection: some View {
        Section {
            HStack(spacing: AppSpacing.sm) {
                SettingsIconView(icon: .bellFill, color: .red)

                Text("Notifications")
                    .font(AppTypography.body)
                    .foregroundStyle(AppColors.textPrimary)

                Spacer()

                if viewModel.isRequestingNotificationPermission {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .scaleEffect(0.8)
                } else {
                    Toggle("", isOn: Binding(
                        get: { viewModel.notificationsEnabled },
                        set: { newValue in
                            Task { await viewModel.handleNotificationsToggle(newValue) }
                        }
                    ))
                    .labelsHidden()
                    .tint(AppColors.primary)
                }
            }
            .padding(.vertical, AppSpacing.xxs)

            if viewModel.notificationsEnabled {
                Button {
                    showNotificationTimePicker = true
                } label: {
                    HStack(spacing: AppSpacing.sm) {
                        SettingsIconView(icon: .clock, color: .blue)

                        Text("Daily Reminder")
                            .font(AppTypography.body)
                            .foregroundStyle(AppColors.textPrimary)

                        Spacer()

                        Text(viewModel.notificationTimeLabel)
                            .font(AppTypography.body)
                            .foregroundStyle(AppColors.textSecondary)

                        Image(icon: .chevronRight)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(AppColors.textTertiary)
                    }
                    .padding(.vertical, AppSpacing.xxs)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Daily reminder at \(viewModel.notificationTimeLabel)")
            }

        } header: {
            SettingsSectionHeader("Notifications")
        } footer: {
            if viewModel.notificationAuthorizationStatus == .denied {
                Text("Notifications are disabled in iOS Settings. Tap to open Settings.")
                    .foregroundStyle(AppColors.warning)
            }
        }
    }

    // MARK: - Feedback Section

    private var feedbackSection: some View {
        Section {
            SettingsToggleRow(
                icon: .handTap,
                iconColor: .indigo,
                title: "Haptic Feedback",
                subtitle: "Vibrate on rep detection",
                isOn: $viewModel.hapticFeedbackEnabled
            )

            SettingsToggleRow(
                icon: .speakerWave,
                iconColor: .pink,
                title: "Sound Effects",
                subtitle: "Audio cues during workout",
                isOn: $viewModel.soundEffectsEnabled
            )

        } header: {
            SettingsSectionHeader("Feedback")
        }
    }

    // MARK: - Appearance Section

    private var appearanceSection: some View {
        Section {
            Picker(selection: Binding(
                get: { viewModel.appearanceMode },
                set: { viewModel.appearanceMode = $0 }
            )) {
                ForEach(AppearanceMode.allCases) { mode in
                    Label(mode.label, icon: mode.icon)
                        .tag(mode)
                }
            } label: {
                HStack(spacing: AppSpacing.sm) {
                    SettingsIconView(icon: .circleHalfFilled, color: .gray)
                    Text("Appearance")
                        .font(AppTypography.body)
                        .foregroundStyle(AppColors.textPrimary)
                }
            }
            .pickerStyle(.navigationLink)

        } header: {
            SettingsSectionHeader("Appearance")
        } footer: {
            Text("\"System\" follows your iOS appearance setting.")
        }
    }

    // MARK: - Info Section

    private var infoSection: some View {
        Section {
            Button {
                showFormulaInfo = true
            } label: {
                HStack(spacing: AppSpacing.sm) {
                    SettingsIconView(icon: .infoCircleFill, color: AppColors.primary)

                    Text("Time Credit Formula")
                        .font(AppTypography.body)
                        .foregroundStyle(AppColors.textPrimary)

                    Spacer()

                    Image(icon: .chevronRight)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(AppColors.textTertiary)
                }
                .padding(.vertical, AppSpacing.xxs)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Time credit formula information")

        } header: {
            SettingsSectionHeader("Info")
        } footer: {
            Text("Learn how push-ups are converted into screen time credit.")
        }
    }

    // MARK: - About Section

    private var aboutSection: some View {
        Section {
            HStack(spacing: AppSpacing.sm) {
                SettingsIconView(icon: .gearshapeFill, color: .gray)

                Text("Version")
                    .font(AppTypography.body)
                    .foregroundStyle(AppColors.textPrimary)

                Spacer()

                Text(AppInfo.versionString)
                    .font(AppTypography.body)
                    .foregroundStyle(AppColors.textSecondary)
            }
            .padding(.vertical, AppSpacing.xxs)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("App version \(AppInfo.versionString)")

            SettingsLinkRow(
                icon: .shieldFill,
                iconColor: .blue,
                title: "Privacy Policy",
                url: AppInfo.privacyPolicyURL
            )

            SettingsLinkRow(
                icon: .docText,
                iconColor: .gray,
                title: "Terms of Service",
                url: AppInfo.termsOfServiceURL
            )

            SettingsLinkRow(
                icon: .questionmarkCircle,
                iconColor: .green,
                title: "Support",
                url: AppInfo.supportURL
            )

        } header: {
            SettingsSectionHeader("About")
        }
    }

    // MARK: - Shared Formatters

    /// Formats a minute value into a human-readable duration string.
    /// Shared across the settings screen and its sub-sheets.
    static func formatMinutes(_ minutes: Int) -> String {
        if minutes >= 60 {
            let h = minutes / 60
            let m = minutes % 60
            return m > 0 ? "\(h)h \(m)m" : "\(h)h"
        }
        return "\(minutes) min"
    }

    /// Formats the credit-per-rep value for the section footer.
    private static func formatCreditPerRep(_ pushUpsPerMinute: Int) -> String {
        guard pushUpsPerMinute > 0 else { return "0.0" }
        return String(format: "%.1f", 60.0 / Double(pushUpsPerMinute))
    }
}

// MARK: - SettingsSectionHeader

/// Styled section header matching iOS grouped list style.
private struct SettingsSectionHeader: View {
    let title: String

    init(_ title: String) {
        self.title = title
    }

    var body: some View {
        Text(title)
            .font(AppTypography.caption1)
            .foregroundStyle(AppColors.textSecondary)
            .textCase(.uppercase)
    }
}

// MARK: - SettingsIconView

/// Rounded-square icon used in settings rows (iOS Settings style).
///
/// Matches the native iOS Settings app icon treatment: a coloured rounded
/// rectangle with a white SF Symbol centred inside.
struct SettingsIconView: View {
    let icon: AppIcon
    let color: Color
    var size: CGFloat = 28

    var body: some View {
        Image(systemName: icon.rawValue)
            .font(.system(size: size * 0.5, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(color, in: RoundedRectangle(cornerRadius: size * 0.214))
    }
}

// MARK: - SettingsToggleRow

/// A settings row with an icon, title, optional subtitle, and a toggle.
struct SettingsToggleRow: View {
    let icon: AppIcon
    let iconColor: Color
    let title: String
    var subtitle: String? = nil
    @Binding var isOn: Bool

    var body: some View {
        HStack(spacing: AppSpacing.sm) {
            SettingsIconView(icon: icon, color: iconColor)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(AppTypography.body)
                    .foregroundStyle(AppColors.textPrimary)

                if let subtitle {
                    Text(subtitle)
                        .font(AppTypography.caption1)
                        .foregroundStyle(AppColors.textSecondary)
                }
            }

            Spacer()

            Toggle("", isOn: $isOn)
                .labelsHidden()
                .tint(AppColors.primary)
        }
        .padding(.vertical, AppSpacing.xxs)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title)\(subtitle.map { ", \($0)" } ?? "")")
        .accessibilityValue(isOn ? "On" : "Off")
        .accessibilityAddTraits(.isButton)
    }
}

// MARK: - SettingsLinkRow

/// A settings row that opens a URL in Safari.
private struct SettingsLinkRow: View {
    let icon: AppIcon
    let iconColor: Color
    let title: String
    let url: URL

    var body: some View {
        Link(destination: url) {
            HStack(spacing: AppSpacing.sm) {
                SettingsIconView(icon: icon, color: iconColor)

                Text(title)
                    .font(AppTypography.body)
                    .foregroundStyle(AppColors.textPrimary)

                Spacer()

                Image(icon: .arrowUpRight)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(AppColors.textTertiary)
            }
            .padding(.vertical, AppSpacing.xxs)
        }
        .accessibilityLabel("\(title), opens in browser")
    }
}

// MARK: - DailyLimitPickerSheet

/// Bottom sheet for selecting the daily credit limit in minutes.
private struct DailyLimitPickerSheet: View {
    @ObservedObject var viewModel: SettingsViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                ForEach(SettingsViewModel.dailyCreditLimitOptions, id: \.self) { minutes in
                    Button {
                        viewModel.dailyCreditLimit = minutes
                        dismiss()
                    } label: {
                        HStack {
                            Text(SettingsView.formatMinutes(minutes))
                                .font(AppTypography.body)
                                .foregroundStyle(AppColors.textPrimary)

                            Spacer()

                            if viewModel.dailyCreditLimit == minutes {
                                Image(icon: .checkmark)
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundStyle(AppColors.primary)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(SettingsView.formatMinutes(minutes))
                    .accessibilityAddTraits(viewModel.dailyCreditLimit == minutes ? .isSelected : [])
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Daily Credit Limit")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium])
    }
}

// MARK: - NotificationTimePickerSheet

/// Bottom sheet for selecting the daily reminder time.
private struct NotificationTimePickerSheet: View {
    @ObservedObject var viewModel: SettingsViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var selectedTime: Date = Date()

    var body: some View {
        NavigationStack {
            VStack(spacing: AppSpacing.lg) {
                DatePicker(
                    "Reminder Time",
                    selection: $selectedTime,
                    displayedComponents: .hourAndMinute
                )
                .datePickerStyle(.wheel)
                .labelsHidden()
                .padding(.top, AppSpacing.md)

                Spacer()
            }
            .navigationTitle("Daily Reminder")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        viewModel.notificationTime = selectedTime
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
        .presentationDetents([.medium])
        .onAppear {
            selectedTime = viewModel.notificationTime
        }
    }
}

// MARK: - TimeCreditFormulaSheet

/// Informational sheet explaining how time credit is calculated.
private struct TimeCreditFormulaSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: AppSpacing.lg) {

                    // Hero icon
                    HStack {
                        Spacer()
                        Image(icon: .clockBadgePlus)
                            .font(.system(size: 56, weight: .light))
                            .foregroundStyle(AppColors.primary)
                            .symbolRenderingMode(.hierarchical)
                        Spacer()
                    }
                    .padding(.top, AppSpacing.md)

                    VStack(alignment: .leading, spacing: AppSpacing.md) {

                        formulaSection(
                            title: "Basic Formula",
                            content: "Each push-up earns you a fixed amount of screen time based on your configured push-up rate:\n\n  Credit per rep = 60 seconds / Push-Ups per Minute\n\nFor example, at the default rate of 10 push-ups/min, each rep earns 6 seconds."
                        )

                        Divider()

                        formulaSection(
                            title: "Quality Multiplier",
                            content: "When the Quality Multiplier is enabled, your form score (0-100%) scales the earned credit:\n\n  Final credit = Base credit x Form score\n\nPerfect form (100%) earns the full amount. Poor form reduces the credit proportionally, encouraging good technique."
                        )

                        Divider()

                        formulaSection(
                            title: "Daily Limit",
                            content: "You can optionally set a daily credit cap. Once reached, additional push-ups in that day no longer earn credit. The limit resets at midnight."
                        )

                        Divider()

                        formulaSection(
                            title: "Example",
                            content: "Rate: 10 push-ups/min\nReps: 30\nForm score: 80%\n\nBase credit: 30 x 6s = 180s (3 min)\nWith quality: 180s x 0.80 = 144s (2 min 24s)"
                        )
                    }
                }
                .padding(.horizontal, AppSpacing.screenHorizontal)
                .padding(.bottom, AppSpacing.screenVerticalBottom)
            }
            .navigationTitle("Time Credit Formula")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .fontWeight(.semibold)
                }
            }
        }
    }

    private func formulaSection(title: String, content: String) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.xs) {
            Text(title)
                .font(AppTypography.headline)
                .foregroundStyle(AppColors.textPrimary)

            Text(content)
                .font(AppTypography.body)
                .foregroundStyle(AppColors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK: - Previews

#if DEBUG
#Preview("SettingsView") {
    NavigationStack {
        SettingsView()
    }
}

#Preview("SettingsView - Dark") {
    NavigationStack {
        SettingsView()
    }
    .preferredColorScheme(.dark)
}

#Preview("SettingsIconView") {
    HStack(spacing: AppSpacing.md) {
        SettingsIconView(icon: .bellFill, color: .red)
        SettingsIconView(icon: .camera, color: .gray)
        SettingsIconView(icon: .starFill, color: .orange)
        SettingsIconView(icon: .shieldFill, color: .blue)
    }
    .padding()
    .background(AppColors.backgroundPrimary)
}

#Preview("TimeCreditFormulaSheet") {
    TimeCreditFormulaSheet()
}
#endif
