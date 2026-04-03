import SwiftUI
import MapKit
import Shared

// MARK: - JoggingView

/// Full-screen jogging workout view with live stats and route map.
///
/// **Phases**
/// - Idle: Shows a "Start Run" button with location permission check.
/// - Active: Shows live stats (distance, duration, pace, speed) and a route map.
/// - Confirming Stop: Shows a confirmation alert.
/// - Finished: Shows a summary with earned screen time.
struct JoggingView: View {

    @StateObject private var viewModel = JoggingViewModel()
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var showStopConfirmation = false
    @State private var showShareSheet = false
    @State private var showCrewLobby = false
    @State private var showPlannerView = false
    @State private var showMusicSheet = false
    @State private var selectedRecentRun: RunningDashboardData.RecentRun?
    @State private var isMapFocusMode = false
    @State private var shareImage: UIImage?
    @State private var isRenderingShareImage = false
    @State private var mapPosition: MapCameraPosition = .automatic
    @State private var isFollowingRunner = false
    @State private var isCurrentMarkerPulsing = false
    @State private var musicWidgetSwipeOffset: CGFloat = 0
    @State private var spotifyRefreshButtonRotation: Double = 0
    @State private var isSpotifyRefreshButtonPressed = false
#if DEBUG
    /// Temporary: simulates 0→1000 m for ring + DIST only; remove when no longer needed.
#endif

    var body: some View {
        ZStack {
            AppColors.backgroundPrimary
                .ignoresSafeArea()

            switch viewModel.phase {
            case .idle:
                idleView
            case .active, .confirmingStop:
                activeView
            case .finished:
                finishedView
            }
        }
        .alert(viewModel.stopConfirmationTitle, isPresented: $showStopConfirmation) {
            Button("Keep Running", role: .cancel) {
                viewModel.cancelStop()
            }
            Button("End Run", role: .destructive) {
                viewModel.confirmStop()
            }
        } message: {
            Text(viewModel.stopConfirmationMessage)
        }
        .onChange(of: viewModel.phase) { _, newPhase in
            if newPhase == .confirmingStop {
                showStopConfirmation = true
            }
        }
        .fullScreenCover(isPresented: $showCrewLobby) {
            CrewRunView(viewModel: viewModel, screen: .lobby)
        }
        .fullScreenCover(isPresented: $showPlannerView) {
            CrewRunView(viewModel: viewModel, screen: .planner)
        }
        .sheet(isPresented: $showMusicSheet) {
            musicSheet
        }
        .sheet(item: $selectedRecentRun) { run in
            RecentRunDetailSheet(run: run)
        }
    }

    // MARK: - Idle View

    private var idleView: some View {
        ScrollView {
            VStack(spacing: AppSpacing.md) {
                idleTopBar
                    .padding(.top, AppSpacing.md)

                runningHubHero
                primaryActionsCard
                startRunCard
                futureRunsCard
                runningHighlightsCard
                runningPersonalBestCard
                recentRunsCard
            }
            .padding(.horizontal, AppSpacing.screenHorizontal)
            .padding(.bottom, AppSpacing.screenVerticalBottom)
        }
    }

