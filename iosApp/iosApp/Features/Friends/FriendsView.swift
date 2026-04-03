import SwiftUI

// MARK: - FriendsView

/// Root view for the Friends tab.
///
/// Renders the Friend Hub -- a single scrollable screen that shows the
/// leaderboard, the friends list, and quick-action buttons for adding
/// friends and managing incoming requests.
///
/// Navigation to individual friend stats is handled via NavigationLink
/// pushes from within the hub. The Add Friend and Requests flows open
/// as bottom sheets so the hub context is never lost.
struct FriendsView: View {

    /// Injected from `MainTabView` so the tab-bar badge and this view share
    /// the same ViewModel instance and are always in sync.
    @ObservedObject var viewModel: FriendsViewModel

    var onOpenMenu: (() -> Void)? = nil

    /// Controls the Add Friend bottom sheet.
    @State private var showAddFriend = false

    /// Controls the Requests bottom sheet.
    @State private var showRequests = false

    var body: some View {
        NavigationStack {
            FriendHubView(
                viewModel: viewModel,
                showAddFriend: $showAddFriend,
                showRequests: $showRequests
            )
            .safeAreaPadding(.top, 6)
            .navigationTitle("Friends")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                if let onOpenMenu {
                    ToolbarItem(placement: .topBarLeading) {
                        Button(action: onOpenMenu) {
                            Image(systemName: "line.3.horizontal")
                                .font(.system(size: 17, weight: .medium))
                                .foregroundStyle(AppColors.textPrimary)
                        }
                        .accessibilityLabel("Open menu")
                    }
                }
                toolbarItems
            }
        }
        .sheet(isPresented: $showAddFriend) {
            AddFriendSheet(viewModel: viewModel)
        }
        .sheet(isPresented: $showRequests) {
            RequestsSheet(viewModel: viewModel)
        }
        .onAppear {
            viewModel.loadIncomingRequests()
            viewModel.loadFriends()
        }
    }

    // MARK: Toolbar

    @ToolbarContentBuilder
    private var toolbarItems: some ToolbarContent {
        ToolbarItemGroup(placement: .navigationBarTrailing) {
            // Requests button with badge
            Button {
                showRequests = true
            } label: {
                ZStack(alignment: .topTrailing) {
                    Image(systemName: "bell.fill")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(AppColors.primary)

                    if viewModel.pendingRequestCount > 0 {
                        Text("\(viewModel.pendingRequestCount)")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 2)
                            .background(AppColors.error, in: Capsule())
                            .offset(x: 8, y: -6)
                    }
                }
                .frame(width: 44, height: 44)
            }
            .accessibilityLabel(
                viewModel.pendingRequestCount > 0
                    ? "\(viewModel.pendingRequestCount) pending requests"
                    : "Friend requests"
            )

            // Add friend button
            Button {
                showAddFriend = true
            } label: {
                Image(systemName: "person.badge.plus")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(AppColors.primary)
                    .frame(width: 44, height: 44)
            }
            .accessibilityLabel("Add friend")
        }
    }
}

// MARK: - FriendHubView

/// The main scrollable hub content.
private struct FriendHubView: View {

    @ObservedObject var viewModel: FriendsViewModel
    @Binding var showAddFriend: Bool
    @Binding var showRequests: Bool

    var body: some View {
        ScrollView {
            LazyVStack(spacing: AppSpacing.lg) {
                hubHero
                quickActionsCard

                // 1. Leaderboard -- only shown once we know the user has friends.
                //    Deliberately NOT shown while isLoadingFriends to avoid the
                //    flicker where the leaderboard appears briefly then disappears.
                if !viewModel.friends.isEmpty {
                    leaderboardSection
                }

                // 2. Friends list
                friendsSection
            }
            .padding(.horizontal, AppSpacing.screenHorizontal)
            .padding(.top, AppSpacing.sm)
            .padding(.bottom, AppSpacing.screenVerticalBottom)
        }
        .background(AppColors.backgroundPrimary)
        .refreshable {
            await viewModel.refresh()
        }
    }

