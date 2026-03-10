import SwiftUI

// MARK: - FriendsView

/// Root view for the Friends tab.
///
/// Contains four sub-screens selectable via a segmented Picker:
///   0 – Find        (user search + send request)
///   1 – Requests    (incoming pending requests with accept / decline)
///   2 – Friends     (accepted friends list with remove + tap-to-stats)
///   3 – Leaderboard (friends ranked by push-up count for a chosen period)
struct FriendsView: View {

    /// Injected from `MainTabView` so the tab-bar badge and this view share
    /// the same ViewModel instance and are always in sync.
    @ObservedObject var viewModel: FriendsViewModel

    @State private var selectedSegment: Int = 0

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Segmented picker
                Picker("", selection: $selectedSegment) {
                    Text("Find").tag(0)
                    requestsLabel.tag(1)
                    Text("Friends").tag(2)
                    Text("Leaderboard").tag(3)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, AppSpacing.screenHorizontal)
                .padding(.vertical, AppSpacing.xs)

                Divider()

                // Content
                switch selectedSegment {
                case 0:
                    UserSearchView(viewModel: viewModel)
                case 1:
                    FriendRequestsView(viewModel: viewModel)
                case 2:
                    FriendsListView(viewModel: viewModel)
                case 3:
                    LeaderboardView(viewModel: viewModel)
                default:
                    EmptyView()
                }
            }
            .background(AppColors.backgroundPrimary)
            .navigationTitle("Friends")
            .navigationBarTitleDisplayMode(.large)
        }
        .onAppear {
            viewModel.loadIncomingRequests()
            viewModel.loadFriends()
        }
    }

    // MARK: Requests badge label

    private var requestsLabel: some View {
        HStack(spacing: 4) {
            Text("Requests")
            if viewModel.pendingRequestCount > 0 {
                Text("\(viewModel.pendingRequestCount)")
                    .font(.caption2.bold())
                    .foregroundStyle(.white)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(AppColors.error, in: Capsule())
            }
        }
    }
}

// MARK: - UserSearchView

struct UserSearchView: View {

    @ObservedObject var viewModel: FriendsViewModel

    var body: some View {
        VStack(spacing: 0) {
            // Search bar
            HStack(spacing: AppSpacing.xs) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(AppColors.textSecondary)

                TextField("Search by name or username…", text: $viewModel.searchQuery)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .onChange(of: viewModel.searchQuery) { _, q in
                        viewModel.onQueryChanged(q)
                    }

                if !viewModel.searchQuery.isEmpty {
                    Button { viewModel.clearSearch() } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(AppColors.textSecondary)
                    }
                }
            }
            .padding(AppSpacing.sm)
            .background(AppColors.backgroundTertiary)
            .clipShape(RoundedRectangle(cornerRadius: AppSpacing.cornerRadiusChip))
            .padding(.horizontal, AppSpacing.screenHorizontal)
            .padding(.vertical, AppSpacing.sm)

            Divider()

            if viewModel.isSearching {
                Spacer()
                ProgressView()
                Spacer()
            } else if let error = viewModel.searchError {
                errorState(message: error)
            } else if viewModel.searchQuery.count >= 2 && viewModel.searchResults.isEmpty {
                emptyState(
                    icon: "person.slash",
                    title: "No users found",
                    message: "Try a different name or username."
                )
            } else if viewModel.searchQuery.count < 2 {
                emptyState(
                    icon: "magnifyingglass",
                    title: "Find Friends",
                    message: "Type at least 2 characters to search."
                )
            } else {
                List(viewModel.searchResults) { user in
                    UserSearchRow(
                        user: user,
                        isSending: viewModel.sendingRequestIds.contains(user.id),
                        onSend: { viewModel.sendFriendRequest(to: user.id) }
                    )
                    .listRowBackground(AppColors.backgroundSecondary)
                }
                .listStyle(.plain)
            }
        }
    }

    private func emptyState(icon: String, title: String, message: String) -> some View {
        VStack(spacing: AppSpacing.md) {
            Spacer()
            Image(systemName: icon)
                .font(.system(size: 48, weight: .light))
                .foregroundStyle(AppColors.textTertiary)
            VStack(spacing: AppSpacing.xs) {
                Text(title).font(AppTypography.headline).foregroundStyle(AppColors.textPrimary)
                Text(message).font(AppTypography.body).foregroundStyle(AppColors.textSecondary)
                    .multilineTextAlignment(.center)
            }
            Spacer()
        }
        .padding(.horizontal, AppSpacing.xl)
    }

    private func errorState(message: String) -> some View {
        VStack(spacing: AppSpacing.md) {
            Spacer()
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 48, weight: .light))
                .foregroundStyle(AppColors.error)
            Text(message).font(AppTypography.body).foregroundStyle(AppColors.textSecondary)
                .multilineTextAlignment(.center)
            Spacer()
        }
        .padding(.horizontal, AppSpacing.xl)
    }
}

