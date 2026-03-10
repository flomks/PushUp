import SwiftUI

// MARK: - FriendsView

/// Root view for the Friends tab.
///
/// Contains three sub-screens selectable via a Picker (segmented control):
///   0 – Find Friends  (user search + send request)
///   1 – Requests      (incoming pending requests with accept/decline)
///   2 – Friends       (accepted friends list with remove)
struct FriendsView: View {

    /// Injected from MainTabView so the tab-bar badge and this view share
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

    // Badge on "Requests" segment label
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
            // Avatar placeholder
            Circle()
                .fill(AppColors.primary.opacity(0.15))
                .frame(width: 40, height: 40)
                .overlay {
                    Text(String(user.displayLabel.prefix(1)).uppercased())
                        .font(AppTypography.headline)
                        .foregroundStyle(AppColors.primary)
                }

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

            // Action button
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
            // Avatar
            Circle()
                .fill(AppColors.primary.opacity(0.15))
                .frame(width: 40, height: 40)
                .overlay {
                    Text(String(request.displayLabel.prefix(1)).uppercased())
                        .font(AppTypography.headline)
                        .foregroundStyle(AppColors.primary)
                }

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
                    // Decline
                    Button(action: onDecline) {
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(AppColors.error)
                            .frame(width: 32, height: 32)
                            .background(AppColors.error.opacity(0.12), in: Circle())
                    }
                    .buttonStyle(.plain)

                    // Accept
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
                    FriendRow(
                        friend: friend,
                        isRemoving: viewModel.removingIds.contains(friend.id),
                        onRemove: { friendToRemove = friend }
                    )
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

// MARK: - FriendRow

private struct FriendRow: View {

    let friend: FriendItem
    let isRemoving: Bool
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: AppSpacing.sm) {
            Circle()
                .fill(AppColors.success.opacity(0.15))
                .frame(width: 40, height: 40)
                .overlay {
                    Text(String(friend.displayLabel.prefix(1)).uppercased())
                        .font(AppTypography.headline)
                        .foregroundStyle(AppColors.success)
                }

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

// MARK: - Preview

#if DEBUG
#Preview("FriendsView") {
    FriendsView(viewModel: FriendsViewModel())
}
#endif