    private func heroMetric(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
            Text(title)
                .font(AppTypography.caption1)
                .foregroundStyle(Color.white.opacity(0.74))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, AppSpacing.sm)
        .padding(.vertical, AppSpacing.xs)
        .background(Color.white.opacity(0.12), in: RoundedRectangle(cornerRadius: AppSpacing.cornerRadiusButton))
    }

    private func quickAction(
        title: String,
        subtitle: String,
        icon: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: AppSpacing.xs) {
                Image(systemName: icon)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(AppColors.primary)
                    .frame(width: 38, height: 38)
                    .background(AppColors.primary.opacity(0.10), in: Circle())

                Text(title)
                    .font(AppTypography.bodySemibold)
                    .foregroundStyle(AppColors.textPrimary)

                Text(subtitle)
                    .font(AppTypography.caption1)
                    .foregroundStyle(AppColors.textSecondary)
                    .multilineTextAlignment(.leading)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(AppSpacing.md)
            .background(AppColors.backgroundTertiary.opacity(0.55), in: RoundedRectangle(cornerRadius: AppSpacing.cornerRadiusCard))
        }
        .buttonStyle(.plain)
    }

    private var hubHero: some View {
        ZStack(alignment: .bottomLeading) {
            RoundedRectangle(cornerRadius: AppSpacing.cornerRadiusLarge + 4)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.08, green: 0.20, blue: 0.32),
                            Color(red: 0.12, green: 0.38, blue: 0.58),
                            Color(red: 0.98, green: 0.43, blue: 0.22)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay(alignment: .topTrailing) {
                    Circle()
                        .fill(Color.white.opacity(0.10))
                        .frame(width: 170, height: 170)
                        .offset(x: 44, y: -40)
                }
                .overlay(alignment: .bottomTrailing) {
                    Circle()
                        .stroke(Color.white.opacity(0.10), lineWidth: 1)
                        .frame(width: 160, height: 160)
                        .offset(x: 36, y: 52)
                }

            VStack(alignment: .leading, spacing: AppSpacing.md) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: AppSpacing.xxs) {
                        Text("SOCIAL")
                            .font(.system(size: 12, weight: .bold, design: .rounded))
                            .foregroundStyle(Color.white.opacity(0.72))
                            .tracking(2)

                        Text("Your crew, your competition, your progress.")
                            .font(.system(size: 30, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                            .lineLimit(3)
                    }

                    Spacer(minLength: 12)

                    ZStack {
                        Circle()
                            .fill(Color.white.opacity(0.14))
                            .frame(width: 60, height: 60)

                        Image(systemName: "person.3.fill")
                            .font(.system(size: 28, weight: .semibold))
                            .foregroundStyle(.white)
                    }
                }

                Text("Track overall activity, inspect friend profiles, and keep the competitive layer aligned with the rest of the app.")
                    .font(AppTypography.body)
                    .foregroundStyle(Color.white.opacity(0.84))

                HStack(spacing: AppSpacing.sm) {
                    heroMetric(title: "Friends", value: "\(viewModel.friends.count)")
                    heroMetric(title: "Requests", value: "\(viewModel.pendingRequestCount)")
                    heroMetric(title: "Board", value: viewModel.leaderboardPeriod.shortLabel)
                }
            }
            .padding(AppSpacing.xl)
        }
    }

    private var quickActionsCard: some View {
        Card {
            HStack(spacing: AppSpacing.sm) {
                quickAction(
                    title: "Add Friend",
                    subtitle: "Search or use code",
                    icon: "person.badge.plus"
                ) {
                    showAddFriend = true
                }

                quickAction(
                    title: "Requests",
                    subtitle: viewModel.pendingRequestCount > 0 ? "\(viewModel.pendingRequestCount) pending" : "Inbox clear",
                    icon: "bell.badge.fill"
                ) {
                    showRequests = true
                }
            }
        }
    }

    // MARK: - Leaderboard Section

    @ViewBuilder
    private var leaderboardSection: some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            // Section header with period chips
            HStack {
                Text("Activity Board")
                    .font(AppTypography.title2)
                    .foregroundStyle(AppColors.textPrimary)

                Spacer()

                // Period chips
                HStack(spacing: AppSpacing.xxs) {
                    ForEach(FriendStatsPeriod.allCases) { period in
                        periodChip(period)
                    }
                }
            }

            if viewModel.isLoadingLeaderboard && viewModel.leaderboard.isEmpty {
                leaderboardSkeleton
            } else if let error = viewModel.leaderboardError {
                leaderboardError(error)
            } else if viewModel.leaderboard.isEmpty {
                leaderboardEmpty
            } else {
                leaderboardContent
            }
        }
        .onAppear { viewModel.loadLeaderboard() }
    }

    private func periodChip(_ period: FriendStatsPeriod) -> some View {
        let isSelected = viewModel.leaderboardPeriod == period
        return Button {
            viewModel.selectLeaderboardPeriod(period)
        } label: {
            Text(period.shortLabel)
                .font(AppTypography.caption2)
                .fontWeight(.semibold)
                .foregroundStyle(isSelected ? AppColors.textOnPrimary : AppColors.textSecondary)
                .padding(.horizontal, AppSpacing.xs)
                .padding(.vertical, AppSpacing.xxs)
                .background(
                    isSelected ? AppColors.primary : AppColors.backgroundTertiary,
                    in: Capsule()
                )
        }
        .buttonStyle(.plain)
        .animation(.easeInOut(duration: 0.15), value: isSelected)
    }

    // MARK: Leaderboard content

    @ViewBuilder
    private var leaderboardContent: some View {
        VStack(spacing: AppSpacing.xs) {
            // Podium: all entries with rank 1, 2, or 3 — requires at least
            // one entry at each of those three distinct rank levels.
            let podiumEntries = viewModel.leaderboard.filter { $0.rank <= 3 }
            let distinctPodiumRanks = Set(podiumEntries.map { $0.rank })
            let hasPodium = distinctPodiumRanks.count >= 3

            if hasPodium {
                PodiumView(entries: podiumEntries, viewModel: viewModel)
                    .padding(.bottom, AppSpacing.xs)
            }

            // Rows: entries below the podium threshold, or all entries when
            // there are fewer than 3 distinct rank levels.
            let rowEntries: [LeaderboardEntry] = hasPodium
                ? viewModel.leaderboard.filter { $0.rank > 3 }
                : viewModel.leaderboard

            ForEach(rowEntries) { entry in
                leaderboardRow(entry: entry)
            }
        }
    }

    private func leaderboardRow(entry: LeaderboardEntry) -> some View {
        let rank = entry.rank
        let content = HStack(spacing: AppSpacing.sm) {
            // Rank number
            Text("\(rank)")
                .font(AppTypography.captionSemibold)
                .foregroundStyle(AppColors.textSecondary)
                .frame(width: 20, alignment: .center)

            // Avatar (leaderboard entries carry no URL; initials fallback is used)
            AvatarView(
                initials: FriendItem.makeInitials(
                    entry.isCurrentUser
                        ? entry.displayLabel.replacingOccurrences(of: " (You)", with: "")
                        : entry.displayLabel
                ),
                size: 36
            )

            // Name
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: AppSpacing.xxs) {
                    Text(entry.isCurrentUser
                         ? entry.displayLabel.replacingOccurrences(of: " (You)", with: "")
                         : entry.displayLabel)
                        .font(AppTypography.bodySemibold)
                        .foregroundStyle(entry.isCurrentUser ? AppColors.primary : AppColors.textPrimary)
                    if entry.isCurrentUser {
                        Text("You")
                            .font(AppTypography.caption2)
                            .foregroundStyle(AppColors.primary)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(AppColors.primary.opacity(0.12), in: Capsule())
                    }
                }
                if let sub = entry.usernameLabel {
                    Text(sub)
                        .font(AppTypography.caption1)
                        .foregroundStyle(AppColors.textSecondary)
                }
            }

            Spacer()

            // Activity score
            VStack(alignment: .trailing, spacing: 1) {
                Text("\(entry.activityPoints)")
                    .font(AppTypography.headline)
                    .foregroundStyle(entry.isCurrentUser ? AppColors.primary : AppColors.textPrimary)
                Text("activity")
                    .font(AppTypography.caption2)
                    .foregroundStyle(AppColors.textSecondary)
            }
        }
        .padding(.horizontal, AppSpacing.md)
        .padding(.vertical, AppSpacing.sm)
        .background(
            entry.isCurrentUser
                ? AppColors.primary.opacity(0.08)
                : AppColors.backgroundSecondary,
            in: RoundedRectangle(cornerRadius: AppSpacing.cornerRadiusLarge)
        )

        if entry.isCurrentUser {
            return AnyView(content)
        } else {
            return AnyView(
                NavigationLink {
                    FriendStatsView(
                        viewModel: viewModel,
                        friendId: entry.id,
                        friendName: entry.displayLabel
                    )
                } label: {
                    content
                }
                .buttonStyle(.plain)
            )
        }
    }

    // MARK: Leaderboard states

    private var leaderboardSkeleton: some View {
        VStack(spacing: AppSpacing.xs) {
            ForEach(0..<3, id: \.self) { _ in
                RoundedRectangle(cornerRadius: AppSpacing.cornerRadiusCard)
                    .fill(AppColors.backgroundSecondary)
                    .frame(height: 60)
                    .shimmer()
            }
        }
    }

    private func leaderboardError(_ message: String) -> some View {
        Card(hasShadow: false) {
            HStack(spacing: AppSpacing.sm) {
                Image(systemName: "exclamationmark.triangle")
                    .foregroundStyle(AppColors.error)
                Text(message)
                    .font(AppTypography.caption1)
                    .foregroundStyle(AppColors.textSecondary)
                Spacer()
                Button("Retry") { viewModel.loadLeaderboard() }
                    .font(AppTypography.captionSemibold)
                    .foregroundStyle(AppColors.primary)
            }
        }
    }

    private var leaderboardEmpty: some View {
        Card(hasShadow: false) {
            VStack(spacing: AppSpacing.sm) {
                Image(systemName: "trophy")
                    .font(.system(size: 36, weight: .light))
                    .foregroundStyle(AppColors.textTertiary)
                Text("No activity board yet")
                    .font(AppTypography.headline)
                    .foregroundStyle(AppColors.textPrimary)
                Text("Add friends to compare overall activity, consistency, and momentum.")
                    .font(AppTypography.caption1)
                    .foregroundStyle(AppColors.textSecondary)
                    .multilineTextAlignment(.center)
                Button {
                    showAddFriend = true
                } label: {
                    Label("Add Friends", systemImage: "person.badge.plus")
                        .font(AppTypography.captionSemibold)
                        .foregroundStyle(AppColors.textOnPrimary)
                        .padding(.horizontal, AppSpacing.md)
                        .padding(.vertical, AppSpacing.xs)
                        .background(AppColors.primary, in: Capsule())
                }
                .buttonStyle(.plain)
                .padding(.top, AppSpacing.xxs)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, AppSpacing.md)
        }
    }

    // MARK: - Friends Section

    @ViewBuilder
    private var friendsSection: some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            HStack {
                Text("Friends")
                    .font(AppTypography.title2)
                    .foregroundStyle(AppColors.textPrimary)

                if !viewModel.friends.isEmpty {
                    Text("\(viewModel.friends.count)")
                        .font(AppTypography.caption2)
                        .fontWeight(.bold)
                        .foregroundStyle(AppColors.textSecondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(AppColors.backgroundTertiary, in: Capsule())
                }

                Spacer()
            }

            if viewModel.isLoadingFriends && viewModel.friends.isEmpty {
                friendsSkeleton
            } else if let error = viewModel.friendsError {
                friendsError(error)
            } else if viewModel.friends.isEmpty {
                friendsEmpty
            } else {
                friendsList
            }
        }
    }

    private var friendsList: some View {
        VStack(spacing: AppSpacing.xs) {
            ForEach(viewModel.friends) { friend in
                FriendHubRow(
                    friend: friend,
                    isRemoving: viewModel.removingIds.contains(friend.id),
                    onRemove: { viewModel.removeFriend(friend.id) },
                    destination: {
                        FriendStatsView(
                            viewModel: viewModel,
                            friendId: friend.id,
                            friendName: friend.displayLabel
                        )
                    }
                )
            }
        }
    }

    private var friendsSkeleton: some View {
        VStack(spacing: AppSpacing.xs) {
            ForEach(0..<3, id: \.self) { _ in
                RoundedRectangle(cornerRadius: AppSpacing.cornerRadiusCard)
                    .fill(AppColors.backgroundSecondary)
                    .frame(height: 64)
                    .shimmer()
            }
        }
    }

    private func friendsError(_ message: String) -> some View {
        Card(hasShadow: false) {
            HStack(spacing: AppSpacing.sm) {
                Image(systemName: "exclamationmark.triangle")
                    .foregroundStyle(AppColors.error)
                Text(message)
                    .font(AppTypography.caption1)
                    .foregroundStyle(AppColors.textSecondary)
                Spacer()
                Button("Retry") { viewModel.loadFriends() }
                    .font(AppTypography.captionSemibold)
                    .foregroundStyle(AppColors.primary)
            }
        }
    }

    private var friendsEmpty: some View {
        Card(hasShadow: false) {
            VStack(spacing: AppSpacing.sm) {
                Image(systemName: "person.2")
                    .font(.system(size: 36, weight: .light))
                    .foregroundStyle(AppColors.textTertiary)
                Text("No friends yet")
                    .font(AppTypography.headline)
                    .foregroundStyle(AppColors.textPrimary)
                Text("Build your circle, compare activity, and inspect how each friend is progressing.")
                    .font(AppTypography.caption1)
                    .foregroundStyle(AppColors.textSecondary)
                    .multilineTextAlignment(.center)
                Button {
                    showAddFriend = true
                } label: {
                    Label("Find Friends", systemImage: "magnifyingglass")
                        .font(AppTypography.captionSemibold)
                        .foregroundStyle(AppColors.textOnPrimary)
                        .padding(.horizontal, AppSpacing.md)
                        .padding(.vertical, AppSpacing.xs)
                        .background(AppColors.primary, in: Capsule())
                }
                .buttonStyle(.plain)
                .padding(.top, AppSpacing.xxs)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, AppSpacing.md)
        }
    }
}

