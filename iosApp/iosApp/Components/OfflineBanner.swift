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
    @ObservedObject private var syncService = SyncService.shared

    var body: some View {
        if !networkMonitor.isConnected {
            VStack(spacing: 0) {
                bannerContent
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
            .animation(.spring(response: 0.4, dampingFraction: 0.8), value: networkMonitor.isConnected)
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
            colors: [
                AppColors.warning,
                AppColors.warning.opacity(0.9),
            ],
            startPoint: .leading,
            endPoint: .trailing
        )
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
#Preview("OfflineBanner") {
    VStack {
        // Simulated banner (always visible in preview)
        HStack(spacing: AppSpacing.sm) {
            Image(icon: .wifiSlash)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.white)

            VStack(alignment: .leading, spacing: 2) {
                Text("No Internet Connection")
                    .font(AppTypography.captionSemibold)
                    .foregroundStyle(.white)

                Text("3 workouts will sync when back online")
                    .font(AppTypography.caption2)
                    .foregroundStyle(.white.opacity(0.85))
            }

            Spacer()

            HStack(spacing: AppSpacing.xxs) {
                Image(icon: .icloudAndArrowUp)
                    .font(.system(size: 12, weight: .semibold))
                Text("3")
                    .font(.system(size: 12, weight: .bold))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, AppSpacing.xs)
            .padding(.vertical, AppSpacing.xxs)
            .background(.white.opacity(0.25), in: Capsule())
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

        Spacer()
    }
}
#endif