    private var idleTopBar: some View {
        HStack(alignment: .center) {
            Button {
                dismiss()
            } label: {
                HStack(spacing: AppSpacing.xs) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 16, weight: .semibold))
                    Text("Training")
                        .font(AppTypography.bodySemibold)
                }
                .foregroundStyle(AppColors.textSecondary)
                .padding(.horizontal, AppSpacing.md)
                .padding(.vertical, AppSpacing.sm)
                .background(AppColors.backgroundSecondary, in: Capsule())
            }
            .buttonStyle(.plain)

            Spacer()

            HStack(spacing: AppSpacing.xs) {
                Image(systemName: "figure.run")
                    .font(.system(size: 14, weight: .semibold))
                Text("Run Hub")
                    .font(AppTypography.captionSemibold)
            }
            .foregroundStyle(AppColors.info)
            .padding(.horizontal, AppSpacing.sm)
            .padding(.vertical, AppSpacing.xs)
            .background(AppColors.info.opacity(0.10), in: Capsule())
        }
    }

    private var runningHubHero: some View {
        ZStack(alignment: .bottomLeading) {
            RoundedRectangle(cornerRadius: AppSpacing.cornerRadiusLarge + 4)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.97, green: 0.40, blue: 0.22),
                            Color(red: 0.90, green: 0.18, blue: 0.28),
                            Color(red: 0.26, green: 0.08, blue: 0.14)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay(alignment: .topTrailing) {
                    Circle()
                        .fill(Color.white.opacity(0.10))
                        .frame(width: 180, height: 180)
                        .blur(radius: 8)
                        .offset(x: 48, y: -36)
                }
                .overlay(alignment: .bottomTrailing) {
                    Circle()
                        .stroke(Color.white.opacity(0.10), lineWidth: 1)
                        .frame(width: 170, height: 170)
                        .offset(x: 44, y: 50)
                }

            VStack(alignment: .leading, spacing: AppSpacing.md) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: AppSpacing.xxs) {
                        Text("RUNNING")
                            .font(.system(size: 12, weight: .bold, design: .rounded))
                            .foregroundStyle(Color.white.opacity(0.72))
                            .tracking(2)

                        Text("Your next run starts here.")
                            .font(.system(size: 34, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer(minLength: 12)

                    ZStack {
                        Circle()
                            .fill(Color.white.opacity(0.14))
                            .frame(width: 58, height: 58)

                        Image(systemName: "figure.run")
                            .font(.system(size: 28, weight: .semibold))
                            .foregroundStyle(.white)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)

                Text("Built for route tracking, pace control, and repeatable progress. This is the core running surface for the app going forward.")
                    .font(AppTypography.body)
                    .foregroundStyle(Color.white.opacity(0.82))

                HStack(spacing: AppSpacing.sm) {
                    heroMetricPill(
                        title: "This Week",
                        value: formatDistance(viewModel.dashboard.weekDistanceMeters)
                    )
                    heroMetricPill(
                        title: "Runs",
                        value: "\(viewModel.dashboard.weekRuns)"
                    )
                    heroMetricPill(
                        title: "Avg Pace",
                        value: formatPace(viewModel.dashboard.averagePaceSecondsPerKm)
                    )
                }
            }
            .padding(AppSpacing.xl)
        }
        .frame(minHeight: 270)
    }

    private var runningWidgetBackground: LinearGradient {
        LinearGradient(
            colors: [
                Color(red: 0.08, green: 0.08, blue: 0.09),
                Color(red: 0.05, green: 0.05, blue: 0.06)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private var primaryActionsCard: some View {
        VStack(spacing: AppSpacing.md) {
            sectionEyebrow(
                title: "Choose Your Run",
                subtitle: "Choose what kind of run you want to prepare next"
            )

            if !viewModel.hasLocationPermission {
                HStack(spacing: AppSpacing.sm) {
                    Image(systemName: "location.fill")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(AppColors.warning)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Location access required")
                            .font(AppTypography.bodySemibold)
                            .foregroundStyle(.white)
                        Text("Allow location first so route, distance, and pace can be tracked correctly.")
                            .font(AppTypography.caption1)
                            .foregroundStyle(Color.white.opacity(0.60))
                    }

                    Spacer()
                }
                .padding(AppSpacing.md)
                .background(AppColors.warning.opacity(0.08), in: RoundedRectangle(cornerRadius: AppSpacing.cornerRadiusCard))
            }

            VStack(spacing: AppSpacing.sm) {
                hubActionTile(
                    title: "Solo Run",
                    subtitle: "Prepare a normal run and start when you are ready.",
                    icon: "figure.run",
                    accentColor: Color(red: 0.20, green: 0.82, blue: 0.49),
                    isSelected: viewModel.launchMode == .solo
                ) {
                    viewModel.setLaunchMode(.solo)
                }

                HStack(spacing: AppSpacing.sm) {
                    hubActionTile(
                        title: "Crew Run",
                        subtitle: "Open the lobby for live runs, crew lineups, and social starts.",
                        icon: "person.3.fill",
                        accentColor: Color(red: 0.98, green: 0.42, blue: 0.18),
                        isSelected: viewModel.launchMode == .crew
                    ) {
                        viewModel.setLaunchMode(.crew)
                        showCrewLobby = true
                    }

                    hubActionTile(
                        title: "Plan Run",
                        subtitle: viewModel.upcomingEventCountLabel,
                        icon: "calendar.badge.plus",
                        accentColor: Color(red: 0.42, green: 0.55, blue: 0.82),
                        isSelected: false
                    ) {
                        showPlannerView = true
                    }
                }
            }

            HStack(spacing: AppSpacing.sm) {
                quickRunAction(
                    title: "Music",
                    subtitle: viewModel.musicCardSubtitle,
                    icon: "music.note"
                ) {
                    showMusicSheet = true
                }
            }
        }
        .padding(AppSpacing.lg)
        .background(runningWidgetBackground, in: RoundedRectangle(cornerRadius: AppSpacing.cornerRadiusLarge, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: AppSpacing.cornerRadiusLarge, style: .continuous)
                .stroke(Color.white.opacity(0.10), lineWidth: 1)
        )
    }

    private var startRunCard: some View {
        VStack(alignment: .leading, spacing: AppSpacing.md) {
            sectionEyebrow(
                title: viewModel.launchMode == .solo ? "Ready To Start" : "Current Start Context",
                subtitle: viewModel.launchMode == .solo
                    ? "Solo run is selected. Start manually when you want to begin tracking."
                    : "Crew mode stays separate. Use the lobby to join or line up the social run before starting."
            )

            HStack(spacing: AppSpacing.sm) {
                Image(systemName: viewModel.launchMode == .solo ? "figure.run" : "person.3.fill")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(viewModel.launchMode == .solo ? Color(red: 0.20, green: 0.82, blue: 0.49) : Color(red: 0.98, green: 0.42, blue: 0.18))

                Text(viewModel.socialSelectionSummary)
                    .font(AppTypography.caption1)
                    .foregroundStyle(Color.white.opacity(0.60))

                Spacer()
            }

            Button {
                if viewModel.hasLocationPermission {
                    viewModel.startWorkout()
                } else {
                    viewModel.requestLocationPermission()
                }
            } label: {
                HStack(spacing: AppSpacing.sm) {
                    Image(systemName: viewModel.hasLocationPermission ? "play.fill" : "location.fill")
                        .font(.system(size: 18, weight: .bold))
                    Text(viewModel.startActionTitle)
                        .font(AppTypography.title3)
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, AppSpacing.lg)
                .background(
                    LinearGradient(
                        colors: [
                            Color(red: 0.98, green: 0.42, blue: 0.18),
                            Color(red: 0.91, green: 0.20, blue: 0.18)
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    ),
                    in: RoundedRectangle(cornerRadius: AppSpacing.cornerRadiusButton)
                )
                .shadow(color: Color(red: 0.95, green: 0.32, blue: 0.20).opacity(0.28), radius: 18, x: 0, y: 10)
            }
            .buttonStyle(.plain)
        }
        .padding(AppSpacing.lg)
        .background(runningWidgetBackground, in: RoundedRectangle(cornerRadius: AppSpacing.cornerRadiusLarge, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: AppSpacing.cornerRadiusLarge, style: .continuous)
                .stroke(Color.white.opacity(0.10), lineWidth: 1)
        )
    }

    private func hubActionTile(
        title: String,
        subtitle: String,
        icon: String,
        accentColor: Color,
        isSelected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: AppSpacing.sm) {
                HStack(alignment: .top) {
                    ZStack {
                        Circle()
                            .fill(isSelected ? accentColor.opacity(0.18) : Color.white.opacity(0.08))
                            .frame(width: 42, height: 42)

                        Image(systemName: icon)
                            .font(.system(size: 17, weight: .bold))
                            .foregroundStyle(isSelected ? accentColor : .white)
                    }

                    Spacer()

                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(accentColor)
                    }
                }

                Text(title)
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)

                Text(subtitle)
                    .font(AppTypography.caption1)
                    .foregroundStyle(Color.white.opacity(0.64))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, minHeight: 136, alignment: .leading)
            .padding(AppSpacing.md)
            .background(
                Color.white.opacity(isSelected ? 0.08 : 0.04),
                in: RoundedRectangle(cornerRadius: 24, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .stroke(isSelected ? accentColor.opacity(0.55) : Color.white.opacity(0.08), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private var futureRunsCard: some View {
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

                Button("View All") {
                    showPlannerView = true
                }
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Color.white.opacity(0.42))
                .buttonStyle(.plain)
            }

            if viewModel.upcomingRuns.isEmpty {
                Text("No events on the calendar yet. Open the planner to schedule a solo or crew run in the future.")
                    .font(AppTypography.caption1)
                    .foregroundStyle(Color.white.opacity(0.46))
            } else {
                VStack(spacing: AppSpacing.sm) {
                    ForEach(Array(viewModel.upcomingRuns.sorted(by: { $0.plannedStartAt < $1.plannedStartAt }).prefix(3).enumerated()), id: \.element.id) { index, run in
                        Button {
                            viewModel.selectUpcomingRun(run.id)
                            showPlannerView = true
                        } label: {
                            upcomingPreviewRow(run: run, showsConnector: index != min(viewModel.upcomingRuns.count, 3) - 1)
                        }
                        .buttonStyle(.plain)
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

    private var runningHighlightsCard: some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            sectionEyebrow(title: "Weekly Flow", subtitle: "Your current running rhythm")

            HStack(spacing: AppSpacing.sm) {
                statItem(
                    value: formatDistance(viewModel.dashboard.weekDistanceMeters),
                    label: "Distance",
                    icon: "figure.run"
                )
                statItem(
                    value: "\(viewModel.dashboard.weekRuns)",
                    label: "Runs",
                    icon: "timer"
                )
                statItem(
                    value: "+\(viewModel.dashboard.weekEarnedMinutes)m",
                    label: "Earned",
                    icon: "bolt.fill"
                )
            }
        }
        .padding(AppSpacing.lg)
        .background(runningWidgetBackground, in: RoundedRectangle(cornerRadius: AppSpacing.cornerRadiusLarge, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: AppSpacing.cornerRadiusLarge, style: .continuous)
                .stroke(Color.white.opacity(0.10), lineWidth: 1)
        )
    }

    private var runningPersonalBestCard: some View {
        VStack(alignment: .leading, spacing: AppSpacing.md) {
            sectionEyebrow(title: "Personal Bests", subtitle: "Benchmarks you can beat")

            summaryRow(
                icon: "flag.fill",
                label: "Best Distance",
                value: formatDistance(viewModel.dashboard.bestDistanceMeters)
            )
            summaryRow(
                icon: "clock.fill",
                label: "Longest Run",
                value: formatDurationSeconds(viewModel.dashboard.longestRunDurationSeconds)
            )
            summaryRow(
                icon: "speedometer",
                label: "Weekly Avg Pace",
                value: formatPace(viewModel.dashboard.averagePaceSecondsPerKm)
            )
        }
        .padding(AppSpacing.lg)
        .background(runningWidgetBackground, in: RoundedRectangle(cornerRadius: AppSpacing.cornerRadiusLarge, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: AppSpacing.cornerRadiusLarge, style: .continuous)
                .stroke(Color.white.opacity(0.10), lineWidth: 1)
        )
    }

    private var recentRunsCard: some View {
        VStack(alignment: .leading, spacing: AppSpacing.md) {
            sectionEyebrow(title: "Recent Runs", subtitle: "Your latest sessions")

            if viewModel.dashboard.recentRuns.isEmpty {
                VStack(spacing: AppSpacing.sm) {
                    Image(systemName: "figure.run.circle")
                        .font(.system(size: 34, weight: .light))
                        .foregroundStyle(Color.white.opacity(0.24))
                    Text("No runs yet")
                        .font(AppTypography.subheadlineSemibold)
                        .foregroundStyle(.white)
                    Text("Start your first run to begin building your route history, pacing trends, and weekly volume.")
                        .font(AppTypography.caption1)
                        .foregroundStyle(Color.white.opacity(0.60))
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, AppSpacing.xl)
            } else {
                ForEach(viewModel.dashboard.recentRuns) { run in
                    Button {
                        selectedRecentRun = run
                    } label: {
                        recentRunRow(run)
                    }
                    .buttonStyle(.plain)
                    if run.id != viewModel.dashboard.recentRuns.last?.id {
                        Divider()
                            .overlay(Color.white.opacity(0.08))
                    }
                }
            }
        }
        .padding(AppSpacing.lg)
        .background(runningWidgetBackground, in: RoundedRectangle(cornerRadius: AppSpacing.cornerRadiusLarge, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: AppSpacing.cornerRadiusLarge, style: .continuous)
                .stroke(Color.white.opacity(0.10), lineWidth: 1)
        )
    }

    // MARK: - Active View

    private var activeView: some View {
        GeometryReader { proxy in
            ZStack {
                routeMapView
                    .ignoresSafeArea()

                if !isMapFocusMode {
                    LinearGradient(
                        colors: [
                            Color.black.opacity(0.25),
                            Color.black.opacity(0.55),
                            Color.black.opacity(0.85)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
                } else {
                    // Keep the map clean; only a subtle top fade for readability.
                    LinearGradient(
                        colors: [
                            Color.black.opacity(0.35),
                            Color.black.opacity(0.0)
                        ],
                        startPoint: .top,
                        endPoint: .center
                    )
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
                }

                // Stats UI layer (slides out with swipe effect)
                statsOverlay
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .offset(x: isMapFocusMode ? proxy.size.width : 0)
                    .animation(.spring(duration: 0.45), value: isMapFocusMode)

                mapFocusToggleButton
                    .position(
                        x: isMapFocusMode ? 6 : (proxy.size.width - 6),
                        y: proxy.size.height - 46
                    )
            }
        }
    }

    private var mapFocusToggleButton: some View {
        Button {
            isMapFocusMode.toggle()
            if !isMapFocusMode {
                isFollowingRunner = false
            }
        } label: {
            Image(systemName: isMapFocusMode ? "chevron.right" : "chevron.left")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 50, height: 44)
                .background(
                    UnevenRoundedRectangle(
                        topLeadingRadius: isMapFocusMode ? 22 : 14,
                        bottomLeadingRadius: isMapFocusMode ? 22 : 14,
                        bottomTrailingRadius: isMapFocusMode ? 14 : 22,
                        topTrailingRadius: isMapFocusMode ? 14 : 22
                    )
                    .fill(Color.black.opacity(0.45))
                )
                .overlay(
                    UnevenRoundedRectangle(
                        topLeadingRadius: isMapFocusMode ? 22 : 14,
                        bottomLeadingRadius: isMapFocusMode ? 22 : 14,
                        bottomTrailingRadius: isMapFocusMode ? 14 : 22,
                        topTrailingRadius: isMapFocusMode ? 14 : 22
                    )
                    .stroke(Color.white.opacity(0.10), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }

    private var statsOverlay: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .topTrailing) {
                HStack(alignment: .firstTextBaseline) {
                    Text(speedValueDisplay)
                        .font(.system(size: 56, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)

                    Text("KM/H")
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundStyle(Color.white.opacity(0.7))
                        .tracking(1)
                        .padding(.leading, 8)

                    Spacer(minLength: 8)
                }

                Button {
                    showCrewLobby = true
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "person.2.fill")
                            .font(.system(size: 13, weight: .semibold))
                        Text("\(viewModel.runParticipants.count)")
                            .font(.system(size: 13, weight: .bold, design: .rounded))
                            .monospacedDigit()
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(Color.black.opacity(0.35), in: Capsule())
                }
                .padding(.top, 4)
            }
            .padding(.horizontal, AppSpacing.screenHorizontal)
            .padding(.top, 24)
            .overlay(alignment: .top) {
                VStack(spacing: 10) {
                    if let stateLabel = viewModel.activeRunStateLabel {
                        activeRunStatusChip(stateLabel)
                    }

                    if let banner = viewModel.liveRunBannerMessage {
                        activeRunBanner(banner)
                    }

                    if viewModel.isPaused {
                        Text("PAUSED")
                            .font(.system(size: 12, weight: .bold, design: .rounded))
                            .foregroundStyle(Color.orange)
                            .tracking(2)
                    }
                }
                .padding(.top, 98)
            }

            if viewModel.selectedLiveRunSessionId != nil || viewModel.lastDetachedLiveRunSessionId != nil {
                HStack {
                    Spacer()
                    if viewModel.selectedLiveRunSessionId != nil {
                        Button {
                            viewModel.leaveCurrentLiveRun()
                        } label: {
                            HStack(spacing: 8) {
                                if viewModel.isLeavingLiveRun {
                                    ProgressView()
                                        .tint(.white)
                                }
                                Text(viewModel.isLeavingLiveRun ? "Leaving..." : "Leave Crew")
                                    .font(.system(size: 12, weight: .bold, design: .rounded))
                            }
                            .foregroundStyle(.white)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(Color.black.opacity(0.35), in: Capsule())
                        }
                        .buttonStyle(.plain)
                        .disabled(viewModel.isLeavingLiveRun)
                    } else if viewModel.lastDetachedLiveRunSessionId != nil {
                        Button {
                            viewModel.rejoinLastLiveRun()
                        } label: {
                            HStack(spacing: 8) {
                                if viewModel.isRejoiningLiveRun {
                                    ProgressView()
                                        .tint(.white)
                                }
                                Text(viewModel.isRejoiningLiveRun ? "Rejoining..." : "Rejoin Crew")
                                    .font(.system(size: 12, weight: .bold, design: .rounded))
                            }
                            .foregroundStyle(.white)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(Color.orange.opacity(0.88), in: Capsule())
                        }
                        .buttonStyle(.plain)
                        .disabled(viewModel.isRejoiningLiveRun)
                    }
                }
                .padding(.horizontal, AppSpacing.screenHorizontal)
                .padding(.top, 12)
            }

            Spacer()

            VStack(spacing: 14) {
                ZStack {
                    Circle()
                        .fill(Color.black.opacity(0.45))

                    KilometerProgressRing(distanceMeters: viewModel.distanceMeters)

                    VStack(spacing: 10) {
                        Text(paceValueDisplay)
                            .font(.system(size: 48, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                            .monospacedDigit()
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)

                        Text("PACE")
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                            .foregroundStyle(Color.white.opacity(0.55))
                            .tracking(2)

                        Text(viewModel.formattedDuration)
                            .font(.system(size: 31, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                            .monospacedDigit()
                            .padding(.top, 8)

                        Text("TIME")
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                            .foregroundStyle(Color.white.opacity(0.55))
                            .tracking(2)
                    }
                }
                .frame(width: KilometerProgressRing.ringDiameter, height: KilometerProgressRing.ringDiameter)

                HStack(spacing: 18) {
                    activeInfoPill(title: "DIST", value: formatDistanceMeters(viewModel.distanceMeters))
                    activeInfoPill(title: "PAUSED", value: formatDurationSeconds(Int(viewModel.pauseDuration)))
                }
            }

            Spacer()

            HStack(spacing: 18) {
                Button {
                    showMusicSheet = true
                } label: {
                    Circle()
                        .fill(Color.black.opacity(0.35))
                        .frame(width: 44, height: 44)
                        .overlay(
                            Image(systemName: "music.note")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(Color.white.opacity(0.85))
                        )
                }

                Button {
                    if viewModel.isPaused {
                        viewModel.resumeWorkout()
                    } else {
                        viewModel.pauseWorkout()
                    }
                } label: {
                    Circle()
                        .fill(Color.orange)
                        .frame(width: 82, height: 82)
                        .overlay(
                            Image(systemName: viewModel.isPaused ? "play.fill" : "pause.fill")
                                .font(.system(size: 28, weight: .bold))
                                .foregroundStyle(.white)
                        )
                }

                Button {
                    viewModel.requestStop()
                } label: {
                    Circle()
                        .fill(Color.black.opacity(0.35))
                        .frame(width: 44, height: 44)
                        .overlay(
                            Image(systemName: "xmark")
                                .font(.system(size: 15, weight: .bold))
                                .foregroundStyle(Color.white.opacity(0.85))
                        )
                }
            }
            .overlay(alignment: .top) {
                if viewModel.spotifyConnected && viewModel.spotifyIsPlaying {
                    activeSpotifyNowPlayingCard
                        .offset(y: -82)
                }
            }
            .padding(.bottom, 24)
        }
        .allowsHitTesting(!isMapFocusMode)
    }

    private var activeSpotifyNowPlayingCard: some View {
        HStack(spacing: 12) {
            Image(systemName: viewModel.spotifyConnected ? "waveform.circle.fill" : "music.note")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(viewModel.spotifyConnected ? AppColors.success : Color.white.opacity(0.72))
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 3) {
                Text(viewModel.spotifyNowPlayingTitle ?? "No active playback")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(1)

                Text(viewModel.spotifyNowPlayingArtist ?? viewModel.jamStatusLabel)
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color.white.opacity(0.60))
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            SpotifyLiveBarsView(
                isAnimating: viewModel.spotifyConnected && viewModel.spotifyIsPlaying,
                tint: AppColors.success
            )
            .frame(width: 24, height: 16)
            .clipped()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(maxWidth: min(UIScreen.main.bounds.width - 60, 328))
        .background(
            Capsule(style: .continuous)
                .fill(Color.black.opacity(0.52))
                .overlay(
                    Capsule(style: .continuous)
                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
                )
        )
        .shadow(color: Color.black.opacity(0.20), radius: 12, y: 6)
        .offset(x: musicWidgetSwipeOffset)
        .contentShape(Capsule(style: .continuous))
        .gesture(
            DragGesture(minimumDistance: 18, coordinateSpace: .local)
                .onEnded { value in
                    let horizontal = value.translation.width
                    let vertical = value.translation.height
                    guard abs(horizontal) > abs(vertical), abs(horizontal) > 28 else { return }

                    if horizontal < 0 {
                        animateMusicWidgetSwipe(direction: -1)
                        viewModel.nextTrack()
                    } else {
                        animateMusicWidgetSwipe(direction: 1)
                        viewModel.previousTrack()
                    }
                }
        )
    }

    private func animateMusicWidgetSwipe(direction: CGFloat) {
        withAnimation(.easeOut(duration: 0.12)) {
            musicWidgetSwipeOffset = 18 * direction
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
            withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                musicWidgetSwipeOffset = 0
            }
        }
    }

    private func animateSpotifyRefreshButton() {
        withAnimation(.easeOut(duration: 0.10)) {
            isSpotifyRefreshButtonPressed = true
        }
        withAnimation(.spring(response: 0.34, dampingFraction: 0.74)) {
            spotifyRefreshButtonRotation -= 180
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.14) {
            withAnimation(.easeOut(duration: 0.14)) {
                isSpotifyRefreshButtonPressed = false
            }
        }
    }

// MARK: - Route Map

    private var displayRouteCoordinates: [CLLocationCoordinate2D] {
        RouteSmoothing.smoothCoordinates(viewModel.routeLocations.map(\.coordinate))
    }

    private var routeMapView: some View {
        Map(
            position: $mapPosition,
            interactionModes: isMapFocusMode ? [.pan, .zoom, .pitch, .rotate] : []
        ) {
            // Start marker
            if let start = viewModel.routeLocations.first {
                Annotation("Start", coordinate: start.coordinate) {
                    VStack(spacing: 4) {
                        Text("START")
                            .font(.system(size: 9, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(Color.green.opacity(0.9), in: Capsule())

                        Circle()
                            .fill(Color.green)
                            .frame(width: 12, height: 12)
                            .overlay(
                                Circle()
                                    .stroke(.white, lineWidth: 2)
                            )
                    }
                }
            }

            // Route polyline
            if displayRouteCoordinates.count >= 2 {
                MapPolyline(
                    coordinates: displayRouteCoordinates
                )
                .stroke(AppColors.info, lineWidth: 4)
            }

            // Current position marker
            if let current = viewModel.routeLocations.last {
                Annotation("", coordinate: current.coordinate) {
                    ZStack {
                        Circle()
                            .stroke(AppColors.info.opacity(0.45), lineWidth: 2)
                            .frame(width: 30, height: 30)
                            .scaleEffect(isCurrentMarkerPulsing ? 1.35 : 0.75)
                            .opacity(isCurrentMarkerPulsing ? 0.0 : 0.9)

                        Circle()
                            .fill(AppColors.info)
                            .frame(width: 16, height: 16)
                        Circle()
                            .fill(.white)
                            .frame(width: 8, height: 8)
                    }
                    .shadow(color: AppColors.info.opacity(0.5), radius: 6)
                    .onAppear {
                        guard !isCurrentMarkerPulsing else { return }
                        withAnimation(.easeOut(duration: 1.3).repeatForever(autoreverses: false)) {
                            isCurrentMarkerPulsing = true
                        }
                    }
                }
            }

            // End marker (shown on finished screen)
            if viewModel.phase == .finished,
               let end = viewModel.routeLocations.last {
                Annotation("End", coordinate: end.coordinate) {
                    VStack(spacing: 4) {
                        Text("END")
                            .font(.system(size: 9, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(Color.orange.opacity(0.9), in: Capsule())

                        Circle()
                            .fill(Color.orange)
                            .frame(width: 12, height: 12)
                            .overlay(
                                Circle()
                                    .stroke(.white, lineWidth: 2)
                            )
                    }
                }
            }
        }
        .mapStyle(.standard(elevation: .flat))
        .mapControlVisibility(isMapFocusMode ? .visible : .hidden)
        .mapControls {}
        .onChange(of: viewModel.routeLocations.last) { _, last in
            guard let last else { return }

            if isFollowingRunner {
                centerOnRunner(last.coordinate, animated: true)
                return
            }

            guard !isMapFocusMode else { return }
            let region = MKCoordinateRegion(
                center: last.coordinate,
                span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
            )
            mapPosition = .region(region)
        }
        .overlay(alignment: .bottomTrailing) {
            if isMapFocusMode {
                VStack(spacing: 10) {
                    Button {
                        showEntireRoute()
                    } label: {
                        Image(systemName: "arrow.up.left.and.arrow.down.right")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 42, height: 42)
                            .background(Color.black.opacity(0.55), in: Circle())
                            .overlay(Circle().stroke(Color.white.opacity(0.12), lineWidth: 1))
                    }
                    .buttonStyle(.plain)

                    Button {
                        recenterOnCurrentLocation()
                    } label: {
                        Image(systemName: "location.fill")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 42, height: 42)
                            .background(Color.black.opacity(0.55), in: Circle())
                            .overlay(Circle().stroke(Color.white.opacity(0.12), lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                }
                // Place controls lower to avoid Dynamic Island area
                .padding(.trailing, 14)
                .padding(.bottom, 90)
            }
        }
    }

    private func recenterOnCurrentLocation() {
        guard let last = viewModel.routeLocations.last else { return }
        isFollowingRunner = true
        centerOnRunner(last.coordinate, animated: true)
    }

    private func centerOnRunner(_ coordinate: CLLocationCoordinate2D, animated: Bool) {
        // Tight zoom for active "runner-fixed" mode.
        let region = MKCoordinateRegion(
            center: coordinate,
            span: MKCoordinateSpan(latitudeDelta: 0.0014, longitudeDelta: 0.0014)
        )
        if animated {
            withAnimation(.easeInOut(duration: 0.25)) {
                mapPosition = .region(region)
            }
        } else {
            mapPosition = .region(region)
        }
    }

    private func showEntireRoute() {
        isFollowingRunner = false
        let coordinates = displayRouteCoordinates
        guard !coordinates.isEmpty else { return }
        let region = mapRegionForCoordinates(coordinates)
        withAnimation(.easeInOut(duration: 0.3)) {
            mapPosition = .region(region)
        }
    }

    private func mapRegionForCoordinates(_ coords: [CLLocationCoordinate2D]) -> MKCoordinateRegion {
        guard let first = coords.first else {
            return MKCoordinateRegion(
                center: CLLocationCoordinate2D(latitude: 0, longitude: 0),
                span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
            )
        }

        var minLat = first.latitude
        var maxLat = first.latitude
        var minLon = first.longitude
        var maxLon = first.longitude

        for coord in coords {
            minLat = min(minLat, coord.latitude)
            maxLat = max(maxLat, coord.latitude)
            minLon = min(minLon, coord.longitude)
            maxLon = max(maxLon, coord.longitude)
        }

        let center = CLLocationCoordinate2D(
            latitude: (minLat + maxLat) / 2,
            longitude: (minLon + maxLon) / 2
        )
        let span = MKCoordinateSpan(
            latitudeDelta: max((maxLat - minLat) * 1.35, 0.004),
            longitudeDelta: max((maxLon - minLon) * 1.35, 0.004)
        )
        return MKCoordinateRegion(center: center, span: span)
    }

    // MARK: - Finished View

    private var finishedView: some View {
        ZStack {
            routeMapView
                .ignoresSafeArea()

            LinearGradient(
                colors: [
                    Color.black.opacity(0.30),
                    Color.black.opacity(0.65),
                    Color.black.opacity(0.92)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack(spacing: AppSpacing.lg) {
                Spacer(minLength: 20)

                VStack(alignment: .leading, spacing: AppSpacing.lg) {
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(viewModel.completedRunCounts ? "SESSION COMPLETE" : "SESSION ENDED")
                                .font(.system(size: 11, weight: .bold, design: .rounded))
                                .foregroundStyle(Color.white.opacity(0.50))
                                .tracking(1.8)

                            Text(viewModel.finishedTitle)
                                .font(.system(size: 34, weight: .bold, design: .rounded))
                                .foregroundStyle(.white)
                        }

                        Spacer()

                        statusPill(
                            title: viewModel.completedRunCounts ? "Saved" : "Discarded",
                            icon: viewModel.completedRunCounts ? "checkmark.circle.fill" : "minus.circle.fill",
                            tint: viewModel.completedRunCounts ? Color(red: 0.98, green: 0.42, blue: 0.18) : Color.white.opacity(0.84)
                        )
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text(viewModel.formattedDistance)
                            .font(.system(size: 64, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                            .monospacedDigit()
                            .lineLimit(1)
                            .minimumScaleFactor(0.62)

                        Text("Total Distance")
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                            .foregroundStyle(Color.white.opacity(0.50))
                            .tracking(1.8)
                    }

                    Text(viewModel.finishedSubtitle)
                        .font(AppTypography.body)
                        .foregroundStyle(Color.white.opacity(0.76))
                        .fixedSize(horizontal: false, vertical: true)

                    HStack(spacing: 10) {
                        finishedStat(value: viewModel.formattedDuration, label: "Time")
                        finishedStat(value: viewModel.formattedPace, label: "Pace")
                        finishedStat(
                            value: viewModel.completedRunCounts ? "+\(viewModel.earnedMinutes)m" : "Not saved",
                            label: viewModel.completedRunCounts ? "Earned" : "Status"
                        )
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(24)
                .background(finishedHeroBackground, in: RoundedRectangle(cornerRadius: 32, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 32, style: .continuous)
                        .stroke(Color.white.opacity(0.12), lineWidth: 1)
                )

                Spacer()

                HStack(spacing: 12) {
                    if viewModel.completedRunCounts {
                        Button {
                            prepareShareImage()
                        } label: {
                            HStack(spacing: 8) {
                                if isRenderingShareImage {
                                    ProgressView()
                                        .tint(.white)
                                        .scaleEffect(0.76)
                                } else {
                                    Image(systemName: "square.and.arrow.up")
                                        .font(.system(size: 14, weight: .bold))
                                }
                                Text("Share")
                                    .font(.system(size: 16, weight: .semibold))
                            }
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 54)
                            .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 18, style: .continuous)
                                    .stroke(Color.white.opacity(0.10), lineWidth: 1)
                            )
                        }
                        .buttonStyle(.plain)
                        .disabled(isRenderingShareImage)
                    }

                    Button {
                        dismiss()
                    } label: {
                        Text("Done")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 54)
                            .background(
                                LinearGradient(
                                    colors: [
                                        Color(red: 0.98, green: 0.42, blue: 0.18),
                                        Color(red: 0.90, green: 0.18, blue: 0.28)
                                    ],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                ),
                                in: RoundedRectangle(cornerRadius: 18, style: .continuous)
                            )
                    }
                    .buttonStyle(.plain)
                }
                .padding(.bottom, AppSpacing.md)
            }
            .padding(.horizontal, AppSpacing.screenHorizontal)
        }
        .sheet(isPresented: $showShareSheet) {
            if let image = shareImage {
                ShareSheet(items: [image])
            }
        }
    }

    // MARK: - Finished View Helpers

    private var finishedHeroBackground: LinearGradient {
        LinearGradient(
            colors: viewModel.completedRunCounts
                ? [
                    Color(red: 0.13, green: 0.13, blue: 0.15),
                    Color(red: 0.08, green: 0.08, blue: 0.09),
                    Color(red: 0.22, green: 0.09, blue: 0.10)
                ]
                : [
                    Color(red: 0.10, green: 0.10, blue: 0.11),
                    Color(red: 0.06, green: 0.06, blue: 0.07),
                    Color(red: 0.12, green: 0.12, blue: 0.13)
                ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private var finishedWidgetBackground: LinearGradient {
        LinearGradient(
            colors: [
                Color(red: 0.08, green: 0.08, blue: 0.09),
                Color(red: 0.05, green: 0.05, blue: 0.06)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private func finishedStat(value: String, label: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(value)
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.75)

            Text(label)
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .foregroundStyle(Color.white.opacity(0.56))
                .tracking(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(finishedWidgetBackground, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(Color.white.opacity(0.10), lineWidth: 1)
        )
    }

    private func statusPill(title: String, icon: String, tint: Color) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .bold))
            Text(title)
                .font(.system(size: 12, weight: .bold, design: .rounded))
        }
        .foregroundStyle(tint)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.white.opacity(0.06), in: Capsule())
    }

    // MARK: - Share Image Generation

    private func prepareShareImage() {
        guard !isRenderingShareImage else { return }
        isRenderingShareImage = true

        let coordinates = displayRouteCoordinates
        let distance = viewModel.formattedDistance
        let duration = viewModel.formattedDuration
        let pace = viewModel.formattedPace
        let calories = "\(viewModel.caloriesBurned) cal"
        let earnedMinutes = viewModel.earnedMinutes

        Task {
            let mapSnapshot = await JoggingMapSnapshotGenerator.generateSnapshot(
                coordinates: coordinates
            )

            let image = JoggingShareRenderer.renderShareImage(
                mapSnapshot: mapSnapshot,
                distance: distance,
                duration: duration,
                pace: pace,
                calories: calories,
                earnedMinutes: earnedMinutes,
                date: Date()
            )

            shareImage = image
            isRenderingShareImage = false

            if image != nil {
                showShareSheet = true
            }
        }
    }

    private func openMusicApp() {
        guard let musicURL = URL(string: "music://") else { return }
        openURL(musicURL)
    }

    // MARK: - Helper Views

    private func statItem(value: String, label: String, icon: String) -> some View {
        VStack(spacing: AppSpacing.xxs) {
            Image(systemName: icon)
                .font(.system(size: 16))
                .foregroundStyle(Color(red: 0.95, green: 0.33, blue: 0.19))

            Text(value)
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            Text(label)
                .font(AppTypography.caption2)
                .foregroundStyle(Color.white.opacity(0.52))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, AppSpacing.md)
        .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private func heroMetricPill(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title.uppercased())
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .foregroundStyle(Color.white.opacity(0.62))
                .tracking(1.5)

            Text(value)
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, AppSpacing.sm)
        .padding(.vertical, AppSpacing.sm)
        .background(Color.white.opacity(0.12), in: RoundedRectangle(cornerRadius: AppSpacing.cornerRadiusCard))
    }

    private func quickRunAction(
        title: String,
        subtitle: String,
        icon: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: AppSpacing.sm) {
                ZStack {
                    Circle()
                        .fill(Color.white.opacity(0.08))
                        .frame(width: 38, height: 38)

                    Image(systemName: icon)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Color.white.opacity(0.88))
                }

                VStack(alignment: .leading, spacing: 2) {
                        Text(title)
                            .font(AppTypography.bodySemibold)
                            .foregroundStyle(.white)
                    Text(subtitle)
                        .font(AppTypography.caption2)
                        .foregroundStyle(Color.white.opacity(0.52))
                }

                Spacer()
            }
            .padding(AppSpacing.md)
            .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private func runModeOption(
        mode: RunLaunchMode,
        title: String,
        subtitle: String,
        icon: String
    ) -> some View {
        let isSelected = viewModel.launchMode == mode

        return Button {
            viewModel.setLaunchMode(mode)
        } label: {
            VStack(alignment: .leading, spacing: AppSpacing.sm) {
                HStack {
                    ZStack {
                        Circle()
                            .fill(isSelected ? Color.white.opacity(0.20) : Color.white.opacity(0.08))
                            .frame(width: 40, height: 40)

                        Image(systemName: icon)
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(.white)
                    }

                    Spacer()

                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundStyle(.white)
                    }
                }

                Text(title)
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)

                Text(subtitle)
                    .font(AppTypography.caption1)
                    .foregroundStyle(isSelected ? Color.white.opacity(0.80) : Color.white.opacity(0.56))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, minHeight: 150, alignment: .leading)
            .padding(AppSpacing.md)
            .background(
                Group {
                    if isSelected {
                        LinearGradient(
                            colors: mode == .solo
                                ? [Color(red: 0.13, green: 0.70, blue: 0.36), Color(red: 0.08, green: 0.44, blue: 0.22)]
                                : [Color(red: 0.98, green: 0.42, blue: 0.18), Color(red: 0.84, green: 0.21, blue: 0.18)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    } else {
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.06),
                                Color.white.opacity(0.04)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    }
                }
            )
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .stroke(isSelected ? Color.clear : Color.white.opacity(0.10), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private func upcomingPreviewRow(run: UpcomingRunOption, showsConnector: Bool) -> some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(spacing: 0) {
                Circle()
                    .fill(Color.white.opacity(0.20))
                    .frame(width: 16, height: 16)
                    .overlay(Circle().stroke(Color.white.opacity(0.40), lineWidth: 2))

                if showsConnector {
                    Rectangle()
                        .fill(Color.white.opacity(0.10))
                        .frame(width: 1, height: 58)
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

                Text(upcomingTimelineDateText(for: run))
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Color.white.opacity(0.40))

                HStack(spacing: 6) {
                    Image(systemName: "figure.run")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Color.white.opacity(0.40))
                    Text(upcomingTimelineBadgeText(for: run))
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Color.white.opacity(0.60))
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color.white.opacity(0.05), in: Capsule())
            }
            .padding(.bottom, showsConnector ? 0 : 2)
        }
    }

    private func upcomingTimelineDateText(for run: UpcomingRunOption) -> String {
        Self.upcomingTimelineDateFormatter.string(from: run.plannedStartAt)
    }

    private func upcomingTimelineBadgeText(for run: UpcomingRunOption) -> String {
        if let status = run.status, !status.isEmpty {
            return status.replacingOccurrences(of: "_", with: " ").capitalized
        }
        return run.visibility.uppercased() == "PRIVATE" ? "Solo event" : "Crew run"
    }

    private func sectionEyebrow(title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(AppTypography.headline)
                .foregroundStyle(.white)
            Text(subtitle)
                .font(AppTypography.caption1)
                .foregroundStyle(Color.white.opacity(0.52))
        }
    }

    private func recentRunRow(_ run: RunningDashboardData.RecentRun) -> some View {
        HStack(spacing: AppSpacing.sm) {
            ZStack {
                Circle()
                    .fill(Color(red: 0.95, green: 0.33, blue: 0.19).opacity(0.10))
                    .frame(width: 42, height: 42)

                Image(systemName: "figure.run")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Color(red: 0.95, green: 0.33, blue: 0.19))
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(Self.shortDateFormatter.string(from: run.date))
                    .font(AppTypography.bodySemibold)
                    .foregroundStyle(.white)

                HStack(spacing: AppSpacing.xs) {
                    Text(formatDurationSeconds(run.durationSeconds))
                    Text("•")
                    Text("+\(run.earnedMinutes)m")
                }
                .font(AppTypography.caption2)
                .foregroundStyle(Color.white.opacity(0.52))
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 3) {
                Text(formatDistance(run.distanceMeters))
                    .font(AppTypography.bodySemibold)
                    .foregroundStyle(.white)

                HStack(spacing: 6) {
                    Text(formatPace(run.avgPaceSecondsPerKm))
                        .font(AppTypography.caption1)
                        .foregroundStyle(Color.white.opacity(0.52))

                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(Color.white.opacity(0.24))
                }
            }
        }
        .padding(.vertical, 2)
    }

    private var speedValueDisplay: String {
        String(format: "%.2f", viewModel.currentSpeed * 3.6)
    }

    private var paceValueDisplay: String {
        guard let pace = viewModel.currentPaceSecondsPerKm, pace > 0 else { return "--.--" }
        let paceMinutes = Double(pace) / 60.0
        return String(format: "%.2f", paceMinutes)
    }

    private func formatDistanceMeters(_ m: Double) -> String {
        if m >= 1000 {
            return String(format: "%.2f km", m / 1000.0)
        }
        return String(format: "%.0f m", m)
    }

    private func activeInfoPill(title: String, value: String) -> some View {
        VStack(spacing: 3) {
            Text(value)
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.75)

            Text(title)
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .foregroundStyle(Color.white.opacity(0.55))
                .tracking(1)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color.black.opacity(0.3), in: Capsule())
    }

    private func activeRunStatusChip(_ text: String) -> some View {
        HStack(spacing: 8) {
            Circle()
                .fill(Color.orange)
                .frame(width: 8, height: 8)
            Text(text)
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .tracking(1)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(Color.black.opacity(0.42), in: Capsule())
    }

    private func activeRunBanner(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 13, weight: .semibold, design: .rounded))
            .foregroundStyle(.white)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color.orange.opacity(0.92))
            )
            .padding(.horizontal, 32)
    }


    // MARK: - Music Sheet

    private var musicSheet: some View {
        NavigationStack {
            ZStack {
                Color(red: 0.06, green: 0.06, blue: 0.08)
                    .ignoresSafeArea()

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 0) {
                        spotifyConnectionHeader
                        Spacer()
                            .frame(height: 18)
                        nowPlayingCard
                        Spacer()
                            .frame(height: 18)
                        playbackControls
                        Spacer()
                            .frame(height: 18)
                        runModeSelector
                        if viewModel.jamActive || viewModel.selectedLiveRunSessionId != nil {
                            Spacer()
                                .frame(height: 18)
                            runJamCard
                        }
                    }
                    .padding(.horizontal, AppSpacing.screenHorizontal)
                    .padding(.top, AppSpacing.md)
                    .padding(.bottom, AppSpacing.screenVerticalBottom)
                }
            }
            .navigationTitle("Run Audio")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.hidden, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        animateSpotifyRefreshButton()
                        viewModel.refreshSpotifyDetails()
                    } label: {
                        ZStack {
                            Capsule(style: .continuous)
                                .fill(Color.white.opacity(isSpotifyRefreshButtonPressed ? 0.14 : 0.08))
                                .frame(width: 34, height: 28)

                            Image(systemName: "arrow.triangle.2.circlepath")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundStyle(Color.white.opacity(0.86))
                                .rotationEffect(.degrees(spotifyRefreshButtonRotation))
                                .scaleEffect(isSpotifyRefreshButtonPressed ? 0.92 : 1.0)
                        }
                    }
                    .buttonStyle(.plain)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { showMusicSheet = false }
                        .foregroundStyle(.white)
                }
            }
        }
    }

    // MARK: - Connection Header

    private var spotifyConnectionHeader: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(viewModel.spotifyConnected
                      ? Color(red: 0.13, green: 0.81, blue: 0.41)
                      : Color.white.opacity(0.15))
                .frame(width: 10, height: 10)

            Text(viewModel.spotifyConnected
                 ? (viewModel.spotifyAccountName ?? "Connected")
                 : "Not connected")
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)

            if let accountTier = spotifyAccountTierLabel {
                Text(accountTier)
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .foregroundStyle(accountTier == "Premium" ? .black : Color.white.opacity(0.78))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(
                        accountTier == "Premium"
                            ? Color(red: 0.13, green: 0.81, blue: 0.41)
                            : Color.white.opacity(0.10),
                        in: Capsule()
                    )
            }

            Spacer()

            Button {
                if viewModel.spotifyConnected {
                    viewModel.handleSpotifySecondaryAction()
                } else {
                    viewModel.connectSpotify()
                }
            } label: {
                Text(viewModel.spotifyConnected ? "Disconnect" : "Connect Spotify")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(viewModel.spotifyConnected ? Color.white.opacity(0.6) : .white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(
                        viewModel.spotifyConnected
                            ? Color.white.opacity(0.08)
                            : Color(red: 0.13, green: 0.81, blue: 0.41),
                        in: Capsule()
                    )
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    // MARK: - Now Playing Card

    private var nowPlayingTitle: String {
        viewModel.spotifyNowPlayingTitle ?? (viewModel.spotifyConnected ? "No active playback" : "Connect to play")
    }

    private var nowPlayingArtist: String {
        viewModel.spotifyNowPlayingArtist ?? (viewModel.spotifyConnected ? "Start playing in Spotify" : "Tap Connect above")
    }

    private var hasActivePlayback: Bool {
        viewModel.spotifyNowPlayingTitle != nil
    }

    private var nowPlayingCard: some View {
        VStack(spacing: 20) {
            // Visualizer / idle state
            ZStack {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: viewModel.spotifyIsPlaying
                                ? [Color(red: 0.04, green: 0.12, blue: 0.06), Color(red: 0.02, green: 0.06, blue: 0.03)]
                                : [Color.white.opacity(0.06), Color.white.opacity(0.03)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )

                if viewModel.spotifyIsPlaying {
                    audioVisualizerBars
                        .padding(.horizontal, 16)
                        .padding(.vertical, 24)
                } else {
                    Image(systemName: hasActivePlayback ? "pause.circle.fill" : "music.note")
                        .font(.system(size: 48, weight: .light))
                        .foregroundStyle(Color.white.opacity(0.2))
                }
            }
            .frame(height: 180)

            // Track info
            VStack(spacing: 6) {
                Text(nowPlayingTitle)
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .minimumScaleFactor(0.8)

                Text(nowPlayingArtist)
                    .font(.system(size: 15, weight: .medium, design: .rounded))
                    .foregroundStyle(Color.white.opacity(0.55))
                    .lineLimit(1)
            }

            // Transport controls
            if viewModel.spotifyConnected {
                HStack(spacing: 40) {
                    Button { viewModel.previousTrack() } label: {
                        Image(systemName: "backward.fill")
                            .font(.system(size: 22, weight: .bold))
                            .foregroundStyle(hasActivePlayback ? .white : Color.white.opacity(0.3))
                    }
                    .buttonStyle(.plain)
                    .disabled(!hasActivePlayback)

                    Button { viewModel.togglePlayback() } label: {
                        ZStack {
                            Circle()
                                .fill(.white)
                                .frame(width: 64, height: 64)

                            Image(systemName: viewModel.spotifyIsPlaying ? "pause.fill" : "play.fill")
                                .font(.system(size: 24, weight: .bold))
                                .foregroundStyle(.black)
                        }
                    }
                    .buttonStyle(.plain)

                    Button { viewModel.nextTrack() } label: {
                        Image(systemName: "forward.fill")
                            .font(.system(size: 22, weight: .bold))
                            .foregroundStyle(hasActivePlayback ? .white : Color.white.opacity(0.3))
                    }
                    .buttonStyle(.plain)
                    .disabled(!hasActivePlayback)
                }
                .padding(.top, 4)
            }
        }
        .padding(20)
        .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
    }

    private var spotifyAccountTierLabel: String? {
        guard viewModel.spotifyConnected else { return nil }
        let raw = viewModel.spotifyProductTier?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if raw == "premium" {
            return "Premium"
        }
        if raw == "free" || raw == "open" {
            return "Free"
        }
        return nil
    }

    // MARK: - Audio Visualizer

    /// Simulated multi-band EQ visualizer.
    /// Uses layered sine waves at different frequencies to mimic bass / mid / treble bands.
    /// Runs entirely on the GPU via TimelineView — no audio capture needed.
    private var audioVisualizerBars: some View {
        let barCount = 32
        let spotifyGreen = Color(red: 0.13, green: 0.81, blue: 0.41)

        return TimelineView(.animation(minimumInterval: 0.06, paused: !viewModel.spotifyIsPlaying)) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate

            Canvas { context, size in
                let barWidth: CGFloat = 4
                let gap: CGFloat = (size.width - barWidth * CGFloat(barCount)) / CGFloat(barCount - 1)
                let maxH = size.height

                for i in 0..<barCount {
                    let fi = Double(i)
                    let center = fi / Double(barCount - 1)          // 0…1

                    // Three overlapping frequency bands (bass = left, treble = right)
                    let bass   = sin(t * 2.1 + fi * 0.25) * (1.0 - center) * 0.6
                    let mid    = sin(t * 3.8 + fi * 0.55) * (1.0 - abs(center - 0.5) * 2.0) * 0.5
                    let treble = sin(t * 6.2 + fi * 0.9)  * center * 0.4

                    // Combine bands with a baseline + subtle noise
                    let noise  = sin(t * 11.3 + fi * 2.7) * 0.08
                    let raw    = 0.18 + abs(bass + mid + treble) + noise
                    let norm   = min(max(raw, 0.06), 1.0)

                    let barH   = maxH * norm
                    let x      = CGFloat(i) * (barWidth + gap)
                    let y      = maxH - barH

                    let rect = CGRect(x: x, y: y, width: barWidth, height: barH)
                    let path = Path(roundedRect: rect, cornerRadius: barWidth / 2)

                    // Gradient per bar: bright green at bottom, faded at top
                    let gradient = Gradient(colors: [
                        spotifyGreen,
                        spotifyGreen.opacity(0.7),
                        spotifyGreen.opacity(0.25)
                    ])
                    context.fill(
                        path,
                        with: .linearGradient(
                            gradient,
                            startPoint: CGPoint(x: x, y: maxH),
                            endPoint: CGPoint(x: x, y: y)
                        )
                    )
                }
            }
            .frame(height: 100)
            .drawingGroup()         // render in a single Metal pass
        }
    }

    // MARK: - Run Mode Selector

    private var runModeSelector: some View {
        let spotifyGreen = Color(red: 0.13, green: 0.81, blue: 0.41)

        return VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                Text("Run Mode")
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)

                Spacer()

                if viewModel.spotifyConnected {
                    Button {
                        viewModel.applyCurrentModePreset()
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "wand.and.stars")
                                .font(.system(size: 12, weight: .bold))
                            Text("Generate")
                                .font(.system(size: 12, weight: .bold, design: .rounded))
                        }
                        .foregroundStyle(.black)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(spotifyGreen, in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }

            LazyVGrid(
                columns: [
                    GridItem(.flexible(), spacing: 10),
                    GridItem(.flexible(), spacing: 10)
                ],
                alignment: .leading,
                spacing: 10
            ) {
                ForEach(RunAudioMode.allCases) { mode in
                    let isSelected = viewModel.selectedAudioMode == mode
                    Button {
                        viewModel.selectedAudioMode = mode
                        viewModel.applyCurrentModePreset()
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: runModeIcon(for: mode))
                                .font(.system(size: 12, weight: .bold))
                            Text(mode.rawValue)
                                .font(.system(size: 13, weight: .bold, design: .rounded))
                                .lineLimit(1)
                            Spacer(minLength: 0)
                        }
                        .foregroundStyle(isSelected ? .black : .white)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)
                        .background(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(isSelected ? spotifyGreen : Color.white.opacity(0.08))
                        )
                    }
                    .buttonStyle(.plain)
                }
            }

            if let status = viewModel.spotifyGeneratorStatusMessage, !status.isEmpty {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: status.localizedCaseInsensitiveContains("failed") || status.localizedCaseInsensitiveContains("could not")
                          ? "exclamationmark.triangle.fill"
                          : "info.circle.fill")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(
                            status.localizedCaseInsensitiveContains("failed") || status.localizedCaseInsensitiveContains("could not")
                                ? Color.orange
                                : spotifyGreen
                        )

                    Text(status)
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundStyle(Color.white.opacity(0.78))
                        .multilineTextAlignment(.leading)

                    Spacer(minLength: 0)
                }
                .padding(12)
                .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }

            // Current track / loading
            if viewModel.isLoadingModeQueue {
                HStack(spacing: 10) {
                    ProgressView()
                        .tint(spotifyGreen)
                    Text("Finding tracks...")
                        .font(.system(size: 14, weight: .medium, design: .rounded))
                        .foregroundStyle(Color.white.opacity(0.5))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(14)
                .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            } else if !viewModel.modeQueue.isEmpty {
                // Queue list — show up to 5 upcoming tracks
                VStack(spacing: 0) {
                    ForEach(Array(viewModel.modeQueue.enumerated().prefix(5)), id: \.element.id) { index, track in
                        let isCurrent = index == viewModel.modeQueueIndex
                        Button {
                            viewModel.playFromModeQueue(at: index)
                        } label: {
                            HStack(spacing: 12) {
                                ZStack {
                                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                                        .fill(isCurrent ? spotifyGreen.opacity(0.2) : Color.white.opacity(0.06))
                                        .frame(width: 36, height: 36)

                                    if isCurrent && viewModel.spotifyIsPlaying {
                                        Image(systemName: "waveform")
                                            .font(.system(size: 14, weight: .bold))
                                            .foregroundStyle(spotifyGreen)
                                            .symbolEffect(.variableColor.iterative, isActive: true)
                                    } else {
                                        Text("\(index + 1)")
                                            .font(.system(size: 13, weight: .bold, design: .rounded))
                                            .foregroundStyle(isCurrent ? spotifyGreen : Color.white.opacity(0.3))
                                    }
                                }

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(track.title)
                                        .font(.system(size: 14, weight: isCurrent ? .bold : .semibold, design: .rounded))
                                        .foregroundStyle(isCurrent ? .white : Color.white.opacity(0.7))
                                        .lineLimit(1)

                                    Text(track.artist)
                                        .font(.system(size: 12, weight: .medium, design: .rounded))
                                        .foregroundStyle(Color.white.opacity(0.4))
                                        .lineLimit(1)
                                }

                                Spacer()

                                if isCurrent {
                                    Image(systemName: "play.fill")
                                        .font(.system(size: 10, weight: .bold))
                                        .foregroundStyle(spotifyGreen)
                                }
                            }
                            .padding(.vertical, 10)
                            .padding(.horizontal, 14)
                        }
                        .buttonStyle(.plain)

                        if index < min(viewModel.modeQueue.count, 5) - 1 {
                            Divider()
                                .background(Color.white.opacity(0.06))
                                .padding(.leading, 62)
                        }
                    }
                }
                .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            } else {
                // Fallback: show current preset track
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(viewModel.currentTrack.title)
                            .font(.system(size: 15, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                            .lineLimit(1)

                        Text(viewModel.currentTrack.vibe)
                            .font(.system(size: 12, weight: .medium, design: .rounded))
                            .foregroundStyle(spotifyGreen.opacity(0.8))
                    }

                    Spacer()

                }
                .padding(14)
                .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
        }
        .padding(20)
        .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
    }

    private func runModeIcon(for mode: RunAudioMode) -> String {
        switch mode {
        case .recovery: return "wind"
        case .base: return "figure.run"
        case .tempo: return "metronome.fill"
        case .longRun: return "road.lanes"
        case .race: return "bolt.fill"
        }
    }

    // MARK: - Playback Controls Card

    private var playbackControls: some View {
        VStack(spacing: 12) {
            if !viewModel.spotifyConnected {
                Button {
                    viewModel.connectSpotify()
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "link.circle.fill")
                            .font(.system(size: 18, weight: .bold))
                        Text("Connect Spotify")
                            .font(.system(size: 16, weight: .bold, design: .rounded))
                    }
                    .frame(maxWidth: .infinity)
                    .foregroundStyle(.black)
                    .padding(.vertical, 16)
                    .background(
                        Color(red: 0.13, green: 0.81, blue: 0.41),
                        in: RoundedRectangle(cornerRadius: 16, style: .continuous)
                    )
                }
                .buttonStyle(.plain)

                Text("Connect once to control playback directly from this screen.")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Color.white.opacity(0.4))
                    .multilineTextAlignment(.center)
            } else if !hasActivePlayback {
                VStack(spacing: 8) {
                    Button {
                        viewModel.togglePlayback()
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "play.fill")
                                .font(.system(size: 16, weight: .bold))
                            Text("Resume Playback")
                                .font(.system(size: 15, weight: .bold, design: .rounded))
                        }
                        .frame(maxWidth: .infinity)
                        .foregroundStyle(.black)
                        .padding(.vertical, 14)
                        .background(
                            Color(red: 0.13, green: 0.81, blue: 0.41),
                            in: RoundedRectangle(cornerRadius: 16, style: .continuous)
                        )
                    }
                    .buttonStyle(.plain)

                    Button {
                        viewModel.openSpotifyApp()
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "arrow.up.forward.app.fill")
                                .font(.system(size: 13, weight: .bold))
                            Text("Open Spotify")
                                .font(.system(size: 13, weight: .semibold, design: .rounded))
                        }
                        .foregroundStyle(Color.white.opacity(0.5))
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 4)
                }
            }

        }
    }

    // MARK: - Run Jam Card

    private var runJamCard: some View {
        VStack(alignment: .leading, spacing: AppSpacing.md) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Run Jam")
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                    Text(viewModel.jamStatusLabel)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Color.white.opacity(0.55))
                }

                Spacer()

                if viewModel.jamActive {
                    Text("\(viewModel.jamListenerCount)")
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                        .foregroundStyle(Color(red: 0.13, green: 0.81, blue: 0.41))
                    + Text(" listening")
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundStyle(Color.white.opacity(0.5))
                }
            }

            if viewModel.jamActive {
                Button {
                    viewModel.isCurrentUserInJam ? viewModel.leaveJam() : viewModel.joinJam()
                } label: {
                    Text(viewModel.isCurrentUserInJam ? "Leave Jam" : "Join Jam")
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .frame(maxWidth: .infinity)
                        .foregroundStyle(.white)
                        .padding(.vertical, 12)
                        .background(Color.white.opacity(0.1), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(.plain)
            } else if viewModel.selectedLiveRunSessionId != nil {
                Button {
                    viewModel.startJam()
                } label: {
                    Text("Start Jam")
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .frame(maxWidth: .infinity)
                        .foregroundStyle(.black)
                        .padding(.vertical, 12)
                        .background(Color(red: 0.13, green: 0.81, blue: 0.41), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(20)
        .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
    }


    private func summaryRow(icon: String, label: String, value: String) -> some View {
        HStack {
            Image(systemName: icon)
                .font(.system(size: 18))
                .foregroundStyle(Color(red: 0.95, green: 0.33, blue: 0.19))
                .frame(width: 28)

            Text(label)
                .font(AppTypography.body)
                .foregroundStyle(Color.white.opacity(0.52))

            Spacer()

            Text(value)
                .font(AppTypography.bodySemibold)
                .foregroundStyle(.white)
                .monospacedDigit()
        }
    }

    private func formatDistance(_ meters: Double) -> String {
        guard meters > 0 else { return "0 m" }
        if meters >= 1000 {
            return String(format: "%.2f km", meters / 1000.0)
        }
        return "\(Int(meters)) m"
    }

    private func formatDurationSeconds(_ seconds: Int) -> String {
        let clamped = max(0, seconds)
        let h = clamped / 3600
        let m = (clamped % 3600) / 60
        let s = clamped % 60
        if h > 0 {
            return String(format: "%d:%02d:%02d", h, m, s)
        }
        return String(format: "%02d:%02d", m, s)
    }

    private func formatPace(_ secondsPerKm: Int?) -> String {
        guard let secondsPerKm, secondsPerKm > 0 else { return "--:-- /km" }
        let m = secondsPerKm / 60
        let s = secondsPerKm % 60
        return String(format: "%d:%02d /km", m, s)
    }

    private static let shortDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE, MMM d"
        formatter.locale = Locale(identifier: "en_US")
        return formatter
    }()

    private static let calendarMonthFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM"
        formatter.locale = Locale(identifier: "en_US")
        return formatter
    }()

    private static let upcomingTimelineDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd • HH:mm"
        formatter.locale = Locale(identifier: "en_US")
        return formatter
    }()
}