// MARK: - PodiumView

/// Displays the top 3 leaderboard entries as a visual podium.
private struct PodiumView: View {

    let entries: [LeaderboardEntry]
    let viewModel: FriendsViewModel

    private struct PodiumItem: Identifiable {
        let entry: LeaderboardEntry
        var id: String { entry.id }
        var rank: Int { entry.rank }
    }

    /// Reorders entries for the classic podium layout: 2nd (left), 1st (center), 3rd (right).
    /// When multiple entries share the same rank they are grouped together in that slot.
    private var orderedItems: [PodiumItem] {
        let rank1 = entries.filter { $0.rank == 1 }.map { PodiumItem(entry: $0) }
        let rank2 = entries.filter { $0.rank == 2 }.map { PodiumItem(entry: $0) }
        let rank3 = entries.filter { $0.rank == 3 }.map { PodiumItem(entry: $0) }
        // Layout: [rank2...] [rank1...] [rank3...]
        return rank2 + rank1 + rank3
    }

    var body: some View {
        HStack(alignment: .bottom, spacing: AppSpacing.xs) {
            ForEach(orderedItems) { item in
                podiumColumn(rank: item.rank, entry: item.entry)
            }
        }
        .padding(.horizontal, AppSpacing.xs)
    }

    private func podiumColumn(rank: Int, entry: LeaderboardEntry) -> some View {
        let isFirst = rank == 1
        let podiumHeight: CGFloat = isFirst ? 72 : (rank == 2 ? 52 : 44)
        let avatarSize: CGFloat = isFirst ? 52 : 40
        let rankColor = Self.rankColor(rank)
        let displayName = entry.isCurrentUser
            ? entry.displayLabel.replacingOccurrences(of: " (You)", with: "")
            : entry.displayLabel

        return VStack(spacing: AppSpacing.xxs) {
            // Crown for 1st
            if isFirst {
                Image(systemName: "crown.fill")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(Color(light: "#FFD700", dark: "#FFD700"))
            }

            // Avatar -- tappable for non-self entries
            Group {
                if entry.isCurrentUser {
                    podiumAvatar(displayName: displayName, avatarSize: avatarSize,
                                 rankColor: rankColor, isFirst: isFirst)
                } else {
                    NavigationLink {
                        FriendStatsView(
                            viewModel: viewModel,
                            friendId: entry.id,
                            friendName: displayName
                        )
                    } label: {
                        podiumAvatar(displayName: displayName, avatarSize: avatarSize,
                                     rankColor: rankColor, isFirst: isFirst)
                    }
                    .buttonStyle(.plain)
                }
            }

            // Name
            Text(displayName)
                .font(isFirst ? AppTypography.captionSemibold : AppTypography.caption2)
                .foregroundStyle(AppColors.textPrimary)
                .lineLimit(1)
                .frame(maxWidth: .infinity)

            // Activity score
            Text("\(entry.activityPoints)")
                .font(isFirst ? AppTypography.subheadlineSemibold : AppTypography.captionSemibold)
                .foregroundStyle(rankColor)

            // Podium block
            RoundedRectangle(cornerRadius: AppSpacing.xs)
                .fill(rankColor.opacity(0.15))
                .frame(height: podiumHeight)
                .overlay(alignment: .center) {
                    Text("\(rank)")
                        .font(.system(size: isFirst ? 22 : 17, weight: .bold, design: .rounded))
                        .foregroundStyle(rankColor)
                }
        }
        .frame(maxWidth: .infinity)
    }

