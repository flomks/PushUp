import SwiftUI

// MARK: - FriendStatsView

/// Full-screen detail view showing a friend's activity statistics.
///
/// Displayed when the user taps a friend in the Friends list or Leaderboard.
/// Supports switching between Today / This Week / This Month periods.
/// Navigated to via `NavigationStack` push from `FriendsListView`.
struct FriendStatsView: View {

    @ObservedObject var viewModel: FriendsViewModel

    let friendId: String
    let friendName: String

    var body: some View {
        ScrollView {
            VStack(spacing: AppSpacing.md) {
                // Period picker
                periodPicker

                // Content area
                switch viewModel.friendStatsState {
                case .idle:
                    // Trigger initial load on appear; show nothing until data arrives.
                    Color.clear.frame(height: 1)

                case .loading:
                    loadingView

                case .loaded(let data):
                    statsContent(data: data)

                case .error(let message):
                    errorView(message: message)
                }
            }
            .padding(.horizontal, AppSpacing.screenHorizontal)
            .padding(.top, AppSpacing.md)
            .padding(.bottom, AppSpacing.screenVerticalBottom)
        }
        .background(AppColors.backgroundPrimary)
        .navigationTitle(friendName.isEmpty ? "Friend" : friendName)
        .navigationBarTitleDisplayMode(.large)
        .onAppear {
            viewModel.loadFriendStats(
                friendId: friendId,
                friendName: friendName,
                period: viewModel.friendStatsPeriod
            )
        }
        .onDisappear {
            viewModel.resetFriendStats()
        }
    }

    // MARK: Period picker

    private var periodPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: AppSpacing.xs) {
                ForEach(FriendStatsPeriod.allCases) { period in
                    periodChip(period)
                }
            }
            .padding(.horizontal, 2) // prevent chip shadow clipping
        }
    }

    private func periodChip(_ period: FriendStatsPeriod) -> some View {
        let isSelected = viewModel.friendStatsPeriod == period
        return Button {
            viewModel.changeFriendStatsPeriod(
                to: period,
                friendId: friendId,
                friendName: friendName
            )
        } label: {
            Text(period.label)
                .font(AppTypography.captionSemibold)
                .foregroundStyle(isSelected ? AppColors.textOnPrimary : AppColors.textPrimary)
                .padding(.horizontal, AppSpacing.sm)
                .padding(.vertical, AppSpacing.xxs + 2)
                .background(
                    isSelected ? AppColors.primary : AppColors.backgroundTertiary,
                    in: Capsule()
                )
        }
        .buttonStyle(.plain)
        .animation(.easeInOut(duration: 0.15), value: isSelected)
    }

    // MARK: Loading

    private var loadingView: some View {
        VStack(spacing: AppSpacing.md) {
            Spacer(minLength: AppSpacing.xxl)
            ProgressView()
                .scaleEffect(1.2)
            Text("Loading stats…")
                .font(AppTypography.subheadline)
                .foregroundStyle(AppColors.textSecondary)
            Spacer(minLength: AppSpacing.xxl)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: Error

    private func errorView(message: String) -> some View {
        VStack(spacing: AppSpacing.md) {
            Spacer(minLength: AppSpacing.xxl)
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: AppSpacing.iconSizeXL, weight: .light))
                .foregroundStyle(AppColors.error)
            Text(message)
                .font(AppTypography.body)
                .foregroundStyle(AppColors.textSecondary)
                .multilineTextAlignment(.center)
            Button("Retry") {
                viewModel.loadFriendStats(
                    friendId: friendId,
                    friendName: friendName,
                    period: viewModel.friendStatsPeriod
                )
            }
            .buttonStyle(.bordered)
            Spacer(minLength: AppSpacing.xxl)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, AppSpacing.xl)
    }

    // MARK: Stats content

    @ViewBuilder
    private func statsContent(data: FriendStatsData) -> some View {
        if data.totalSessions == 0 {
            emptyStatsView(data: data)
        } else {
            VStack(spacing: AppSpacing.md) {
                // Date range subtitle
                dateRangeLabel(from: data.dateFrom, to: data.dateTo)

                // Hero push-up card
                pushupHeroCard(count: data.pushupCount)

                // 2-column grid: Sessions + Screen Time
                HStack(spacing: AppSpacing.sm) {
                    statCard(
                        icon: "figure.strengthtraining.traditional",
                        label: "Sessions",
                        value: "\(data.totalSessions)",
                        color: AppColors.primary
                    )
                    statCard(
                        icon: "clock.fill",
                        label: "Screen Time",
                        value: formatDuration(seconds: data.totalEarnedSeconds),
                        color: AppColors.secondary
                    )
                }

                // Average quality card (full width)
                if let quality = data.averageQuality {
                    qualityCard(score: quality)
                }
            }
        }
    }

    // MARK: Empty stats

    private func emptyStatsView(data: FriendStatsData) -> some View {
        VStack(spacing: AppSpacing.md) {
            Spacer(minLength: AppSpacing.xxl)
            Image(systemName: "figure.strengthtraining.traditional")
                .font(.system(size: AppSpacing.iconSizeXL, weight: .light))
                .foregroundStyle(AppColors.textTertiary)
            VStack(spacing: AppSpacing.xs) {
                Text("No activity yet")
                    .font(AppTypography.headline)
                    .foregroundStyle(AppColors.textPrimary)
                let periodLabel: String = {
                    switch viewModel.friendStatsPeriod {
                    case .day:   return "today"
                    case .week:  return "this week"
                    case .month: return "this month"
                    }
                }()
                let name = data.friendName.isEmpty ? "Your friend" : data.friendName
                Text("\(name) hasn't recorded any push-ups \(periodLabel).")
                    .font(AppTypography.body)
                    .foregroundStyle(AppColors.textSecondary)
                    .multilineTextAlignment(.center)
            }
            Spacer(minLength: AppSpacing.xxl)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, AppSpacing.xl)
    }

    // MARK: Sub-components

    private func dateRangeLabel(from: String, to: String) -> some View {
        Text("\(from)  –  \(to)")
            .font(AppTypography.caption1)
            .foregroundStyle(AppColors.textSecondary)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func pushupHeroCard(count: Int) -> some View {
        VStack(spacing: AppSpacing.xs) {
            Text("\(count)")
                .font(AppTypography.displayLarge)
                .foregroundStyle(AppColors.textOnPrimary)
            HStack(spacing: AppSpacing.xxs) {
                Image(systemName: "figure.strengthtraining.traditional")
                    .font(.system(size: AppSpacing.iconSizeSmall))
                    .foregroundStyle(AppColors.textOnPrimary.opacity(0.8))
                Text("Push-ups")
                    .font(AppTypography.subheadlineSemibold)
                    .foregroundStyle(AppColors.textOnPrimary.opacity(0.8))
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, AppSpacing.xl)
        .background(AppColors.primary, in: RoundedRectangle(cornerRadius: AppSpacing.cornerRadiusLarge))
    }

    private func statCard(
        icon: String,
        label: String,
        value: String,
        color: Color
    ) -> some View {
        VStack(spacing: AppSpacing.xs) {
            Image(systemName: icon)
                .font(.system(size: AppSpacing.iconSizeMedium))
                .foregroundStyle(color)
            Text(value)
                .font(AppTypography.displayMedium)
                .foregroundStyle(AppColors.textPrimary)
            Text(label)
                .font(AppTypography.caption1)
                .foregroundStyle(AppColors.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(AppSpacing.cardPadding)
        .background(AppColors.backgroundSecondary, in: RoundedRectangle(cornerRadius: AppSpacing.cornerRadiusCard))
    }

    private func qualityCard(score: Double) -> some View {
        let percentage = Int((score * 100).rounded())
        let color = AppColors.formScoreColor(score)

        return HStack(spacing: AppSpacing.sm) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: AppSpacing.iconSizeMedium))
                .foregroundStyle(color)
            VStack(alignment: .leading, spacing: 2) {
                Text("Avg. Form Quality")
                    .font(AppTypography.caption1)
                    .foregroundStyle(AppColors.textSecondary)
                Text("\(percentage)%")
                    .font(AppTypography.headline)
                    .foregroundStyle(color)
            }
            Spacer()
            // Visual quality bar
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(AppColors.backgroundTertiary)
                    RoundedRectangle(cornerRadius: 4)
                        .fill(color)
                        .frame(width: geo.size.width * score)
                }
            }
            .frame(width: 80, height: 8)
        }
        .padding(AppSpacing.cardPadding)
        .background(AppColors.backgroundSecondary, in: RoundedRectangle(cornerRadius: AppSpacing.cornerRadiusCard))
    }
}