private struct RecentRunDetailSheet: View {
    let run: RunningDashboardData.RecentRun

    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel: RecentRunDetailViewModel

    init(run: RunningDashboardData.RecentRun) {
        self.run = run
        _viewModel = StateObject(wrappedValue: RecentRunDetailViewModel(run: run))
    }

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(spacing: AppSpacing.lg) {
                    heroCard
                    routeCard
                    segmentCard
                    checkpointCard
                    crewCard
                }
                .padding(.horizontal, AppSpacing.screenHorizontal)
                .padding(.top, AppSpacing.md)
                .padding(.bottom, AppSpacing.screenVerticalBottom)
            }
            .background(
                LinearGradient(
                    colors: [
                        Color(red: 0.96, green: 0.97, blue: 0.99),
                        AppColors.backgroundPrimary
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()
            )
            .navigationTitle("Run Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            .task {
                await viewModel.loadIfNeeded()
            }
        }
    }

    private var heroCard: some View {
        ZStack(alignment: .bottomLeading) {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.08, green: 0.13, blue: 0.26),
                            Color(red: 0.16, green: 0.39, blue: 0.65),
                            Color(red: 0.98, green: 0.44, blue: 0.22)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay(alignment: .topTrailing) {
                    Circle()
                        .fill(Color.white.opacity(0.10))
                        .frame(width: 170, height: 170)
                        .offset(x: 40, y: -40)
                }

            VStack(alignment: .leading, spacing: AppSpacing.md) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("RECENT RUN")
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                            .foregroundStyle(Color.white.opacity(0.68))
                            .tracking(1.6)

                        Text(Self.headerDateFormatter.string(from: run.date))
                            .font(.system(size: 30, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)

                        Text(viewModel.sessionHeadline)
                            .font(AppTypography.callout)
                            .foregroundStyle(Color.white.opacity(0.80))
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer(minLength: 12)

                    VStack(alignment: .trailing, spacing: 8) {
                        detailStatusChip(viewModel.isCrewRun ? "Crew Linked" : "Solo")
                        detailStatusChip(viewModel.syncLabel)
                    }
                }

                HStack(spacing: AppSpacing.sm) {
                    detailMetricPill(title: "Distance", value: Self.formatDistance(run.distanceMeters))
                    detailMetricPill(title: "Duration", value: Self.formatDuration(run.durationSeconds))
                    detailMetricPill(title: "Pace", value: Self.formatPace(run.avgPaceSecondsPerKm))
                }

                HStack(spacing: AppSpacing.sm) {
                    detailMetricPill(title: "Earned", value: "+\(run.earnedMinutes)m")
                    detailMetricPill(title: "Calories", value: "\(viewModel.caloriesBurned)")
                    detailMetricPill(title: "Points", value: "\(viewModel.routePoints.count)")
                }
            }
            .padding(AppSpacing.xl)
        }
        .overlay {
            if viewModel.isLoading {
                ProgressView()
                    .tint(.white)
            }
        }
    }

    private var routeCard: some View {
        Card(padding: 0, hasShadow: true) {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    detailSectionHeader("Route", subtitle: "GPS line, elevation markers, and coverage")
                    Spacer()
                }
                .padding(.horizontal, AppSpacing.cardPadding)
                .padding(.top, AppSpacing.cardPadding)

                RecentRunRouteMap(routePoints: viewModel.routePoints)
                    .frame(height: 250)
                    .padding(AppSpacing.sm)

                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: AppSpacing.sm) {
                    detailStatTile(title: "Active", value: Self.formatDuration(viewModel.activeDurationSeconds), icon: "figure.run", tint: AppColors.success)
                    detailStatTile(title: "Paused", value: Self.formatDuration(viewModel.pauseDurationSeconds), icon: "pause.fill", tint: AppColors.warning)
                    detailStatTile(title: "Active Dist.", value: Self.formatDistance(viewModel.activeDistanceMeters), icon: "location.north.line.fill", tint: AppColors.info)
                    detailStatTile(title: "Pause Dist.", value: Self.formatDistance(viewModel.pauseDistanceMeters), icon: "moon.zzz.fill", tint: AppColors.secondary)
                }
                .padding(.horizontal, AppSpacing.cardPadding)
                .padding(.bottom, AppSpacing.cardPadding)
            }
        }
    }

    private var segmentCard: some View {
        Card {
            VStack(alignment: .leading, spacing: AppSpacing.md) {
                detailSectionHeader("Segments", subtitle: "Every running and pause block captured for this run")

                if viewModel.segments.isEmpty {
                    Text("No segmented run data is available for this session yet.")
                        .font(AppTypography.caption1)
                        .foregroundStyle(AppColors.textSecondary)
                } else {
                    ForEach(Array(viewModel.segmentRows.enumerated()), id: \.element.id) { index, segment in
                        HStack(alignment: .top, spacing: AppSpacing.sm) {
                            ZStack {
                                Circle()
                                    .fill(segment.isPause ? AppColors.warning.opacity(0.12) : AppColors.success.opacity(0.12))
                                    .frame(width: 42, height: 42)

                                Image(systemName: segment.isPause ? "pause.fill" : "figure.run")
                                    .font(.system(size: 15, weight: .bold))
                                    .foregroundStyle(segment.isPause ? AppColors.warning : AppColors.success)
                            }

                            VStack(alignment: .leading, spacing: 4) {
                                Text(segment.title)
                                    .font(AppTypography.bodySemibold)
                                    .foregroundStyle(AppColors.textPrimary)
                                Text(segment.subtitle)
                                    .font(AppTypography.caption1)
                                    .foregroundStyle(AppColors.textSecondary)
                            }

                            Spacer()

                            VStack(alignment: .trailing, spacing: 4) {
                                Text(segment.metric)
                                    .font(AppTypography.bodySemibold)
                                    .foregroundStyle(AppColors.textPrimary)
                                Text(segment.trailingDetail)
                                    .font(AppTypography.caption1)
                                    .foregroundStyle(AppColors.textSecondary)
                            }
                        }

                        if index != viewModel.segmentRows.indices.last {
                            Divider()
                        }
                    }
                }
            }
        }
    }

    private var checkpointCard: some View {
        Card {
            VStack(alignment: .leading, spacing: AppSpacing.md) {
                detailSectionHeader("Checkpoints", subtitle: "Key route points pulled from the recorded GPS timeline")

                if viewModel.checkpoints.isEmpty {
                    Text("No route checkpoints were generated because this run has too few GPS points.")
                        .font(AppTypography.caption1)
                        .foregroundStyle(AppColors.textSecondary)
                } else {
                    ForEach(viewModel.checkpoints) { checkpoint in
                        HStack(spacing: AppSpacing.sm) {
                            VStack(spacing: 2) {
                                Text(checkpoint.badge)
                                    .font(.system(size: 10, weight: .bold, design: .rounded))
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 5)
                                    .background(checkpoint.tint, in: Capsule())
                            }
                            .frame(width: 64)

                            VStack(alignment: .leading, spacing: 3) {
                                Text(checkpoint.title)
                                    .font(AppTypography.bodySemibold)
                                    .foregroundStyle(AppColors.textPrimary)
                                Text(checkpoint.subtitle)
                                    .font(AppTypography.caption1)
                                    .foregroundStyle(AppColors.textSecondary)
                            }

                            Spacer()

                            VStack(alignment: .trailing, spacing: 3) {
                                Text(checkpoint.coordinateLabel)
                                    .font(.system(size: 12, weight: .bold, design: .rounded))
                                    .foregroundStyle(AppColors.textPrimary)
                                Text(checkpoint.timestampLabel)
                                    .font(AppTypography.caption1)
                                    .foregroundStyle(AppColors.textSecondary)
                            }
                        }
                    }
                }
            }
        }
    }

    private var crewCard: some View {
        Card {
            VStack(alignment: .leading, spacing: AppSpacing.md) {
                detailSectionHeader("Crew Layer", subtitle: "Social session, members, and awarded run XP")

                if let errorMessage = viewModel.socialErrorMessage {
                    Text(errorMessage)
                        .font(AppTypography.caption1)
                        .foregroundStyle(AppColors.textSecondary)
                }

                if let snapshot = viewModel.liveSnapshot, let session = snapshot.session {
                    HStack(spacing: AppSpacing.sm) {
                        detailStatTile(title: "Mode", value: session.mode.capitalized, icon: "bolt.heart.fill", tint: AppColors.secondary)
                        detailStatTile(title: "Presence", value: "\(snapshot.presenceCount)", icon: "dot.radiowaves.left.and.right", tint: AppColors.info)
                        detailStatTile(title: "Members", value: "\(snapshot.participants.count)", icon: "person.3.fill", tint: AppColors.primary)
                    }

                    VStack(alignment: .leading, spacing: AppSpacing.sm) {
                        Text("Members")
                            .font(AppTypography.bodySemibold)
                            .foregroundStyle(AppColors.textPrimary)

                        ForEach(snapshot.participants, id: \.id) { participant in
                            HStack(spacing: AppSpacing.sm) {
                                Circle()
                                    .fill(participant.isLeader ? AppColors.secondary.opacity(0.18) : AppColors.fill)
                                    .frame(width: 38, height: 38)
                                    .overlay(
                                        Text(viewModel.initials(for: participant.userId))
                                            .font(.system(size: 13, weight: .bold, design: .rounded))
                                            .foregroundStyle(participant.isLeader ? AppColors.secondary : AppColors.textPrimary)
                                    )

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(viewModel.displayName(for: participant.userId))
                                        .font(AppTypography.bodySemibold)
                                        .foregroundStyle(AppColors.textPrimary)
                                    Text(participant.status.capitalized.replacingOccurrences(of: "_", with: " "))
                                        .font(AppTypography.caption1)
                                        .foregroundStyle(AppColors.textSecondary)
                                }

                                Spacer()

                                if participant.isLeader {
                                    Text("Leader")
                                        .font(.system(size: 10, weight: .bold, design: .rounded))
                                        .foregroundStyle(AppColors.secondary)
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 5)
                                        .background(AppColors.secondary.opacity(0.10), in: Capsule())
                                }
                            }
                        }
                    }

                    if !viewModel.xpAwards.isEmpty {
                        VStack(alignment: .leading, spacing: AppSpacing.sm) {
                            Text("Run XP Awards")
                                .font(AppTypography.bodySemibold)
                                .foregroundStyle(AppColors.textPrimary)

                            ForEach(viewModel.xpAwards, id: \.id) { award in
                                HStack(spacing: AppSpacing.sm) {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(viewModel.displayName(for: award.userId))
                                            .font(AppTypography.bodySemibold)
                                            .foregroundStyle(AppColors.textPrimary)
                                        Text(award.bonusType.capitalized)
                                            .font(AppTypography.caption1)
                                            .foregroundStyle(AppColors.textSecondary)
                                    }

                                    Spacer()

                                    VStack(alignment: .trailing, spacing: 2) {
                                        Text("+\(award.totalXpAwarded) XP")
                                            .font(AppTypography.bodySemibold)
                                            .foregroundStyle(AppColors.secondary)
                                        Text("Base \(award.baseXp) • Bonus \(award.bonusXp)")
                                            .font(AppTypography.caption1)
                                            .foregroundStyle(AppColors.textSecondary)
                                    }
                                }
                            }
                        }
                    }
                } else {
                    HStack(spacing: AppSpacing.sm) {
                        ZStack {
                            Circle()
                                .fill(AppColors.fill)
                                .frame(width: 44, height: 44)

                            Image(systemName: "person.2.slash.fill")
                                .font(.system(size: 18, weight: .bold))
                                .foregroundStyle(AppColors.textSecondary)
                        }

                        VStack(alignment: .leading, spacing: 3) {
                            Text("Solo session")
                                .font(AppTypography.bodySemibold)
                                .foregroundStyle(AppColors.textPrimary)
                            Text("This run was not linked to a crew session, so there are no live members or social XP rows to show.")
                                .font(AppTypography.caption1)
                                .foregroundStyle(AppColors.textSecondary)
                        }
                    }
                }
            }
        }
    }

    private func detailSectionHeader(_ title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(AppTypography.headline)
                .foregroundStyle(.white)
            Text(subtitle)
                .font(AppTypography.caption1)
                .foregroundStyle(Color.white.opacity(0.52))
        }
    }

    private func detailMetricPill(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title.uppercased())
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .foregroundStyle(Color.white.opacity(0.62))
                .tracking(1.1)

            Text(value)
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, AppSpacing.sm)
        .padding(.vertical, AppSpacing.sm)
        .background(Color.white.opacity(0.12), in: RoundedRectangle(cornerRadius: AppSpacing.cornerRadiusCard))
    }

    private func detailStatusChip(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.system(size: 10, weight: .bold, design: .rounded))
            .foregroundStyle(.white)
            .tracking(1.0)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(Color.white.opacity(0.12), in: Capsule())
    }

    private func detailStatTile(title: String, value: String, icon: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(tint)
            Text(value)
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundStyle(AppColors.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(title)
                .font(AppTypography.caption1)
                .foregroundStyle(AppColors.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(AppSpacing.md)
        .background(AppColors.backgroundPrimary, in: RoundedRectangle(cornerRadius: AppSpacing.cornerRadiusCard))
    }

    private static let headerDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE, MMM d"
        formatter.locale = Locale(identifier: "en_US")
        return formatter
    }()

    fileprivate static func formatDistance(_ meters: Double) -> String {
        if meters >= 1000 {
            return String(format: "%.2f km", meters / 1000.0)
        }
        return String(format: "%.0f m", meters)
    }

    fileprivate static func formatDuration(_ seconds: Int) -> String {
        let h = seconds / 3600
        let m = (seconds % 3600) / 60
        let s = seconds % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%02d:%02d", m, s)
    }

    fileprivate static func formatPace(_ secondsPerKm: Int?) -> String {
        guard let secondsPerKm, secondsPerKm > 0 else { return "--:-- /km" }
        let m = secondsPerKm / 60
        let s = secondsPerKm % 60
        return String(format: "%d:%02d /km", m, s)
    }
}

