import SwiftUI

// MARK: - SyncIndicator

/// Navigation bar button that displays the current sync status.
///
/// **Visual states**
/// | SyncState   | Icon                              | Animation            | Badge |
/// |-------------|-----------------------------------|----------------------|-------|
/// | `.idle`     | Cloud with subtle shimmer         | Gentle light sweep   | No    |
/// | `.syncing`  | Animated bars inside tinted cloud | Continuous motion    | No    |
/// | `.success`  | Green cloud with check accent     | Scale pop + soft glow| No    |
/// | `.error`    | Exclamation triangle (red)        | None                 | No    |
/// | `.offline`  | Wi-Fi slash (gray)                | None                 | No    |
///
/// When `unsyncedCount > 0`, a red badge is overlaid on the icon showing the
/// number of workouts waiting to be synced (e.g. "3").
///
/// Tapping the indicator triggers a manual sync via `SyncService.syncNow()`.
///
/// **Animation note**
/// The rotation animation is driven by `isRotating` which is set in both
/// `.onAppear` (for the initial render) and `.onChange` (for subsequent state
/// changes). Without the `.onAppear` call, the animation would never start if
/// the view is first rendered while the state is already `.syncing`.
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

    @ObservedObject private var syncService    = SyncService.shared

    /// Controls the scale-pop animation for the success state.
    @State private var showSuccessScale: Bool = false
    @State private var showSuccessGlow: Bool = false

    var body: some View {
        Button {
            Task { await syncService.syncNow() }
        } label: {
            ZStack(alignment: .topTrailing) {
                syncIcon
                    .font(.system(size: 18, weight: .medium))
                    .frame(width: 32, height: 32)
                    .contentShape(Rectangle())

                // Unsynced count badge -- hidden while actively syncing to
                // avoid visual clutter alongside the spinning icon.
                if syncService.unsyncedCount > 0 && syncService.syncState != .syncing {
                    unsyncedBadge
                }
            }
        }
        .buttonStyle(.plain)
        .disabled(syncService.isSyncing)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityHint("Double tap to sync now")
        // Seed animation state on first render so the rotation starts
        // immediately if the view appears while already syncing.
        .onAppear {
            handleStateChange(syncService.syncState)
        }
        // Update animation state on subsequent state transitions.
        .onChange(of: syncService.syncState) { _, newState in
            handleStateChange(newState)
        }
    }

    // MARK: - Sync Icon

    @ViewBuilder
    private var syncIcon: some View {
        switch syncService.syncState {
        case .idle:
            shimmerCloudIcon(
                baseColors: [
                    AppColors.textSecondary.opacity(0.82),
                    AppColors.primary.opacity(0.42)
                ]
            )

        case .syncing:
            ZStack {
                Image(icon: .cloudFill)
                    .foregroundStyle(
                        LinearGradient(
                            colors: [
                                AppColors.primary.opacity(0.28),
                                AppColors.primaryVariant.opacity(0.22)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )

                MotionLoadingIndicator(
                    tint: AppColors.primary,
                    lineCount: 3,
                    lineWidth: 2.2,
                    height: 10,
                    speed: 1.1
                )
                .frame(width: 14, height: 10)
                .offset(y: 1)
            }

        case .success:
            cloudStatusIcon(
                baseColors: [
                    AppColors.success.opacity(0.92),
                    AppColors.primaryVariant.opacity(0.55)
                ],
                accentBackground: AppColors.success,
                accentForeground: .white,
                accentIcon: .checkmark
            )
                .scaleEffect(showSuccessScale ? 1.2 : 1.0)
                .shadow(
                    color: AppColors.success.opacity(showSuccessGlow ? 0.45 : 0.18),
                    radius: showSuccessGlow ? 10 : 4
                )
                .animation(
                    .spring(response: 0.3, dampingFraction: 0.5),
                    value: showSuccessScale
                )
                .animation(.easeOut(duration: 0.35), value: showSuccessGlow)

        case .error:
            Image(icon: .exclamationmarkTriangle)
                .foregroundStyle(AppColors.error)

        case .offline:
            Image(icon: .wifiSlash)
                .foregroundStyle(AppColors.textSecondary)
        }
    }

    private func shimmerCloudIcon(baseColors: [Color]) -> some View {
        ZStack {
            Image(icon: .cloudFill)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(
                    LinearGradient(
                        colors: baseColors,
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            ShimmerSweep()
                .mask {
                    Image(icon: .cloudFill)
                }
                .blendMode(.screen)
        }
    }

    private func cloudStatusIcon(
        baseColors: [Color],
        accentBackground: Color,
        accentForeground: Color,
        accentIcon: AppIcon
    ) -> some View {
        ZStack(alignment: .bottomTrailing) {
            Image(icon: .cloudFill)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(
                    LinearGradient(
                        colors: baseColors,
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            ZStack {
                Circle()
                    .fill(accentBackground)

                Image(icon: accentIcon)
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(accentForeground)
            }
            .frame(width: 13, height: 13)
            .offset(x: 2, y: 1)
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

    /// Updates local animation state in response to a `SyncState` change.
    ///
    /// Called from both `.onAppear` and `.onChange` so that the animation
    /// is correctly seeded on first render and on all subsequent transitions.
    private func handleStateChange(_ state: SyncState) {
        switch state {
        case .syncing:
            showSuccessScale = false
            showSuccessGlow = false

        case .success:
            showSuccessScale = true
            showSuccessGlow = true
            // Reset scale after the spring animation settles (~0.5 s).
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                showSuccessScale = false
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) {
                showSuccessGlow = false
            }

        case .idle, .error, .offline:
            showSuccessScale = false
            showSuccessGlow = false
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

private struct ShimmerSweep: View {
    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30, paused: false)) { timeline in
            let time = timeline.date.timeIntervalSinceReferenceDate
            let cycle = time.truncatingRemainder(dividingBy: 2.6) / 2.6
            let phase = CGFloat(cycle) * 2.2 - 1.1

            LinearGradient(
                stops: [
                    .init(color: .clear, location: 0.0),
                    .init(color: Color.white.opacity(0.0), location: 0.34),
                    .init(color: Color.white.opacity(0.62), location: 0.5),
                    .init(color: Color.white.opacity(0.0), location: 0.66),
                    .init(color: .clear, location: 1.0)
                ],
                startPoint: UnitPoint(x: phase, y: 0.1),
                endPoint: UnitPoint(x: phase + 0.55, y: 0.9)
            )
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
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