// MARK: - UserSearchRow

private struct UserSearchRow: View {

    let user: UserSearchItem
    let isSending: Bool
    let onSend: () -> Void

    var body: some View {
        HStack(spacing: AppSpacing.sm) {
            FriendAvatar(label: user.displayLabel, color: AppColors.primary)

            VStack(alignment: .leading, spacing: 2) {
                Text(user.displayLabel)
                    .font(AppTypography.bodySemibold)
                    .foregroundStyle(AppColors.textPrimary)
                if let sub = user.usernameLabel {
                    Text(sub)
                        .font(AppTypography.caption1)
                        .foregroundStyle(AppColors.textSecondary)
                }
            }

            Spacer()

            switch user.friendshipStatus {
            case "friend":
                Label("Friends", systemImage: "checkmark")
                    .font(AppTypography.caption1)
                    .foregroundStyle(AppColors.success)
            case "pending":
                Text("Pending")
                    .font(AppTypography.caption1)
                    .foregroundStyle(AppColors.textSecondary)
                    .padding(.horizontal, AppSpacing.sm)
                    .padding(.vertical, AppSpacing.xxs)
                    .background(AppColors.backgroundTertiary, in: Capsule())
            default:
                if isSending {
                    ProgressView().scaleEffect(0.8)
                } else {
                    Button(action: onSend) {
                        Label("Add", systemImage: "person.badge.plus")
                            .font(AppTypography.caption1.bold())
                            .foregroundStyle(.white)
                            .padding(.horizontal, AppSpacing.sm)
                            .padding(.vertical, AppSpacing.xxs)
                            .background(AppColors.primary, in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.vertical, AppSpacing.xs)
    }
}

// MARK: - FriendRequestsView

struct FriendRequestsView: View {

    @ObservedObject var viewModel: FriendsViewModel

    var body: some View {
        Group {
            if viewModel.isLoadingRequests {
                VStack { Spacer(); ProgressView(); Spacer() }
            } else if let error = viewModel.requestsError {
                errorState(message: error)
            } else if viewModel.incomingRequests.isEmpty {
                emptyState
            } else {
                List(viewModel.incomingRequests) { request in
                    FriendRequestRow(
                        request: request,
                        isResponding: viewModel.respondingIds.contains(request.id),
                        onAccept: { viewModel.acceptRequest(request.id) },
                        onDecline: { viewModel.declineRequest(request.id) }
                    )
                    .listRowBackground(AppColors.backgroundSecondary)
                }
                .listStyle(.plain)
                .refreshable { viewModel.loadIncomingRequests() }
            }
        }
        .alert(
            "Error",
            isPresented: Binding(
                get: { viewModel.respondError != nil },
                set: { if !$0 { viewModel.dismissRespondError() } }
            )
        ) {
            Button("OK", role: .cancel) { viewModel.dismissRespondError() }
        } message: {
            Text(viewModel.respondError ?? "")
        }
    }

    private var emptyState: some View {
        VStack(spacing: AppSpacing.md) {
            Spacer()
            Image(systemName: "envelope.open")
                .font(.system(size: 48, weight: .light))
                .foregroundStyle(AppColors.textTertiary)
            VStack(spacing: AppSpacing.xs) {
                Text("No pending requests")
                    .font(AppTypography.headline)
                    .foregroundStyle(AppColors.textPrimary)
                Text("When someone sends you a friend request, it will appear here.")
                    .font(AppTypography.body)
                    .foregroundStyle(AppColors.textSecondary)
                    .multilineTextAlignment(.center)
            }
            Spacer()
        }
        .padding(.horizontal, AppSpacing.xl)
    }

    private func errorState(message: String) -> some View {
        VStack(spacing: AppSpacing.md) {
            Spacer()
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 48, weight: .light))
                .foregroundStyle(AppColors.error)
            Text(message)
                .font(AppTypography.body)
                .foregroundStyle(AppColors.textSecondary)
                .multilineTextAlignment(.center)
            Button("Retry") { viewModel.loadIncomingRequests() }
                .buttonStyle(.bordered)
            Spacer()
        }
        .padding(.horizontal, AppSpacing.xl)
    }
}

// MARK: - FriendRequestRow

private struct FriendRequestRow: View {

    let request: FriendRequestItem
    let isResponding: Bool
    let onAccept: () -> Void
    let onDecline: () -> Void

    var body: some View {
        HStack(spacing: AppSpacing.sm) {
            FriendAvatar(label: request.displayLabel, color: AppColors.primary)

            VStack(alignment: .leading, spacing: 2) {
                Text(request.displayLabel)
                    .font(AppTypography.bodySemibold)
                    .foregroundStyle(AppColors.textPrimary)
                if let sub = request.usernameLabel {
                    Text(sub)
                        .font(AppTypography.caption1)
                        .foregroundStyle(AppColors.textSecondary)
                }
            }

            Spacer()

            if isResponding {
                ProgressView().scaleEffect(0.8)
            } else {
                HStack(spacing: AppSpacing.xs) {
                    Button(action: onDecline) {
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(AppColors.error)
                            .frame(width: 32, height: 32)
                            .background(AppColors.error.opacity(0.12), in: Circle())
                    }
                    .buttonStyle(.plain)

                    Button(action: onAccept) {
                        Image(systemName: "checkmark")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 32, height: 32)
                            .background(AppColors.success, in: Circle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.vertical, AppSpacing.xs)
    }
}

// MARK: - FriendsListView

struct FriendsListView: View {

    @ObservedObject var viewModel: FriendsViewModel
    @State private var friendToRemove: FriendItem? = nil

    var body: some View {
        Group {
            if viewModel.isLoadingFriends {
                VStack { Spacer(); ProgressView(); Spacer() }
            } else if let error = viewModel.friendsError {
                errorState(message: error)
            } else if viewModel.friends.isEmpty {
                emptyState
            } else {
                List(viewModel.friends) { friend in
                    NavigationLink {
                        FriendStatsView(
                            viewModel: viewModel,
                            friendId: friend.id,
                            friendName: friend.displayLabel
                        )
                    } label: {
                        FriendRowLabel(
                            friend: friend,
                            isRemoving: viewModel.removingIds.contains(friend.id),
                            onRemove: { friendToRemove = friend }
                        )
                    }
                    .listRowBackground(AppColors.backgroundSecondary)
                }
                .listStyle(.plain)
                .refreshable { viewModel.loadFriends() }
            }
        }
        .confirmationDialog(
            "Remove \(friendToRemove?.displayLabel ?? "friend")?",
            isPresented: Binding(
                get: { friendToRemove != nil },
                set: { if !$0 { friendToRemove = nil } }
            ),
            titleVisibility: .visible
        ) {
            if let f = friendToRemove {
                Button("Remove", role: .destructive) {
                    viewModel.removeFriend(f.id)
                    friendToRemove = nil
                }
            }
            Button("Cancel", role: .cancel) { friendToRemove = nil }
        }
    }

    private var emptyState: some View {
        VStack(spacing: AppSpacing.md) {
            Spacer()
            Image(systemName: "person.2")
                .font(.system(size: 48, weight: .light))
                .foregroundStyle(AppColors.textTertiary)
            VStack(spacing: AppSpacing.xs) {
                Text("No friends yet")
                    .font(AppTypography.headline)
                    .foregroundStyle(AppColors.textPrimary)
                Text("Search for people and send them a friend request.")
                    .font(AppTypography.body)
                    .foregroundStyle(AppColors.textSecondary)
                    .multilineTextAlignment(.center)
            }
            Spacer()
        }
        .padding(.horizontal, AppSpacing.xl)
    }

    private func errorState(message: String) -> some View {
        VStack(spacing: AppSpacing.md) {
            Spacer()
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 48, weight: .light))
                .foregroundStyle(AppColors.error)
            Text(message)
                .font(AppTypography.body)
                .foregroundStyle(AppColors.textSecondary)
                .multilineTextAlignment(.center)
            Button("Retry") { viewModel.loadFriends() }
                .buttonStyle(.bordered)
            Spacer()
        }
        .padding(.horizontal, AppSpacing.xl)
    }
}

// MARK: - FriendRowLabel

/// The label content for a friend row (used in both FriendsListView and LeaderboardView).
private struct FriendRowLabel: View {

    let friend: FriendItem
    let isRemoving: Bool
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: AppSpacing.sm) {
            FriendAvatar(label: friend.displayLabel, color: AppColors.success)

            VStack(alignment: .leading, spacing: 2) {
                Text(friend.displayLabel)
                    .font(AppTypography.bodySemibold)
                    .foregroundStyle(AppColors.textPrimary)
                if let sub = friend.usernameLabel {
                    Text(sub)
                        .font(AppTypography.caption1)
                        .foregroundStyle(AppColors.textSecondary)
                }
            }

            Spacer()

            if isRemoving {
                ProgressView().scaleEffect(0.8)
            } else {
                Button(action: onRemove) {
                    Image(systemName: "person.badge.minus")
                        .font(.system(size: 16))
                        .foregroundStyle(AppColors.textSecondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, AppSpacing.xs)
    }
}

// MARK: - LeaderboardView

/// Displays friends ranked by push-up count for a selectable time period.
///
/// Tapping a row navigates to that friend's full stats detail screen.
struct LeaderboardView: View {

    @ObservedObject var viewModel: FriendsViewModel

    var body: some View {
        VStack(spacing: 0) {
            // Period selector
            periodPicker
                .padding(.horizontal, AppSpacing.screenHorizontal)
                .padding(.vertical, AppSpacing.xs)

            Divider()

            // Content
            if viewModel.isLoadingLeaderboard || (viewModel.isLoadingFriends && viewModel.leaderboard.isEmpty) {
                loadingView
            } else if let error = viewModel.leaderboardError {
                errorState(message: error)
            } else if viewModel.leaderboard.isEmpty {
                emptyState
            } else {
                leaderboardList
            }
        }
        .onAppear {
            // If friends are already loaded, populate the leaderboard immediately.
            // If not, loadFriends() is called from FriendsView.onAppear and
            // loadLeaderboardIfReady() will be triggered once friends arrive.
            viewModel.loadLeaderboard()
        }
    }

    // MARK: Period picker

    private var periodPicker: some View {
        HStack(spacing: AppSpacing.xs) {
            ForEach(FriendStatsPeriod.allCases) { period in
                periodChip(period)
            }
            Spacer()
        }
    }

    private func periodChip(_ period: FriendStatsPeriod) -> some View {
        let isSelected = viewModel.leaderboardPeriod == period
        return Button {
            viewModel.selectLeaderboardPeriod(period)
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

    // MARK: Leaderboard list

    private var leaderboardList: some View {
        List {
            ForEach(Array(viewModel.leaderboard.enumerated()), id: \.element.id) { index, entry in
                NavigationLink {
                    FriendStatsView(
                        viewModel: viewModel,
                        friendId: entry.id,
                        friendName: entry.displayLabel
                    )
                } label: {
                    LeaderboardRow(rank: index + 1, entry: entry)
                }
                .listRowBackground(AppColors.backgroundSecondary)
            }
        }
        .listStyle(.plain)
        .refreshable {
            viewModel.loadLeaderboard()
        }
    }

    // MARK: States

    private var loadingView: some View {
        VStack(spacing: AppSpacing.md) {
            Spacer()
            ProgressView()
            Text("Loading leaderboard…")
                .font(AppTypography.subheadline)
                .foregroundStyle(AppColors.textSecondary)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private var emptyState: some View {
        VStack(spacing: AppSpacing.md) {
            Spacer()
            Image(systemName: "trophy")
                .font(.system(size: 48, weight: .light))
                .foregroundStyle(AppColors.textTertiary)
            VStack(spacing: AppSpacing.xs) {
                Text("No leaderboard yet")
                    .font(AppTypography.headline)
                    .foregroundStyle(AppColors.textPrimary)
                Text("Add friends to see how you compare.")
                    .font(AppTypography.body)
                    .foregroundStyle(AppColors.textSecondary)
                    .multilineTextAlignment(.center)
            }
            Spacer()
        }
        .padding(.horizontal, AppSpacing.xl)
    }

    private func errorState(message: String) -> some View {
        VStack(spacing: AppSpacing.md) {
            Spacer()
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 48, weight: .light))
                .foregroundStyle(AppColors.error)
            Text(message)
                .font(AppTypography.body)
                .foregroundStyle(AppColors.textSecondary)
                .multilineTextAlignment(.center)
            Button("Retry") { viewModel.loadLeaderboard() }
                .buttonStyle(.bordered)
            Spacer()
        }
        .padding(.horizontal, AppSpacing.xl)
    }
}

// MARK: - LeaderboardRow

private struct LeaderboardRow: View {

    let rank: Int
    let entry: LeaderboardEntry

    var body: some View {
        HStack(spacing: AppSpacing.sm) {
            // Rank badge
            rankBadge

            // Avatar
            FriendAvatar(label: entry.displayLabel, color: rankColor)

            // Name
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.displayLabel)
                    .font(AppTypography.bodySemibold)
                    .foregroundStyle(AppColors.textPrimary)
                if let sub = entry.usernameLabel {
                    Text(sub)
                        .font(AppTypography.caption1)
                        .foregroundStyle(AppColors.textSecondary)
                }
            }

            Spacer()

            // Push-up count
            VStack(alignment: .trailing, spacing: 2) {
                Text("\(entry.pushupCount)")
                    .font(AppTypography.headline)
                    .foregroundStyle(AppColors.textPrimary)
                Text("push-ups")
                    .font(AppTypography.caption2)
                    .foregroundStyle(AppColors.textSecondary)
            }
        }
        .padding(.vertical, AppSpacing.xs)
    }

    private var rankBadge: some View {
        ZStack {
            Circle()
                .fill(rankColor.opacity(0.15))
                .frame(width: 28, height: 28)
            Text("\(rank)")
                .font(AppTypography.captionSemibold)
                .foregroundStyle(rankColor)
        }
    }

    /// Gold for 1st, silver for 2nd, bronze for 3rd, default for the rest.
    private var rankColor: Color {
        switch rank {
        case 1: return Color(light: "#FFD700", dark: "#FFD700")   // gold
        case 2: return Color(light: "#C0C0C0", dark: "#A8A8A8")   // silver
        case 3: return Color(light: "#CD7F32", dark: "#CD7F32")   // bronze
        default: return AppColors.primary
        }
    }
}

// MARK: - FriendAvatar

/// Reusable circular avatar showing the first letter of a name.
///
/// Extracted from the inline `Circle().overlay { Text(...) }` pattern that
/// was duplicated across `UserSearchRow`, `FriendRequestRow`, and `FriendRow`.
struct FriendAvatar: View {

    let label: String
    let color: Color
    var size: CGFloat = 40

    var body: some View {
        Circle()
            .fill(color.opacity(0.15))
            .frame(width: size, height: size)
            .overlay {
                Text(String(label.prefix(1)).uppercased())
                    .font(AppTypography.headline)
                    .foregroundStyle(color)
            }
    }
}

// MARK: - Preview

#if DEBUG
#Preview("FriendsView") {
    FriendsView(viewModel: FriendsViewModel())
}
#endif