@MainActor
private final class RecentRunDetailViewModel: ObservableObject {
    @Published private(set) var isLoading = false
    @Published private(set) var session: Shared.JoggingSession?
    @Published private(set) var routePoints: [Shared.RoutePoint] = []
    @Published private(set) var segments: [Shared.JoggingSegment] = []
    @Published private(set) var liveSnapshot: RunCrewSnapshot?
    @Published private(set) var xpAwards: [RunXpAwardSummary] = []
    @Published private(set) var usersById: [String: RunUserSummary] = [:]
    @Published private(set) var socialErrorMessage: String?

    let run: RunningDashboardData.RecentRun
    private var didLoad = false

    init(run: RunningDashboardData.RecentRun) {
        self.run = run
    }

    var caloriesBurned: Int {
        session.map { Int($0.caloriesBurned) } ?? 0
    }

    var activeDurationSeconds: Int {
        if let session, Int(session.activeDurationSeconds) > 0 {
            return Int(session.activeDurationSeconds)
        }
        return segments
            .filter { !Self.isPauseSegment($0) }
            .reduce(0) { $0 + Int($1.durationSeconds) }
    }

    var pauseDurationSeconds: Int {
        if let session, Int(session.pauseDurationSeconds) > 0 {
            return Int(session.pauseDurationSeconds)
        }
        return segments
            .filter(Self.isPauseSegment)
            .reduce(0) { $0 + Int($1.durationSeconds) }
    }