// MARK: - Helpers

/// Formats a duration in seconds into a human-readable string.
///
/// Examples:
///   0       -> "0 min"
///   90      -> "1 min"
///   3600    -> "1h"
///   3661    -> "1h 1m"
private func formatDuration(seconds: Int64) -> String {
    let minutes = seconds / 60
    guard minutes >= 60 else { return "\(minutes) min" }
    let hours = minutes / 60
    let remaining = minutes % 60
    return remaining == 0 ? "\(hours)h" : "\(hours)h \(remaining)m"
}

// MARK: - Preview

#if DEBUG
#Preview("FriendStatsView - Loaded") {
    NavigationStack {
        // Simulate a loaded state via a pre-populated ViewModel.
        let vm = FriendsViewModel()
        vm.friendStatsState = .loaded(FriendStatsData(
            friendId: "u1",
            friendName: "Alice Smith",
            period: "week",
            dateFrom: "2026-03-02",
            dateTo: "2026-03-08",
            pushupCount: 142,
            totalSessions: 7,
            totalEarnedSeconds: 852,
            averageQuality: 0.87
        ))
        vm.friendStatsPeriod = .week
        return FriendStatsView(viewModel: vm, friendId: "u1", friendName: "Alice Smith")
    }
}

#Preview("FriendStatsView - Empty") {
    NavigationStack {
        let vm = FriendsViewModel()
        vm.friendStatsState = .loaded(FriendStatsData(
            friendId: "u2",
            friendName: "Bob Jones",
            period: "day",
            dateFrom: "2026-03-10",
            dateTo: "2026-03-10",
            pushupCount: 0,
            totalSessions: 0,
            totalEarnedSeconds: 0,
            averageQuality: nil
        ))
        vm.friendStatsPeriod = .day
        return FriendStatsView(viewModel: vm, friendId: "u2", friendName: "Bob Jones")
    }
}

#Preview("FriendStatsView - Loading") {
    NavigationStack {
        let vm = FriendsViewModel()
        vm.friendStatsState = .loading
        return FriendStatsView(viewModel: vm, friendId: "u3", friendName: "Charlie")
    }
}

#Preview("FriendStatsView - Error") {
    NavigationStack {
        let vm = FriendsViewModel()
        vm.friendStatsState = .error("Could not load stats. Please try again.")
        return FriendStatsView(viewModel: vm, friendId: "u4", friendName: "Dana")
    }
}
#endif