    private func podiumAvatar(
        displayName: String,
        avatarSize: CGFloat,
        rankColor: Color,
        isFirst: Bool
    ) -> some View {
        ZStack {
            Circle()
                .fill(rankColor.opacity(0.15))
                .frame(width: avatarSize, height: avatarSize)
            Text(String(displayName.prefix(1)).uppercased())
                .font(.system(
                    size: isFirst ? 22 : 17,
                    weight: .bold,
                    design: .rounded
                ))
                .foregroundStyle(rankColor)

            if isFirst {
                Circle()
                    .strokeBorder(rankColor, lineWidth: 2.5)
                    .frame(width: avatarSize, height: avatarSize)
            }
        }
    }

    static func rankColor(_ rank: Int) -> Color {
        switch rank {
        case 1: return Color(light: "#FFD700", dark: "#FFD700")
        case 2: return Color(light: "#A8A8A8", dark: "#C0C0C0")
        case 3: return Color(light: "#CD7F32", dark: "#CD7F32")
        default: return AppColors.primary
        }
    }
}

// MARK: - FriendHubRow

/// A single friend row in the hub friends list with swipe-to-remove.
private struct FriendHubRow<Destination: View>: View {

    let friend: FriendItem
    let isRemoving: Bool
    let onRemove: () -> Void
    @ViewBuilder let destination: () -> Destination