    var activeDistanceMeters: Double {
        if let session, session.activeDistanceMeters > 0 {
            return session.activeDistanceMeters
        }
        return segments
            .filter { !Self.isPauseSegment($0) }
            .reduce(0.0) { $0 + $1.distanceMeters }
    }

    var pauseDistanceMeters: Double {
        if let session, session.pauseDistanceMeters > 0 {
            return session.pauseDistanceMeters
        }
        return segments
            .filter(Self.isPauseSegment)
            .reduce(0.0) { $0 + $1.distanceMeters }
    }

    var isCrewRun: Bool {
        session?.liveRunSessionId != nil
    }

    var syncLabel: String {
        guard let session else { return "Local" }
        return String(describing: session.syncStatus)
            .replacingOccurrences(of: "_", with: " ")
            .capitalized
    }

    var sessionHeadline: String {
        if let session, session.liveRunSessionId != nil {
            return "This run stayed linked to a crew session, so route, segments, members, and social XP can all be inspected together."
        }
        return "Detailed breakdown of route coverage, pause blocks, and the exact timeline captured during this session."
    }

    var segmentRows: [RunSegmentRow] {
        segments.enumerated().map { index, segment in
            let isPause = Self.isPauseSegment(segment)
            let duration = Int(segment.durationSeconds)
            let distance = segment.distanceMeters
            let secondsPerKm = (!isPause && duration > 0 && distance > 0)
                ? Int((Double(duration) / distance) * 1000.0)
                : nil

            return RunSegmentRow(
                id: segment.id,
                isPause: isPause,
                title: isPause ? "Pause \(index + 1)" : "Run Block \(index + 1)",
                subtitle: "\(Self.timeLabel(epochSeconds: segment.startedAt.epochSeconds)) to \(Self.timeLabel(epochSeconds: (segment.endedAt ?? segment.startedAt).epochSeconds))",
                metric: RecentRunDetailSheet.formatDistance(distance),
                trailingDetail: isPause ? "Paused" : RecentRunDetailSheet.formatPace(secondsPerKm),
                durationSeconds: duration
            )
        }
    }

