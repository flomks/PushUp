import SwiftUI

struct CrewRunView: View {

    @ObservedObject var viewModel: JoggingViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                AppColors.backgroundPrimary
                    .ignoresSafeArea()

                ScrollView {
                    VStack(spacing: AppSpacing.md) {
                        headerCard

                        if viewModel.selectedLiveRunSessionId != nil || viewModel.lastDetachedLiveRunSessionId != nil {
                            liveStatusCard
                        }

                        participantsCard
                        liveRunsCard
                        plannedRunCard
                        upcomingRunsCard
                        inviteFriendsCard
                    }
                    .padding(.horizontal, AppSpacing.screenHorizontal)
                    .padding(.top, AppSpacing.md)
                    .padding(.bottom, AppSpacing.screenVerticalBottom)
                }
                .scrollIndicators(.hidden)

                if viewModel.isLoadingRunSocialData {
                    loadingOverlay
                }
            }
            .navigationTitle("Crew Run")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close") { dismiss() }
                }
            }
            .task {
                await viewModel.loadRunSocialData()
            }
        }
    }

    private var headerCard: some View {
        ZStack(alignment: .bottomLeading) {
            RoundedRectangle(cornerRadius: AppSpacing.cornerRadiusLarge)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.10, green: 0.18, blue: 0.30),
                            Color(red: 0.12, green: 0.39, blue: 0.55),
                            Color(red: 0.95, green: 0.44, blue: 0.23)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay(alignment: .topTrailing) {
                    Circle()
                        .fill(Color.white.opacity(0.10))
                        .frame(width: 160, height: 160)
                        .offset(x: 30, y: -30)
                }

            VStack(alignment: .leading, spacing: AppSpacing.md) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: AppSpacing.xxs) {
                        Text("CREW")
                            .font(.system(size: 12, weight: .bold, design: .rounded))
                            .foregroundStyle(Color.white.opacity(0.72))
                            .tracking(2)

                        Text("Manage your running group in one place.")
                            .font(.system(size: 28, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                            .lineLimit(3)
                    }

                    Spacer(minLength: 12)

                    Image(systemName: "person.3.fill")
                        .font(.system(size: 28, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(14)
                        .background(Color.white.opacity(0.14), in: Circle())
                }

                Text(viewModel.socialSelectionSummary)
                    .font(AppTypography.body)
                    .foregroundStyle(Color.white.opacity(0.86))

                HStack(spacing: AppSpacing.sm) {
                    crewMetric(title: "Lineup", value: "\(viewModel.runParticipants.count)")
                    crewMetric(title: "Live", value: "\(viewModel.activeFriendRuns.count)")
                    crewMetric(title: "Upcoming", value: "\(viewModel.upcomingRuns.count)")
                }
            }
            .padding(AppSpacing.lg)
        }
    }

    private var liveStatusCard: some View {
        Card {
            VStack(alignment: .leading, spacing: AppSpacing.md) {
                sectionHeader("Live Status", subtitle: "Current crew session controls")

                if viewModel.selectedLiveRunSessionId != nil {
                    Text(viewModel.activeRunStateLabel ?? "You are connected to a live crew run.")
                        .font(AppTypography.body)
                        .foregroundStyle(AppColors.textSecondary)

                    actionButton(
                        title: viewModel.isLeavingLiveRun ? "Leaving..." : "Leave Crew",
                        tint: AppColors.error,
                        isLoading: viewModel.isLeavingLiveRun,
                        disabled: viewModel.isLeavingLiveRun
                    ) {
                        viewModel.leaveCurrentLiveRun()
                    }
                } else if viewModel.lastDetachedLiveRunSessionId != nil {
                    Text("Your own run continues. Rejoin reconnects the social session without interrupting tracking.")
                        .font(AppTypography.body)
                        .foregroundStyle(AppColors.textSecondary)

                    actionButton(
                        title: viewModel.isRejoiningLiveRun ? "Rejoining..." : "Rejoin Crew",
                        tint: AppColors.secondary,
                        isLoading: viewModel.isRejoiningLiveRun,
                        disabled: viewModel.isRejoiningLiveRun
                    ) {
                        viewModel.rejoinLastLiveRun()
                    }
                }
            }
        }
    }

    private var participantsCard: some View {
        Card {
            VStack(alignment: .leading, spacing: AppSpacing.md) {
                sectionHeader("Crew Lineup", subtitle: "Who is running or already invited")

                if viewModel.runParticipants.isEmpty {
                    emptyState("No crew selected yet.")
                } else {
                    ForEach(viewModel.runParticipants) { participant in
                        participantRow(participant)
                    }
                }
            }
        }
    }

    private var liveRunsCard: some View {
        Card {
            VStack(alignment: .leading, spacing: AppSpacing.md) {
                sectionHeader("Live Runs", subtitle: "Join a crew that is already moving")

                if viewModel.activeFriendRuns.isEmpty {
                    emptyState("No live friend runs right now.")
                } else {
                    ForEach(viewModel.activeFriendRuns) { run in
                        optionRow(
                            initials: "LR",
                            title: run.title,
                            subtitle: run.subtitle,
                            actionTitle: viewModel.selectedLiveRunSessionId == run.id ? "Selected" : "Join",
                            actionTint: viewModel.selectedLiveRunSessionId == run.id ? AppColors.info : AppColors.secondary
                        ) {
                            viewModel.selectActiveRun(run.id)
                        }
                    }
                }
            }
        }
    }

    private var plannedRunCard: some View {
        Card {
            VStack(alignment: .leading, spacing: AppSpacing.md) {
                sectionHeader("Plan a Run", subtitle: "Create a proper event instead of an inline popup")

                VStack(alignment: .leading, spacing: AppSpacing.xs) {
                    Text("Title")
                        .font(AppTypography.captionSemibold)
                        .foregroundStyle(AppColors.textSecondary)

                    TextField("Crew sunrise run", text: $viewModel.plannedRunTitle)
                        .textInputAutocapitalization(.words)
                        .padding(.horizontal, AppSpacing.md)
                        .frame(height: AppSpacing.buttonHeightPrimary)
                        .background(AppColors.backgroundTertiary, in: RoundedRectangle(cornerRadius: AppSpacing.cornerRadiusButton))
                }

                VStack(alignment: .leading, spacing: AppSpacing.xs) {
                    Text("Start time")
                        .font(AppTypography.captionSemibold)
                        .foregroundStyle(AppColors.textSecondary)

                    DatePicker(
                        "",
                        selection: $viewModel.plannedRunDate,
                        displayedComponents: [.date, .hourAndMinute]
                    )
                    .labelsHidden()
                    .datePickerStyle(.compact)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, AppSpacing.md)
                    .frame(height: AppSpacing.buttonHeightPrimary)
                    .background(AppColors.backgroundTertiary, in: RoundedRectangle(cornerRadius: AppSpacing.cornerRadiusButton))
                }

                actionButton(
                    title: viewModel.isCreatingPlannedRun ? "Creating..." : "Create Planned Run",
                    tint: AppColors.secondary,
                    isLoading: viewModel.isCreatingPlannedRun,
                    disabled: !viewModel.canCreatePlannedRun || viewModel.isCreatingPlannedRun
                ) {
                    viewModel.createPlannedRun()
                }

                Text(viewModel.plannedRunStatusMessage ?? "Uses the currently invited crew as the event lineup.")
                    .font(AppTypography.caption1)
                    .foregroundStyle(AppColors.textSecondary)
            }
        }
    }

    private var upcomingRunsCard: some View {
        Card {
            VStack(alignment: .leading, spacing: AppSpacing.md) {
                sectionHeader("Upcoming Runs", subtitle: "Accepted, invited, and ready-to-start sessions")

                if viewModel.upcomingRuns.isEmpty {
                    emptyState("No planned runs yet.")
                } else {
                    ForEach(viewModel.upcomingRuns) { run in
                        VStack(alignment: .leading, spacing: AppSpacing.sm) {
                            optionRow(
                                initials: "EV",
                                title: run.title,
                                subtitle: run.subtitle,
                                actionTitle: viewModel.upcomingRunPrimaryActionTitle(for: run),
                                actionTint: AppColors.secondary
                            ) {
                                viewModel.handleUpcomingRunPrimaryAction(run)
                            }

                            HStack(spacing: AppSpacing.xs) {
                                if let status = run.status {
                                    statusChip(status.replacingOccurrences(of: "_", with: " ").capitalized)
                                }

                                Spacer()

                                if run.status?.uppercased() == "INVITED" {
                                    Button("Decline") {
                                        viewModel.declineUpcomingRun(run.id)
                                    }
                                    .font(AppTypography.captionSemibold)
                                    .foregroundStyle(AppColors.textSecondary)
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                        .padding(.vertical, AppSpacing.xxs)
                    }
                }
            }
        }
    }

    private var inviteFriendsCard: some View {
        Card {
            VStack(alignment: .leading, spacing: AppSpacing.md) {
                sectionHeader("Invite Friends", subtitle: "Add runners to the lineup or the live session")

                if viewModel.inviteableFriends.isEmpty {
                    emptyState("No friends available to invite.")
                } else {
                    ForEach(viewModel.inviteableFriends) { friend in
                        HStack(spacing: AppSpacing.sm) {
                            avatar(friend.initials)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(friend.displayName)
                                    .font(AppTypography.bodySemibold)
                                    .foregroundStyle(AppColors.textPrimary)

                                if let username = friend.username {
                                    Text("@\(username)")
                                        .font(AppTypography.caption1)
                                        .foregroundStyle(AppColors.textSecondary)
                                }
                            }

                            Spacer()

                            Button {
                                viewModel.inviteFriendToRun(friend.id)
                            } label: {
                                HStack(spacing: AppSpacing.xs) {
                                    if viewModel.isInvitingToLiveRun && viewModel.selectedLiveRunSessionId != nil {
                                        ProgressView()
                                            .tint(.white)
                                    }
                                    Text("Invite")
                                        .font(AppTypography.captionSemibold)
                                }
                                .foregroundStyle(.white)
                                .padding(.horizontal, AppSpacing.md)
                                .padding(.vertical, AppSpacing.xs)
                                .background(AppColors.secondary, in: Capsule())
                            }
                            .buttonStyle(.plain)
                            .disabled(viewModel.isInvitingToLiveRun && viewModel.selectedLiveRunSessionId != nil)
                        }
                    }
                }
            }
        }
    }

    private var loadingOverlay: some View {
        ZStack {
            Color.black.opacity(0.10)
                .ignoresSafeArea()

            VStack(spacing: AppSpacing.sm) {
                ProgressView()
                    .tint(AppColors.secondary)
                Text("Loading crew...")
                    .font(AppTypography.bodySemibold)
                    .foregroundStyle(AppColors.textPrimary)
            }
            .padding(AppSpacing.lg)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: AppSpacing.cornerRadiusLarge))
        }
    }

    private func sectionHeader(_ title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.xxs) {
            Text(title)
                .font(AppTypography.headline)
                .foregroundStyle(AppColors.textPrimary)
            Text(subtitle)
                .font(AppTypography.caption1)
                .foregroundStyle(AppColors.textSecondary)
        }
    }

    private func crewMetric(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
            Text(title)
                .font(AppTypography.caption1)
                .foregroundStyle(Color.white.opacity(0.72))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, AppSpacing.sm)
        .padding(.vertical, AppSpacing.xs)
        .background(Color.white.opacity(0.12), in: RoundedRectangle(cornerRadius: AppSpacing.cornerRadiusButton))
    }

    private func participantRow(_ participant: RunParticipant) -> some View {
        HStack(spacing: AppSpacing.sm) {
            avatar(participant.initials)

            VStack(alignment: .leading, spacing: 2) {
                Text(participant.displayName)
                    .font(AppTypography.bodySemibold)
                    .foregroundStyle(AppColors.textPrimary)

                if let username = participant.username {
                    Text("@\(username)")
                        .font(AppTypography.caption1)
                        .foregroundStyle(AppColors.textSecondary)
                }
            }

            Spacer()

            statusChip(participant.status == .running ? "Running" : "Invited", tint: participant.status == .running ? AppColors.success : AppColors.warning)
        }
        .padding(.vertical, 2)
    }

    private func optionRow(
        initials: String,
        title: String,
        subtitle: String,
        actionTitle: String,
        actionTint: Color,
        action: @escaping () -> Void
    ) -> some View {
        HStack(spacing: AppSpacing.sm) {
            avatar(initials)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(AppTypography.bodySemibold)
                    .foregroundStyle(AppColors.textPrimary)

                Text(subtitle)
                    .font(AppTypography.caption1)
                    .foregroundStyle(AppColors.textSecondary)
            }

            Spacer()

            Button(action: action) {
                Text(actionTitle)
                    .font(AppTypography.captionSemibold)
                    .foregroundStyle(.white)
                    .padding(.horizontal, AppSpacing.md)
                    .padding(.vertical, AppSpacing.xs)
                    .background(actionTint, in: Capsule())
            }
            .buttonStyle(.plain)
        }
    }

    private func actionButton(
        title: String,
        tint: Color,
        isLoading: Bool,
        disabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: AppSpacing.xs) {
                if isLoading {
                    ProgressView()
                        .tint(.white)
                }
                Text(title)
                    .font(AppTypography.buttonPrimary)
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .frame(height: AppSpacing.buttonHeightPrimary)
            .background(disabled ? AppColors.textTertiary : tint, in: RoundedRectangle(cornerRadius: AppSpacing.cornerRadiusButton))
        }
        .buttonStyle(.plain)
        .disabled(disabled)
    }

    private func avatar(_ initials: String) -> some View {
        Circle()
            .fill(AppColors.secondary.opacity(0.16))
            .frame(width: 38, height: 38)
            .overlay {
                Text(initials)
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(AppColors.secondary)
            }
    }

    private func statusChip(_ text: String, tint: Color = AppColors.info) -> some View {
        Text(text)
            .font(AppTypography.captionSemibold)
            .foregroundStyle(tint)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(tint.opacity(0.14), in: Capsule())
    }

    private func emptyState(_ text: String) -> some View {
        Text(text)
            .font(AppTypography.body)
            .foregroundStyle(AppColors.textSecondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, AppSpacing.xs)
    }
}