    @State private var showRemoveConfirm = false

    var body: some View {
        NavigationLink(destination: { destination() }) {
            HStack(spacing: AppSpacing.sm) {
                AvatarView(
                    url: friend.avatarUrl.flatMap { URL(string: $0) },
                    initials: friend.initials,
                    size: 44
                )

                VStack(alignment: .leading, spacing: 3) {
                    Text(friend.displayLabel)
                        .font(AppTypography.bodySemibold)
                        .foregroundStyle(AppColors.textPrimary)

                    HStack(spacing: AppSpacing.xxs) {
                        if let rank = friend.leaderboardRank {
                            rankBadge(rank)
                        }
                        if let level = friend.currentLevel {
                            levelBadge(level)
                        }
                        if let streak = friend.currentStreak, streak > 0 {
                            streakBadge(streak)
                        }
                        // Show @username as fallback when no badges are loaded yet
                        if friend.currentLevel == nil,
                           (friend.currentStreak ?? 0) == 0,
                           let sub = friend.usernameLabel {
                            Text(sub)
                                .font(AppTypography.caption1)
                                .foregroundStyle(AppColors.textSecondary)
                        }
                    }
                }

                Spacer()

                if isRemoving {
                    ProgressView().scaleEffect(0.8)
                } else {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(AppColors.textTertiary)
                }
            }
            .padding(.horizontal, AppSpacing.md)
            .padding(.vertical, AppSpacing.sm)
            .background(
                LinearGradient(
                    colors: [AppColors.backgroundSecondary, AppColors.backgroundSecondary.opacity(0.92)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                in: RoundedRectangle(cornerRadius: AppSpacing.cornerRadiusLarge)
            )
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button(role: .destructive) {
                showRemoveConfirm = true
            } label: {
                Label("Remove Friend", systemImage: "person.badge.minus")
            }
        }
        .confirmationDialog(
            "Remove \(friend.displayLabel)?",
            isPresented: $showRemoveConfirm,
            titleVisibility: .visible
        ) {
            Button("Remove", role: .destructive) { onRemove() }
            Button("Cancel", role: .cancel) {}
        }
    }

    // MARK: - Badge helpers

    private func rankBadge(_ rank: Int) -> some View {
        HStack(spacing: 2) {
            Image(systemName: "chart.bar.fill")
                .font(.system(size: 9, weight: .bold))
            Text("#\(rank)")
                .font(.system(size: 10, weight: .bold, design: .rounded))
        }
        .foregroundStyle(AppColors.info)
        .padding(.horizontal, 5)
        .padding(.vertical, 2)
        .background(AppColors.info.opacity(0.12), in: Capsule())
    }

    private func levelBadge(_ level: Int) -> some View {
        HStack(spacing: 2) {
            Image(systemName: "star.fill")
                .font(.system(size: 9, weight: .bold))
            Text("Lvl \(level)")
                .font(.system(size: 10, weight: .bold, design: .rounded))
        }
        .foregroundStyle(AppColors.primary)
        .padding(.horizontal, 5)
        .padding(.vertical, 2)
        .background(AppColors.primary.opacity(0.12), in: Capsule())
    }

    private func streakBadge(_ streak: Int) -> some View {
        HStack(spacing: 2) {
            Image(systemName: "flame.fill")
                .font(.system(size: 9, weight: .bold))
            Text("\(streak)d")
                .font(.system(size: 10, weight: .bold, design: .rounded))
        }
        .foregroundStyle(AppColors.secondary)
        .padding(.horizontal, 5)
        .padding(.vertical, 2)
        .background(AppColors.secondary.opacity(0.12), in: Capsule())
    }
}

// MARK: - AddFriendSheet

/// Bottom sheet for searching users and sending friend requests.
///
/// Contains three tabs:
///   1. Search  -- find users by name / username
///   2. Code    -- enter a friend code
///   3. My Code -- view / share / manage your own friend code
struct AddFriendSheet: View {

    @ObservedObject var viewModel: FriendsViewModel
    @Environment(\.dismiss) private var dismiss

    /// Which tab is currently selected.
    @State private var selectedTab: AddFriendTab = .search

    /// Controls the full-screen My Code sheet.
    @State private var showMyCode = false

    /// Shared ViewModel for friend code operations.
    @StateObject private var codeViewModel = FriendCodeViewModel()

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Tab picker
                tabPicker
                    .padding(.horizontal, AppSpacing.screenHorizontal)
                    .padding(.top, AppSpacing.sm)

                Divider()
                    .padding(.top, AppSpacing.sm)

                // Tab content
                switch selectedTab {
                case .search:
                    searchTabContent
                case .code:
                    codeTabContent
                }
            }
            .background(AppColors.backgroundPrimary)
            .navigationTitle("Add Friend")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    // "My Code" button -- opens the full friend code management sheet
                    Button {
                        showMyCode = true
                    } label: {
                        Label("My Code", systemImage: "qrcode")
                            .font(AppTypography.captionSemibold)
                            .foregroundStyle(AppColors.primary)
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                        .font(AppTypography.bodySemibold)
                        .foregroundStyle(AppColors.primary)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .sheet(isPresented: $showMyCode) {
            FriendCodeView()
        }
        .onAppear {
            // Wire up auto-refresh once: when a friend is added via code,
            // reload the friends list and leaderboard immediately.
            codeViewModel.onFriendAdded = { [weak viewModel] in
                viewModel?.loadFriends()
                viewModel?.loadLeaderboard()
            }
        }
        .onDisappear { viewModel.clearSearch() }
    }

    // MARK: - Tab picker

    private var tabPicker: some View {
        HStack(spacing: AppSpacing.xs) {
            ForEach(AddFriendTab.allCases) { tab in
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) { selectedTab = tab }
                } label: {
                    HStack(spacing: AppSpacing.xxs) {
                        Image(systemName: tab.systemImage)
                            .font(.system(size: 13, weight: .semibold))
                        Text(tab.label)
                            .font(AppTypography.captionSemibold)
                    }
                    .foregroundStyle(selectedTab == tab ? AppColors.textOnPrimary : AppColors.textSecondary)
                    .padding(.horizontal, AppSpacing.sm)
                    .padding(.vertical, AppSpacing.xs)
                    .frame(maxWidth: .infinity)
                    .background(
                        selectedTab == tab ? AppColors.primary : AppColors.backgroundTertiary,
                        in: Capsule()
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Search tab

    private var searchTabContent: some View {
        VStack(spacing: 0) {
            searchBar
                .padding(.horizontal, AppSpacing.screenHorizontal)
                .padding(.vertical, AppSpacing.sm)

            Divider()

            searchResults
        }
    }

    private var searchBar: some View {
        HStack(spacing: AppSpacing.xs) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(AppColors.textSecondary)
                .font(.system(size: AppSpacing.iconSizeSmall))

            TextField("Search by name or username...", text: $viewModel.searchQuery)
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
        .background(AppColors.backgroundTertiary, in: RoundedRectangle(cornerRadius: AppSpacing.cornerRadiusButton))
    }

    @ViewBuilder
    private var searchResults: some View {
        if viewModel.isSearching {
            Spacer()
            ProgressView()
            Spacer()
        } else if let error = viewModel.searchError {
            searchErrorState(message: error)
        } else if viewModel.searchQuery.count >= 2 && viewModel.searchResults.isEmpty {
            searchEmptyState(
                icon: "person.slash",
                title: "No users found",
                message: "Try a different name or username."
            )
        } else if viewModel.searchQuery.count < 2 {
            searchEmptyState(
                icon: "magnifyingglass",
                title: "Find Friends",
                message: "Type at least 2 characters to search."
            )
        } else {
            ScrollView {
                LazyVStack(spacing: AppSpacing.xs) {
                    ForEach(viewModel.searchResults) { user in
                        AddFriendRow(
                            user: user,
                            isSending: viewModel.sendingRequestIds.contains(user.id),
                            onSend: { viewModel.sendFriendRequest(to: user.id) }
                        )
                        .padding(.horizontal, AppSpacing.md)
                        .background(
                            AppColors.backgroundSecondary,
                            in: RoundedRectangle(cornerRadius: AppSpacing.cornerRadiusCard)
                        )
                    }
                }
                .padding(.horizontal, AppSpacing.screenHorizontal)
                .padding(.vertical, AppSpacing.sm)
            }
        }
    }

    private func searchEmptyState(icon: String, title: String, message: String) -> some View {
        VStack(spacing: AppSpacing.md) {
            Spacer()
            Image(systemName: icon)
                .font(.system(size: 44, weight: .light))
                .foregroundStyle(AppColors.textTertiary)
            VStack(spacing: AppSpacing.xs) {
                Text(title)
                    .font(AppTypography.headline)
                    .foregroundStyle(AppColors.textPrimary)
                Text(message)
                    .font(AppTypography.body)
                    .foregroundStyle(AppColors.textSecondary)
                    .multilineTextAlignment(.center)
            }
            Spacer()
        }
        .padding(.horizontal, AppSpacing.xl)
    }

    private func searchErrorState(message: String) -> some View {
        VStack(spacing: AppSpacing.md) {
            Spacer()
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 44, weight: .light))
                .foregroundStyle(AppColors.error)
            Text(message)
                .font(AppTypography.body)
                .foregroundStyle(AppColors.textSecondary)
                .multilineTextAlignment(.center)
            Spacer()
        }
        .padding(.horizontal, AppSpacing.xl)
    }

    // MARK: - Code tab

    private var codeTabContent: some View {
        // standalone=false: the parent AddFriendSheet provides the NavigationStack.
        EnterFriendCodeSheet(viewModel: codeViewModel, standalone: false)
    }
}

// MARK: - AddFriendTab

private enum AddFriendTab: String, CaseIterable, Identifiable {
    case search = "search"
    case code   = "code"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .search: return "Search"
        case .code:   return "Enter Code"
        }
    }