    var checkpoints: [RunCheckpoint] {
        guard !routePoints.isEmpty else { return [] }
        var items: [RunCheckpoint] = []

        if let first = routePoints.first {
            items.append(checkpoint(from: first, title: "Start", badge: "START", tint: AppColors.success))
        }

        let milestones = [1000.0, 3000.0, 5000.0, 10000.0]
        for milestone in milestones {
            if let point = routePoints.first(where: { $0.distanceFromStart >= milestone }) {
                items.append(
                    checkpoint(
                        from: point,
                        title: "\(Int(milestone / 1000.0)) km mark",
                        badge: "\(Int(milestone / 1000.0))K",
                        tint: AppColors.info
                    )
                )
            }
        }

        if let last = routePoints.last, last.id != routePoints.first?.id {
            items.append(checkpoint(from: last, title: "Finish", badge: "END", tint: AppColors.secondary))
        }

        var seen = Set<String>()
        return items.filter { seen.insert($0.id).inserted }
    }

    func loadIfNeeded() async {
        guard !didLoad else { return }
        didLoad = true
        await load()
    }

    func displayName(for userId: String) -> String {
        usersById[userId]?.displayName ?? "Runner"
    }

    func initials(for userId: String) -> String {
        let source = displayName(for: userId).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !source.isEmpty else { return "R" }
        let parts = source.split(separator: " ")
        if parts.count >= 2 {
            return "\(parts[0].prefix(1))\(parts[1].prefix(1))".uppercased()
        }
        return String(source.prefix(2)).uppercased()
    }

