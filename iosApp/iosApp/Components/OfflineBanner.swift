import SwiftUI

// MARK: - OfflineBanner

/// A non-intrusive banner displayed at the top of the screen when the device
/// has no internet connection.
///
/// **Behaviour**
/// - Slides in from the top with a spring animation when `isConnected` becomes
///   `false`.
/// - Slides out when connectivity is restored.
/// - Shows the number of unsynced workouts if any exist.
/// - Tapping the banner is a no-op (informational only).
///
/// **Design**
/// Uses a warm amber/orange background to indicate a warning state without
/// alarming the user. The message reassures them that data is safe locally
/// and will sync automatically.
///
/// **Animation note**
/// The banner uses `withAnimation` driven by an `@State` flag rather than
/// a conditional `if` branch. A bare `if !isConnected { ... }` causes SwiftUI
/// to destroy and recreate the view on each connectivity change, which
/// prevents the `.transition` from playing. Driving visibility through a
/// boolean `@State` that is updated inside `withAnimation` ensures the
/// enter/exit transitions fire correctly.
///
/// **Usage**
/// Overlay on the main content area:
/// ```swift
/// ZStack(alignment: .top) {
///     MainContent()
///     OfflineBanner()
/// }
/// ```
struct OfflineBanner: View {

    @ObservedObject private var networkMonitor = NetworkMonitor.shared
    @ObservedObject private var syncService    = SyncService.shared

    /// Drives the slide-in / slide-out animation.
    /// Updated inside `withAnimation` whenever `networkMonitor.isConnected` changes.
    @State private var isVisible: Bool = false

    var body: some View {
        VStack(spacing: 0) {
            if isVisible {
                bannerContent
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        // Observe connectivity changes and animate the visibility flag.
        .onChange(of: networkMonitor.isConnected) { connected in
            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                isVisible = !connected
            }
        }
        // Set initial visibility without animation on first render.
        .onAppear {
            isVisible = !networkMonitor.isConnected
        }
    }

    // MARK: - Banner Content

    private var bannerContent: some View {
        HStack(spacing: AppSpacing.sm) {
            Image(icon: .wifiSlash)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.white)

            VStack(alignment: .leading, spacing: 2) {
                Text("No Internet Connection")
                    .font(AppTypography.captionSemibold)
                    .foregroundStyle(.white)

                Text(subtitleText)
                    .font(AppTypography.caption2)
                    .foregroundStyle(.white.opacity(0.85))
            }

            Spacer()

            if syncService.unsyncedCount > 0 {
                unsyncedBadge
            }
        }
        .padding(.horizontal, AppSpacing.screenHorizontal)
        .padding(.vertical, AppSpacing.xs + 2)
        .background(bannerBackground)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
    }

    // MARK: - Subtitle

    private var subtitleText: String {
        if syncService.unsyncedCount > 0 {
            let workoutWord = syncService.unsyncedCount == 1 ? "workout" : "workouts"
            return "\(syncService.unsyncedCount) \(workoutWord) will sync when back online"
        }
        return "Data will be synced when back online"
    }

    // MARK: - Unsynced Badge

    private var unsyncedBadge: some View {
        HStack(spacing: AppSpacing.xxs) {
            Image(icon: .icloudAndArrowUp)
                .font(.system(size: 12, weight: .semibold))
            Text("\(syncService.unsyncedCount)")
                .font(.system(size: 12, weight: .bold))
        }
        .foregroundStyle(.white)
        .padding(.horizontal, AppSpacing.xs)
        .padding(.vertical, AppSpacing.xxs)
        .background(.white.opacity(0.25), in: Capsule())
    }

    // MARK: - Background

    private var bannerBackground: some View {
        LinearGradient(
            colors: [AppColors.warning, AppColors.warning.opacity(0.9)],
            startPoint: .leading,
            endPoint: .trailing
        )
    }

    // MARK: - Accessibility

    private var accessibilityLabel: String {
        if syncService.unsyncedCount > 0 {
            let workoutWord = syncService.unsyncedCount == 1 ? "workout" : "workouts"
            return "No internet connection. \(syncService.unsyncedCount) \(workoutWord) will sync when back online."
        }
        return "No internet connection. Data will be synced when back online."
    }
}

// MARK: - OfflineBannerModifier

/// View modifier that overlays the `OfflineBanner` at the top of any view.
///
/// Usage:
/// ```swift
/// ContentView()
///     .offlineBanner()
/// ```
struct OfflineBannerModifier: ViewModifier {
    func body(content: Content) -> some View {
        ZStack(alignment: .top) {
            content
            OfflineBanner()
        }
    }
}

extension View {
    /// Overlays an `OfflineBanner` at the top of this view.
    func offlineBanner() -> some View {
        modifier(OfflineBannerModifier())
    }
}

// MARK: - Previews

#if DEBUG

/// Wrapper that forces the banner visible regardless of real connectivity,
/// so it can be inspected in Xcode Previews without toggling airplane mode.
private struct OfflineBannerPreview: View {
    var unsyncedCount: Int = 0

    var body: some View {
        HStack(spacing: AppSpacing.sm) {
            Image(icon: .wifiSlash)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.white)

            VStack(alignment: .leading, spacing: 2) {
                Text("No Internet Connection")
                    .font(AppTypography.captionSemibold)
                    .foregroundStyle(.white)

                Text(subtitleText)
                    .font(AppTypography.caption2)
                    .foregroundStyle(.white.opacity(0.85))
            }

            Spacer()

            if unsyncedCount > 0 {
                HStack(spacing: AppSpacing.xxs) {
                    Image(icon: .icloudAndArrowUp)
                        .font(.system(size: 12, weight: .semibold))
                    Text("\(unsyncedCount)")
                        .font(.system(size: 12, weight: .bold))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, AppSpacing.xs)
                .padding(.vertical, AppSpacing.xxs)
                .background(.white.opacity(0.25), in: Capsule())
            }
        }
        .padding(.horizontal, AppSpacing.screenHorizontal)
        .padding(.vertical, AppSpacing.xs + 2)
        .background(
            LinearGradient(
                colors: [AppColors.warning, AppColors.warning.opacity(0.9)],
                startPoint: .leading,
                endPoint: .trailing
            )
        )
    }

    private var subtitleText: String {
        if unsyncedCount > 0 {
            let word = unsyncedCount == 1 ? "workout" : "workouts"
            return "\(unsyncedCount) \(word) will sync when back online"
        }
        return "Data will be synced when back online"
    }
}

#Preview("OfflineBanner - No pending workouts") {
    VStack {
        OfflineBannerPreview(unsyncedCount: 0)
        Spacer()
    }
}

#Preview("OfflineBanner - 3 pending workouts") {
    VStack {
        OfflineBannerPreview(unsyncedCount: 3)
        Spacer()
    }
}

#Preview("OfflineBanner - 1 pending workout (singular)") {
    VStack {
        OfflineBannerPreview(unsyncedCount: 1)
        Spacer()
    }
}
#endif