    var systemImage: String {
        switch self {
        case .search: return "magnifyingglass"
        case .code:   return "person.badge.key"
        }
    }
}

// MARK: - AddFriendRow

private struct AddFriendRow: View {

    let user: UserSearchItem
    let isSending: Bool
    let onSend: () -> Void

    var body: some View {
        HStack(spacing: AppSpacing.sm) {
            AvatarView(
                url: user.avatarUrl.flatMap { URL(string: $0) },
                initials: user.initials,
                size: 40
            )

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
                            .font(AppTypography.captionSemibold)
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

// MARK: - RequestsSheet

/// Bottom sheet for managing incoming friend requests.
struct RequestsSheet: View {

    @ObservedObject var viewModel: FriendsViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.isLoadingRequests {
                    VStack { Spacer(); ProgressView(); Spacer() }
                } else if let error = viewModel.requestsError {
                    requestsError(message: error)
                } else if viewModel.incomingRequests.isEmpty {
                    requestsEmpty
                } else {
                    requestsList
                }
            }
            .background(AppColors.backgroundPrimary)
            .navigationTitle("Friend Requests")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                        .font(AppTypography.bodySemibold)
                        .foregroundStyle(AppColors.primary)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
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

    private var requestsList: some View {
        ScrollView {
            LazyVStack(spacing: AppSpacing.xs) {
                ForEach(viewModel.incomingRequests) { request in
                    RequestRow(
                        request: request,
                        isResponding: viewModel.respondingIds.contains(request.id),
                        onAccept: { viewModel.acceptRequest(request.id) },
                        onDecline: { viewModel.declineRequest(request.id) }
                    )
                    .padding(.horizontal, AppSpacing.md)
                    .padding(.vertical, AppSpacing.sm)
                    .background(
                        AppColors.backgroundSecondary,
                        in: RoundedRectangle(cornerRadius: AppSpacing.cornerRadiusCard)
                    )
                }
            }
            .padding(.horizontal, AppSpacing.screenHorizontal)
            .padding(.top, AppSpacing.sm)
            .padding(.bottom, AppSpacing.screenVerticalBottom)
        }
        .refreshable { viewModel.loadIncomingRequests() }
    }

    private var requestsEmpty: some View {
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

    private func requestsError(message: String) -> some View {
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

// MARK: - RequestRow

private struct RequestRow: View {

    let request: FriendRequestItem
    let isResponding: Bool
    let onAccept: () -> Void
    let onDecline: () -> Void

    var body: some View {
        HStack(spacing: AppSpacing.sm) {
            AvatarView(
                url: request.avatarUrl.flatMap { URL(string: $0) },
                initials: request.initials,
                size: 40
            )

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
                            .frame(width: 36, height: 36)
                            .background(AppColors.error.opacity(0.12), in: Circle())
                    }
                    .buttonStyle(.plain)

                    Button(action: onAccept) {
                        Image(systemName: "checkmark")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 36, height: 36)
                            .background(AppColors.success, in: Circle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.vertical, AppSpacing.xs)
    }
}

// MARK: - Shimmer modifier

private extension View {
    func shimmer() -> some View {
        self.modifier(ShimmerModifier())
    }
}

private struct ShimmerModifier: ViewModifier {
    @State private var phase: CGFloat = -1

    func body(content: Content) -> some View {
        content
            .overlay(
                GeometryReader { geo in
                    LinearGradient(
                        stops: [
                            .init(color: .clear, location: 0),
                            .init(color: .white.opacity(0.35), location: 0.4),
                            .init(color: .white.opacity(0.35), location: 0.6),
                            .init(color: .clear, location: 1)
                        ],
                        startPoint: .init(x: phase, y: 0.5),
                        endPoint: .init(x: phase + 1, y: 0.5)
                    )
                    .frame(width: geo.size.width, height: geo.size.height)
                    .clipShape(RoundedRectangle(cornerRadius: AppSpacing.cornerRadiusCard))
                }
            )
            .onAppear {
                withAnimation(.linear(duration: 1.4).repeatForever(autoreverses: false)) {
                    phase = 1
                }
            }
    }
}

// MARK: - FriendStatsPeriod short label

private extension FriendStatsPeriod {
    var shortLabel: String {
        switch self {
        case .day:   return "Day"
        case .week:  return "Week"
        case .month: return "Month"
        }
    }
}

// MARK: - Preview

#if DEBUG
#Preview("FriendsView - Hub") {
    let vm = FriendsViewModel()
    vm.friends = [
        FriendItem(id: "u1", username: "alice", displayName: "Alice Smith", avatarUrl: nil),
        FriendItem(id: "u2", username: "bob", displayName: "Bob Jones", avatarUrl: nil),
        FriendItem(id: "u3", username: "charlie", displayName: "Charlie", avatarUrl: nil)
    ]
    // Demonstrate dense ranking: Alice and Bob are tied at rank 2 (both 185),
    // Charlie is rank 3 (next distinct count).
    vm.leaderboard = [
        LeaderboardEntry(id: "me",  displayLabel: "You",         usernameLabel: nil,      activityPoints: 2100, totalSessions: 14, totalEarnedSeconds: 1260, isCurrentUser: true,  rank: 1),
        LeaderboardEntry(id: "u1",  displayLabel: "Alice Smith", usernameLabel: "@alice", activityPoints: 1850, totalSessions: 12, totalEarnedSeconds: 1110, isCurrentUser: false, rank: 2),
        LeaderboardEntry(id: "u2",  displayLabel: "Bob Jones",   usernameLabel: "@bob",   activityPoints: 1850, totalSessions: 9,  totalEarnedSeconds: 852,  isCurrentUser: false, rank: 2),
        LeaderboardEntry(id: "u3",  displayLabel: "Charlie",     usernameLabel: nil,      activityPoints: 980,  totalSessions: 6,  totalEarnedSeconds: 588,  isCurrentUser: false, rank: 3)
    ]
    return FriendsView(viewModel: vm)
}

#Preview("FriendsView - Empty") {
    FriendsView(viewModel: FriendsViewModel())
}
#endif