    private func load() async {
        isLoading = true
        socialErrorMessage = nil

        async let sessionTask = fetchSession()
        async let routeTask = fetchRoutePoints()
        async let segmentTask = fetchSegments()

        let resolvedSession = await sessionTask
        session = resolvedSession
        routePoints = await routeTask
        segments = await segmentTask

        if let liveRunSessionId = resolvedSession?.liveRunSessionId {
            async let snapshotTask = fetchLiveSnapshot(sessionId: liveRunSessionId)
            async let awardsTask = fetchAwards(sessionId: liveRunSessionId)
            let snapshot = await snapshotTask
            let awards = await awardsTask
            liveSnapshot = snapshot
            xpAwards = awards

            let userIds = Set(
                (snapshot?.participants.map(\.userId) ?? []) +
                awards.map(\.userId) +
                [snapshot?.session?.leaderUserId].compactMap { $0 }
            )

            if !userIds.isEmpty {
                let users = await fetchUsers(ids: Array(userIds))
                usersById = Dictionary(uniqueKeysWithValues: users.map { ($0.id, $0) })
            }

            if snapshot == nil && awards.isEmpty {
                socialErrorMessage = "No finished crew snapshot was available locally for this run."
            }
        }

        isLoading = false
    }

    private func fetchSession() async -> Shared.JoggingSession? {
        await withCheckedContinuation { continuation in
            DataBridge.shared.fetchJoggingSession(sessionId: run.id) { session in
                continuation.resume(returning: session)
            }
        }
    }

