import SwiftUI

struct CrewRunView: View {

    @ObservedObject var viewModel: JoggingViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var displayedMonth: Date = Calendar.current.startOfDay(for: Date())
    @State private var selectedDay: Date?

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
                        calendarCard
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
                syncCalendarSelection()
            }
            .onChange(of: viewModel.upcomingRuns) { _, _ in
                syncCalendarSelection()
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
                    crewModeButton(
                        mode: .solo,
                        title: "Solo",
                        icon: "figure.run"
                    )
                    crewModeButton(
                        mode: .crew,
                        title: "Crew",
                        icon: "person.3.fill"
                    )
                }

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

                Text(viewModel.plannedRunStatusMessage ?? "Create a run now and invite people later if needed.")
                    .font(AppTypography.caption1)
                    .foregroundStyle(AppColors.textSecondary)
            }
        }
    }

    private var upcomingRunsCard: some View {
        VStack(alignment: .leading, spacing: AppSpacing.md) {
            HStack {
                HStack(spacing: 10) {
                    Image(systemName: "calendar")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(Color.white.opacity(0.42))
                    Text("Upcoming")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(.white)
                }

                Spacer()

                Text("\(viewModel.upcomingRuns.count)")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Color.white.opacity(0.42))
            }

            if viewModel.upcomingRuns.isEmpty {
                Text("No planned runs yet.")
                    .font(AppTypography.caption1)
                    .foregroundStyle(Color.white.opacity(0.46))
            } else {
                VStack(spacing: AppSpacing.sm) {
                    ForEach(Array(viewModel.upcomingRuns.enumerated()), id: \.element.id) { index, run in
                        crewUpcomingRow(
                            run: run,
                            showsConnector: index != viewModel.upcomingRuns.count - 1
                        )
                    }
                }
            }
        }
        .padding(20)
        .background(Color(red: 0.06, green: 0.06, blue: 0.06), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.white.opacity(0.10), lineWidth: 1)
        )
    }

    private var calendarCard: some View {
        Card {
            VStack(alignment: .leading, spacing: AppSpacing.md) {
                sectionHeader("Calendar", subtitle: "See when your planned crew runs actually happen")

                HStack {
                    Button {
                        shiftMonth(by: -1)
                    } label: {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(AppColors.textPrimary)
                            .frame(width: 34, height: 34)
                            .background(AppColors.backgroundPrimary, in: Circle())
                    }
                    .buttonStyle(.plain)

                    Spacer()

                    Text(monthTitle(for: displayedMonth))
                        .font(AppTypography.bodySemibold)
                        .foregroundStyle(AppColors.textPrimary)

                    Spacer()

                    Button {
                        shiftMonth(by: 1)
                    } label: {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(AppColors.textPrimary)
                            .frame(width: 34, height: 34)
                            .background(AppColors.backgroundPrimary, in: Circle())
                    }
                    .buttonStyle(.plain)
                }

                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 7), spacing: 8) {
                    ForEach(Self.weekdaySymbols, id: \.self) { symbol in
                        Text(symbol)
                            .font(AppTypography.caption2)
                            .foregroundStyle(AppColors.textSecondary)
                            .frame(maxWidth: .infinity)
                    }

                    ForEach(monthGridDays(), id: \.self) { date in
                        if Calendar.current.isDate(date, equalTo: displayedMonth, toGranularity: .month) {
                            calendarDayCell(date)
                        } else {
                            Color.clear
                                .frame(height: 42)
                        }
                    }
                }

                VStack(alignment: .leading, spacing: AppSpacing.sm) {
                    Text(selectedDay == nil ? "Selected day" : dayTitle(for: selectedDay!))
                        .font(AppTypography.bodySemibold)
                        .foregroundStyle(AppColors.textPrimary)

                    let dayRuns = selectedDay.map { viewModel.upcomingRuns(on: $0) } ?? []
                    if dayRuns.isEmpty {
                        emptyState("No joined or planned runs on this day.")
                    } else {
                        ForEach(dayRuns) { run in
                            optionRow(
                                initials: "EV",
                                title: run.title,
                                subtitle: run.subtitle,
                                actionTitle: viewModel.upcomingRunPrimaryActionTitle(for: run),
                                actionTint: AppColors.secondary
                            ) {
                                viewModel.handleUpcomingRunPrimaryAction(run)
                            }
                        }
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

    private func crewModeButton(
        mode: RunLaunchMode,
        title: String,
        icon: String
    ) -> some View {
        let isSelected = viewModel.launchMode == mode

        return Button {
            viewModel.setLaunchMode(mode)
        } label: {
            HStack(spacing: AppSpacing.sm) {
                Image(systemName: icon)
                    .font(.system(size: 15, weight: .bold))
                Text(title)
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 16, weight: .bold))
                }
            }
            .foregroundStyle(.white)
            .padding(.horizontal, AppSpacing.md)
            .padding(.vertical, AppSpacing.sm)
            .frame(maxWidth: .infinity)
            .background(
                isSelected
                    ? (mode == .solo ? Color(red: 0.13, green: 0.70, blue: 0.36) : Color(red: 0.95, green: 0.44, blue: 0.23))
                    : Color.white.opacity(0.12),
                in: RoundedRectangle(cornerRadius: AppSpacing.cornerRadiusButton)
            )
        }
        .buttonStyle(.plain)
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

            if participant.status == .invited,
               viewModel.selectedLiveRunSessionId == nil,
               viewModel.selectedUpcomingEventId == nil {
                Button("Revoke") {
                    viewModel.removeInvitedParticipant(participant.id)
                }
                .font(AppTypography.captionSemibold)
                .foregroundStyle(AppColors.error)
                .buttonStyle(.plain)
                .padding(.trailing, AppSpacing.xs)
            }

            statusChip(participant.status == .running ? "Running" : "Invited", tint: participant.status == .running ? AppColors.success : AppColors.warning)
        }
        .padding(.vertical, 2)
    }

    private func crewUpcomingRow(run: UpcomingRunOption, showsConnector: Bool) -> some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(spacing: 0) {
                Circle()
                    .fill(Color.white.opacity(0.20))
                    .frame(width: 16, height: 16)
                    .overlay(Circle().stroke(Color.white.opacity(0.40), lineWidth: 2))

                if showsConnector {
                    Rectangle()
                        .fill(Color.white.opacity(0.10))
                        .frame(width: 1, height: 64)
                        .padding(.top, 4)
                }
            }
            .frame(width: 16)

            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .top) {
                    Text(run.title)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white)

                    Spacer()

                    HStack(spacing: 4) {
                        Image(systemName: "person.2")
                            .font(.system(size: 12, weight: .medium))
                        Text("\(run.participantCount)")
                            .font(.system(size: 12, weight: .medium))
                    }
                    .foregroundStyle(Color.white.opacity(0.40))
                }

                Text(Self.upcomingDateFormatter.string(from: run.plannedStartAt))
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Color.white.opacity(0.40))

                HStack {
                    HStack(spacing: 6) {
                        Image(systemName: "figure.run")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(Color.white.opacity(0.40))
                        Text((run.status?.replacingOccurrences(of: "_", with: " ").capitalized).flatMap { $0.isEmpty ? nil : $0 } ?? "Crew run")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(Color.white.opacity(0.60))
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color.white.opacity(0.05), in: Capsule())

                    Spacer()

                    Button {
                        viewModel.handleUpcomingRunPrimaryAction(run)
                    } label: {
                        Text(viewModel.upcomingRunPrimaryActionTitle(for: run))
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                            .background(AppColors.secondary, in: Capsule())
                    }
                    .buttonStyle(.plain)
                }

                if run.status?.uppercased() == "INVITED" {
                    Button("Decline") {
                        viewModel.declineUpcomingRun(run.id)
                    }
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color.white.opacity(0.40))
                    .buttonStyle(.plain)
                }
            }
        }
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

    private func shiftMonth(by delta: Int) {
        displayedMonth = Calendar.current.date(byAdding: .month, value: delta, to: displayedMonth) ?? displayedMonth
        syncCalendarSelection()
    }

    private func syncCalendarSelection() {
        let calendar = Calendar.current
        let monthRuns = viewModel.upcomingRuns
            .filter { calendar.isDate($0.plannedStartAt, equalTo: displayedMonth, toGranularity: .month) }
            .sorted { $0.plannedStartAt < $1.plannedStartAt }
        if let current = selectedDay,
           calendar.isDate(current, equalTo: displayedMonth, toGranularity: .month) {
            return
        }
        selectedDay = monthRuns.first.map { calendar.startOfDay(for: $0.plannedStartAt) }
            ?? calendar.date(from: calendar.dateComponents([.year, .month], from: displayedMonth))
    }

    private func monthGridDays() -> [Date] {
        let calendar = Calendar.current
        guard
            let monthInterval = calendar.dateInterval(of: .month, for: displayedMonth),
            let firstWeekInterval = calendar.dateInterval(of: .weekOfMonth, for: monthInterval.start),
            let lastDay = calendar.date(byAdding: .day, value: -1, to: monthInterval.end),
            let lastWeekInterval = calendar.dateInterval(of: .weekOfMonth, for: lastDay)
        else {
            return []
        }

        var days: [Date] = []
        var current = firstWeekInterval.start
        while current < lastWeekInterval.end {
            days.append(current)
            current = calendar.date(byAdding: .day, value: 1, to: current) ?? lastWeekInterval.end
        }
        return days
    }

    private func calendarDayCell(_ date: Date) -> some View {
        let calendar = Calendar.current
        let normalized = calendar.startOfDay(for: date)
        let isSelected = selectedDay.map { calendar.isDate($0, inSameDayAs: normalized) } ?? false
        let hasEvent = viewModel.calendarHighlightedDates.contains(normalized)
        let isToday = calendar.isDateInToday(normalized)

        return Button {
            selectedDay = normalized
        } label: {
            VStack(spacing: 4) {
                Text("\(calendar.component(.day, from: normalized))")
                    .font(AppTypography.captionSemibold)
                    .foregroundStyle(isSelected ? Color.white : AppColors.textPrimary)

                Circle()
                    .fill(hasEvent ? (isSelected ? Color.white : AppColors.secondary) : Color.clear)
                    .frame(width: 6, height: 6)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 42)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(
                        isSelected
                        ? AppColors.secondary
                        : (isToday ? AppColors.info.opacity(0.10) : AppColors.backgroundPrimary)
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(isToday && !isSelected ? AppColors.info.opacity(0.35) : Color.clear, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private func monthTitle(for date: Date) -> String {
        Self.monthTitleFormatter.string(from: date)
    }

    private func dayTitle(for date: Date) -> String {
        Self.dayTitleFormatter.string(from: date)
    }

    private static let weekdaySymbols: [String] = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US")
        return formatter.shortStandaloneWeekdaySymbols
    }()

    private static let monthTitleFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM yyyy"
        formatter.locale = Locale(identifier: "en_US")
        return formatter
    }()

    private static let dayTitleFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE, MMM d"
        formatter.locale = Locale(identifier: "en_US")
        return formatter
    }()

    private static let upcomingDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd • HH:mm"
        formatter.locale = Locale(identifier: "en_US")
        return formatter
    }()
}
