import SwiftUI

// MARK: - SyncIndicator

/// Navigation bar button that displays the current sync status.
///
/// **Visual states**
/// | SyncState   | Icon                          | Animation       | Badge |
/// |-------------|-------------------------------|-----------------|-------|
/// | `.idle`     | Cloud icon (subtle)           | None            | No    |
/// | `.syncing`  | Rotating arrows               | Continuous spin | No    |
/// | `.success`  | Checkmark circle (green)      | Scale pop       | No    |
/// | `.error`    | Exclamation triangle (red)    | Shake           | No    |
/// | `.offline`  | Wi-Fi slash (gray)            | None            | No    |
///
/// When `unsyncedCount > 0`, a red badge is overlaid on the icon showing the
/// number of workouts waiting to be synced (e.g. "3").
///
/// Tapping the indicator triggers a manual sync via `SyncService.syncNow()`.
///
/// **Usage**
/// Place in a toolbar:
/// ```swift
/// .toolbar {
///     ToolbarItem(placement: .navigationBarTrailing) {
///         SyncIndicator()
///     }
/// }
/// ```
struct SyncIndicator: View {

    @ObservedObject private var syncService = SyncService.shared
    @ObservedObject private var networkMonitor = NetworkMonitor.shared

    /// Controls the continuous rotation animation for the syncing state.
    @State private var isRotating: Bool = false

    /// Controls the scale-pop animation for the success state.
    @State private var showSuccessScale: Bool = false

    var body: some View {
        Button {
            Task { await syncService.syncNow() }
        } label: {
            ZStack(alignment: .topTrailing) {
                syncIcon
                    .font(.system(size: 18, weight: .medium))
                    .frame(width: 32, height: 32)
                    .contentShape(Rectangle())

                // Unsynced count badge
                if syncService.unsyncedCount > 0 && syncService.syncState != .syncing {
                    unsyncedBadge
                }
            }
        }
        .buttonStyle(.plain)
        .disabled(syncService.isSyncing)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityHint("Double tap to sync now")
        .onChange(of: syncService.syncState) { newState in
            handleStateChange(newState)
        }
    }

    // MARK: - Sync Icon

    @ViewBuilder
    private var syncIcon: some View {
        switch syncService.syncState {
        case .idle:
            Image(icon: .cloudFill)
                .foregroundStyle(AppColors.textTertiary)

        case .syncing:
            Image(icon: .arrowTriangle2Circlepath)
                .foregroundStyle(AppColors.primary)
                .rotationEffect(.degrees(isRotating ? 360 : 0))
                .animation(
                    .linear(duration: 1.0).repeatForever(autoreverses: false),
                    value: isRotating
                )

        case .success:
            Image(icon: .checkmarkCircleFill)
                .foregroundStyle(AppColors.success)
                .scaleEffect(showSuccessScale ? 1.2 : 1.0)
                .animation(.spring(response: 0.3, dampingFraction: 0.5), value: showSuccessScale)

        case .error:
            Image(icon: .exclamationmarkTriangle)
                .foregroundStyle(AppColors.error)

        case .offline:
            Image(icon: .wifiSlash)
                .foregroundStyle(AppColors.textSecondary)
        }
    }

    // MARK: - Unsynced Badge

    private var unsyncedBadge: some View {
        Text("\(syncService.unsyncedCount)")
            .font(.system(size: 10, weight: .bold))
            .foregroundStyle(.white)
            .padding(.horizontal, 4)
            .padding(.vertical, 1)
            .background(AppColors.error, in: Capsule())
            .offset(x: 6, y: -4)
            .transition(.scale.combined(with: .opacity))
            .accessibilityLabel("\(syncService.unsyncedCount) workouts not synced")
    }

    // MARK: - State Change Handler

    private func handleStateChange(_ state: SyncState) {
        switch state {
        case .syncing:
            isRotating = true
            showSuccessScale = false

        case .success:
            isRotating = false
            showSuccessScale = true
            // Reset scale after animation completes.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                showSuccessScale = false
            }

        case .idle, .error, .offline:
            isRotating = false
            showSuccessScale = false
        }
    }

    // MARK: - Accessibility

    private var accessibilityLabel: String {
        switch syncService.syncState {
        case .idle:
            if syncService.unsyncedCount > 0 {
                return "\(syncService.unsyncedCount) workouts not yet synced"
            }
            return "Sync status: up to date"
        case .syncing:
            return "Syncing data"
        case .success:
            return "Sync completed successfully"
        case .error(let message):
            return "Sync error: \(message)"
        case .offline:
            return "Device is offline"
        }
    }
}

// MARK: - SyncIndicatorToolbarItem

/// Convenience toolbar content that places a `SyncIndicator` in the
/// navigation bar trailing position.
///
/// Usage:
/// ```swift
/// .toolbar { SyncIndicatorToolbarItem() }
/// ```
struct SyncIndicatorToolbarItem: ToolbarContent {

    var body: some ToolbarContent {
        ToolbarItem(placement: .navigationBarTrailing) {
            SyncIndicator()
        }
    }
}

// MARK: - Previews

#if DEBUG
#Preview("SyncIndicator - States") {
    NavigationStack {
        List {
            Text("Idle state")
            Text("Syncing state")
            Text("Success state")
            Text("Error state")
            Text("Offline state")
        }
        .navigationTitle("Sync Demo")
        .toolbar {
            SyncIndicatorToolbarItem()
        }
    }
}
#endif