    private func fetchRoutePoints() async -> [Shared.RoutePoint] {
        await withCheckedContinuation { continuation in
            DataBridge.shared.fetchRoutePointsForSession(sessionId: run.id) { points in
                continuation.resume(returning: points)
            }
        }
    }

    private func fetchSegments() async -> [Shared.JoggingSegment] {
        await withCheckedContinuation { continuation in
            DataBridge.shared.fetchJoggingSegmentsForSession(sessionId: run.id) { segments in
                continuation.resume(returning: segments)
            }
        }
    }

    private func fetchLiveSnapshot(sessionId: String) async -> RunCrewSnapshot? {
        await withCheckedContinuation { continuation in
            DataBridge.shared.fetchLiveRunSessionSnapshot(sessionId: sessionId) { snapshot in
                let mapped = snapshot.map { value in
                    RunCrewSnapshot(
                        session: value.session.map {
                            RunCrewSessionSummary(
                                id: $0.id,
                                leaderUserId: $0.leaderUserId,
                                mode: $0.mode,
                                state: $0.state,
                                participantCount: Int($0.participantCount)
                            )
                        },
                        participants: value.participants.map {
                            RunCrewParticipantSummary(
                                id: $0.id,
                                userId: $0.userId,
                                status: $0.status,
                                isLeader: $0.isLeader
                            )
                        },
                        presenceCount: Int(value.presenceCount)
                    )
                }
                continuation.resume(returning: mapped)
            }
        }
    }

    private func fetchAwards(sessionId: String) async -> [RunXpAwardSummary] {
        await withCheckedContinuation { continuation in
            DataBridge.shared.fetchRunXpAwardsForSession(sessionId: sessionId) { awards in
                let mapped = awards.map {
                    RunXpAwardSummary(
                        id: $0.id,
                        userId: $0.userId,
                        baseXp: Int($0.baseXp),
                        bonusType: $0.bonusType,
                        bonusXp: Int($0.bonusXp),
                        totalXpAwarded: Int($0.totalXpAwarded)
                    )
                }
                continuation.resume(returning: mapped)
            }
        }
    }

    private func fetchUsers(ids: [String]) async -> [RunUserSummary] {
        await withCheckedContinuation { continuation in
            DataBridge.shared.fetchRunUsers(userIds: ids) { users in
                let mapped = users.map {
                    RunUserSummary(
                        id: $0.id,
                        username: $0.username,
                        displayName: $0.displayName,
                        avatarUrl: $0.avatarUrl
                    )
                }
                continuation.resume(returning: mapped)
            }
        }
    }

    private func checkpoint(from point: Shared.RoutePoint, title: String, badge: String, tint: Color) -> RunCheckpoint {
        let timestamp = Date(timeIntervalSince1970: Double(point.timestamp.epochSeconds))
        return RunCheckpoint(
            id: point.id,
            title: title,
            subtitle: RecentRunDetailSheet.formatDistance(point.distanceFromStart),
            badge: badge,
            tint: tint,
            coordinateLabel: String(format: "%.4f, %.4f", point.latitude, point.longitude),
            timestampLabel: Self.pointTimeFormatter.string(from: timestamp),
            timestamp: timestamp
        )
    }

    private static func isPauseSegment(_ segment: Shared.JoggingSegment) -> Bool {
        String(describing: segment.type).lowercased().contains("pause")
    }

    private static func timeLabel(epochSeconds: Int64) -> String {
        pointTimeFormatter.string(from: Date(timeIntervalSince1970: Double(epochSeconds)))
    }

    private static let pointTimeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        formatter.locale = Locale(identifier: "en_US")
        return formatter
    }()
}

private struct RecentRunRouteMap: View {
    let routePoints: [Shared.RoutePoint]
    @State private var mapPosition: MapCameraPosition = .automatic

    private var coordinates: [CLLocationCoordinate2D] {
        RouteSmoothing.smoothCoordinates(
            routePoints.map { CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude) }
        )
    }

    var body: some View {
        ZStack {
            if coordinates.isEmpty {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(AppColors.backgroundPrimary)
                    .overlay {
                        VStack(spacing: AppSpacing.sm) {
                            Image(systemName: "map")
                                .font(.system(size: 28, weight: .light))
                                .foregroundStyle(AppColors.textTertiary)
                            Text("No route recorded")
                                .font(AppTypography.bodySemibold)
                                .foregroundStyle(AppColors.textPrimary)
                            Text("This session does not have enough GPS breadcrumbs for a route preview.")
                                .font(AppTypography.caption1)
                                .foregroundStyle(AppColors.textSecondary)
                                .multilineTextAlignment(.center)
                        }
                        .padding(AppSpacing.lg)
                    }
            } else {
                Map(position: $mapPosition) {
                    if let start = coordinates.first {
                        Annotation("Start", coordinate: start) {
                            Circle()
                                .fill(AppColors.success)
                                .frame(width: 14, height: 14)
                                .overlay(Circle().stroke(.white, lineWidth: 2))
                        }
                    }

                    if coordinates.count >= 2 {
                        MapPolyline(coordinates: coordinates)
                            .stroke(
                                LinearGradient(
                                    colors: [AppColors.info, AppColors.secondary],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                ),
                                lineWidth: 5
                            )
                    }

                    if let end = coordinates.last {
                        Annotation("End", coordinate: end) {
                            Circle()
                                .fill(AppColors.secondary)
                                .frame(width: 14, height: 14)
                                .overlay(Circle().stroke(.white, lineWidth: 2))
                        }
                    }
                }
                .mapStyle(.standard(elevation: .flat))
                .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                .onAppear {
                    mapPosition = .region(mapRegion(for: coordinates))
                }
            }
        }
    }

    private func mapRegion(for coordinates: [CLLocationCoordinate2D]) -> MKCoordinateRegion {
        guard let first = coordinates.first else {
            return MKCoordinateRegion(
                center: CLLocationCoordinate2D(latitude: 0, longitude: 0),
                span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
            )
        }

        var minLat = first.latitude
        var maxLat = first.latitude
        var minLon = first.longitude
        var maxLon = first.longitude

        for coordinate in coordinates {
            minLat = min(minLat, coordinate.latitude)
            maxLat = max(maxLat, coordinate.latitude)
            minLon = min(minLon, coordinate.longitude)
            maxLon = max(maxLon, coordinate.longitude)
        }

        return MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: (minLat + maxLat) / 2, longitude: (minLon + maxLon) / 2),
            span: MKCoordinateSpan(
                latitudeDelta: max((maxLat - minLat) * 1.35, 0.004),
                longitudeDelta: max((maxLon - minLon) * 1.35, 0.004)
            )
        )
    }
}

private struct RunSegmentRow: Identifiable {
    let id: String
    let isPause: Bool
    let title: String
    let subtitle: String
    let metric: String
    let trailingDetail: String
    let durationSeconds: Int
}

private struct RunCheckpoint: Identifiable {
    let id: String
    let title: String
    let subtitle: String
    let badge: String
    let tint: Color
    let coordinateLabel: String
    let timestampLabel: String
    let timestamp: Date
}

private struct RunCrewSnapshot {
    let session: RunCrewSessionSummary?
    let participants: [RunCrewParticipantSummary]
    let presenceCount: Int
}

private struct RunCrewSessionSummary {
    let id: String
    let leaderUserId: String
    let mode: String
    let state: String
    let participantCount: Int
}

private struct RunCrewParticipantSummary: Identifiable {
    let id: String
    let userId: String
    let status: String
    let isLeader: Bool
}

private struct RunXpAwardSummary: Identifiable {
    let id: String
    let userId: String
    let baseXp: Int
    let bonusType: String
    let bonusXp: Int
    let totalXpAwarded: Int
}

private struct RunUserSummary: Identifiable {
    let id: String
    let username: String?
    let displayName: String
    let avatarUrl: String?
}

private struct SpotifyLiveBarsView: View {
    let isAnimating: Bool
    let tint: Color

    private let baseline: [CGFloat] = [0.34, 0.70, 0.48, 0.86, 0.58, 0.78]

    var body: some View {
        TimelineView(.animation(minimumInterval: 0.06, paused: !isAnimating)) { context in
            let time = context.date.timeIntervalSinceReferenceDate

            HStack(alignment: .bottom, spacing: 3) {
                ForEach(baseline.indices, id: \.self) { index in
                    Capsule(style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [
                                    tint.opacity(isAnimating ? 0.96 : 0.26),
                                    tint.opacity(isAnimating ? 0.60 : 0.16)
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .frame(width: 3, height: barHeight(at: index, time: time))
                }
            }
            .frame(width: 30, height: 16, alignment: .bottom)
        }
        .accessibilityHidden(true)
    }

    private func barHeight(at index: Int, time: TimeInterval) -> CGFloat {
        guard isAnimating else { return 6 + (baseline[index] * 6) }
        let primary = 0.5 + 0.5 * sin(time * 2.8 + Double(index) * 0.52)
        let secondary = 0.5 + 0.5 * sin(time * 1.9 + Double(index) * 0.91 + 0.8)
        let blend = (primary * 0.72) + (secondary * 0.28)
        let value = max(0.20, baseline[index] * 0.72 + CGFloat(blend) * 0.58)
        return 6 + (value * 9)
    }
}

// MARK: - Previews

#if DEBUG
#Preview("Jogging View") {
    JoggingView()
}
#endif
