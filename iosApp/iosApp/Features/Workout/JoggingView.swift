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
    @State private var showCrewView = false
    @State private var showMusicSheet = false
    @State private var selectedRecentRun: RunningDashboardData.RecentRun?
    @State private var isMapFocusMode = false
    @State private var shareImage: UIImage?
    @State private var isRenderingShareImage = false
    @State private var mapPosition: MapCameraPosition = .automatic
    @State private var isFollowingRunner = false
    @State private var isCurrentMarkerPulsing = false
#if DEBUG
    /// Temporary: simulates 0→1000 m for ring + DIST only; remove when no longer needed.
    @State private var simulatedDistanceMeters: Double?
    @State private var distanceSimulationTask: Task<Void, Never>?
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
        .fullScreenCover(isPresented: $showCrewView) {
            CrewRunView(viewModel: viewModel)
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
                runLaunchCard
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
                            .lineLimit(2)
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

    private var runLaunchCard: some View {
        VStack(spacing: AppSpacing.md) {
            HStack(alignment: .top, spacing: AppSpacing.md) {
                VStack(alignment: .leading, spacing: AppSpacing.xxs) {
                    Text("Quick Start")
                        .font(AppTypography.headline)
                        .foregroundStyle(AppColors.textPrimary)

                    Text(
                        viewModel.hasLocationPermission
                        ? "GPS is ready. Go solo, join a live crew run, or launch a planned event with your people."
                        : "Allow location first so distance, pace, route, and earned time can be tracked correctly."
                    )
                    .font(AppTypography.caption1)
                    .foregroundStyle(AppColors.textSecondary)
                }

                Spacer(minLength: 12)

                Text("+1 min / km")
                    .font(AppTypography.captionSemibold)
                    .foregroundStyle(AppColors.info)
                    .padding(.horizontal, AppSpacing.sm)
                    .padding(.vertical, AppSpacing.xs)
                .background(AppColors.info.opacity(0.10), in: Capsule())
            }

            HStack(spacing: AppSpacing.sm) {
                Image(systemName: "dot.radiowaves.left.and.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(AppColors.info)
                Text(viewModel.socialSelectionSummary)
                    .font(AppTypography.caption1)
                    .foregroundStyle(AppColors.textSecondary)
                Spacer()
            }
            .padding(.horizontal, AppSpacing.xs)

            VStack(alignment: .leading, spacing: AppSpacing.xs) {
                Text("Run Mode")
                    .font(AppTypography.captionSemibold)
                    .foregroundStyle(AppColors.textSecondary)

                Picker("Run Mode", selection: $viewModel.launchMode) {
                    ForEach(RunLaunchMode.allCases) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
            }

            if !viewModel.hasLocationPermission {
                HStack(spacing: AppSpacing.sm) {
                    Image(systemName: "location.fill")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(AppColors.warning)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Location access required")
                            .font(AppTypography.bodySemibold)
                            .foregroundStyle(AppColors.textPrimary)
                        Text("Without location, running metrics and route capture cannot start.")
                            .font(AppTypography.caption1)
                            .foregroundStyle(AppColors.textSecondary)
                    }

                    Spacer()
                }
                .padding(AppSpacing.md)
                .background(AppColors.warning.opacity(0.08), in: RoundedRectangle(cornerRadius: AppSpacing.cornerRadiusCard))
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

            HStack(spacing: AppSpacing.sm) {
                quickRunAction(
                    title: "Crew",
                    subtitle: viewModel.socialSelectionSummary,
                    icon: "person.2.fill"
                ) {
                    showCrewView = true
                }

                quickRunAction(
                    title: "Plan",
                    subtitle: viewModel.upcomingEventCountLabel,
                    icon: "calendar.badge.plus"
                ) {
                    showCrewView = true
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
        .background(AppColors.backgroundSecondary, in: RoundedRectangle(cornerRadius: AppSpacing.cornerRadiusLarge))
    }

    private var futureRunsCard: some View {
        Card {
            VStack(alignment: .leading, spacing: AppSpacing.md) {
                sectionEyebrow(title: "Run Calendar", subtitle: "Future events you joined or planned")

                HStack(alignment: .top, spacing: AppSpacing.md) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(viewModel.upcomingEventCountLabel)
                            .font(AppTypography.bodySemibold)
                            .foregroundStyle(AppColors.textPrimary)
                        Text(viewModel.nextUpcomingRunSummary)
                            .font(AppTypography.caption1)
                            .foregroundStyle(AppColors.textSecondary)
                    }

                    Spacer(minLength: 12)

                    Button("Open Planner") {
                        showCrewView = true
                    }
                    .font(AppTypography.captionSemibold)
                    .foregroundStyle(.white)
                    .padding(.horizontal, AppSpacing.md)
                    .padding(.vertical, AppSpacing.xs)
                    .background(AppColors.secondary, in: Capsule())
                    .buttonStyle(.plain)
                }

                if viewModel.upcomingRuns.isEmpty {
                    Text("No events on the calendar yet. Open the planner to schedule a crew run in the future.")
                        .font(AppTypography.caption1)
                        .foregroundStyle(AppColors.textSecondary)
                } else {
                    VStack(spacing: AppSpacing.sm) {
                        ForEach(Array(viewModel.upcomingRuns.sorted(by: { $0.plannedStartAt < $1.plannedStartAt }).prefix(3))) { run in
                            HStack(spacing: AppSpacing.sm) {
                                VStack(spacing: 2) {
                                    Text(Self.calendarMonthFormatter.string(from: run.plannedStartAt).uppercased())
                                        .font(AppTypography.caption2)
                                        .foregroundStyle(AppColors.textSecondary)
                                    Text("\(Calendar.current.component(.day, from: run.plannedStartAt))")
                                        .font(.system(size: 22, weight: .bold, design: .rounded))
                                        .foregroundStyle(AppColors.textPrimary)
                                }
                                .frame(width: 52)
                                .padding(.vertical, AppSpacing.xs)
                                .background(AppColors.backgroundPrimary, in: RoundedRectangle(cornerRadius: AppSpacing.cornerRadiusCard))

                                VStack(alignment: .leading, spacing: 3) {
                                    Text(run.title)
                                        .font(AppTypography.bodySemibold)
                                        .foregroundStyle(AppColors.textPrimary)
                                    Text(run.subtitle)
                                        .font(AppTypography.caption1)
                                        .foregroundStyle(AppColors.textSecondary)
                                }

                                Spacer()
                            }
                        }
                    }
                }
            }
        }
    }

    private var runningHighlightsCard: some View {
        Card {
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
        }
    }

    private var runningPersonalBestCard: some View {
        Card {
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
        }
    }

    private var recentRunsCard: some View {
        Card {
            VStack(alignment: .leading, spacing: AppSpacing.md) {
                sectionEyebrow(title: "Recent Runs", subtitle: "Your latest sessions")

                if viewModel.dashboard.recentRuns.isEmpty {
                    VStack(spacing: AppSpacing.sm) {
                        Image(systemName: "figure.run.circle")
                            .font(.system(size: 34, weight: .light))
                            .foregroundStyle(AppColors.textTertiary)
                        Text("No runs yet")
                            .font(AppTypography.subheadlineSemibold)
                            .foregroundStyle(AppColors.textPrimary)
                        Text("Start your first run to begin building your route history, pacing trends, and weekly volume.")
                            .font(AppTypography.caption1)
                            .foregroundStyle(AppColors.textSecondary)
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
                        }
                    }
                }
            }
        }
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
                    showCrewView = true
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

                    KilometerProgressRing(distanceMeters: effectiveDistanceMeters)

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
#if DEBUG
                    activeInfoPill(title: "DIST", value: displayDistancePillText())
#else
                    activeInfoPill(title: "DIST", value: formatDistanceMeters(effectiveDistanceMeters))
#endif
                    activeInfoPill(title: "PAUSE", value: formatDurationSeconds(Int(viewModel.pauseDuration)))
                }

#if DEBUG
                testDistanceSimulationButton
#endif
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
                VStack(spacing: 6) {
                    Text(viewModel.currentTrack.title)
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                    Text(viewModel.jamStatusLabel)
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundStyle(Color.white.opacity(0.68))
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(Color.black.opacity(0.35), in: Capsule())
                .offset(y: -58)
            }
            .padding(.bottom, 24)
        }
        .allowsHitTesting(!isMapFocusMode)
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

            VStack(spacing: 18) {
                HStack {
                    Text(viewModel.finishedTitle)
                        .font(.system(size: 30, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)

                    Spacer()

                    if viewModel.completedRunCounts {
                        Button {
                            prepareShareImage()
                        } label: {
                            Circle()
                                .fill(Color.orange)
                                .frame(width: 44, height: 44)
                                .overlay {
                                    if isRenderingShareImage {
                                        ProgressView()
                                            .tint(.white)
                                            .scaleEffect(0.7)
                                    } else {
                                        Image(systemName: "square.and.arrow.up")
                                            .font(.system(size: 16, weight: .bold))
                                            .foregroundStyle(.white)
                                    }
                                }
                        }
                        .disabled(isRenderingShareImage)
                    }
                }
                .padding(.top, 16)

                Circle()
                    .stroke(Color.orange.opacity(0.85), lineWidth: 2)
                    .frame(width: 255, height: 255)
                    .overlay(
                        Circle()
                            .fill(Color.black.opacity(0.42))
                            .overlay(
                                VStack(spacing: 10) {
                                    Text(viewModel.formattedDistance)
                                        .font(.system(size: 44, weight: .bold, design: .rounded))
                                        .foregroundStyle(.white)
                                        .monospacedDigit()
                                        .lineLimit(1)
                                        .minimumScaleFactor(0.7)

                                    Text("TOTAL DISTANCE")
                                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                                        .foregroundStyle(Color.white.opacity(0.58))
                                        .tracking(1.6)
                                }
                            )
                    )

                HStack(spacing: 12) {
                    finishedStat(value: viewModel.formattedDuration, label: "TIME")
                    finishedStat(value: viewModel.formattedPace, label: "PACE")
                    finishedStat(value: "\(viewModel.finishedCaloriesBurned)", label: "CAL")
                }

                HStack(spacing: 10) {
                    Circle()
                        .fill((viewModel.completedRunCounts ? Color.orange : Color.white).opacity(0.18))
                        .frame(width: 42, height: 42)
                        .overlay(
                            Image(systemName: viewModel.completedRunCounts ? "clock.badge.checkmark" : "exclamationmark.circle")
                                .font(.system(size: 17, weight: .semibold))
                                .foregroundStyle(viewModel.completedRunCounts ? Color.orange : Color.white)
                        )

                    VStack(alignment: .leading, spacing: 4) {
                        Text(viewModel.completedRunCounts ? "SCREEN TIME EARNED" : "RUN STATUS")
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                            .foregroundStyle(Color.white.opacity(0.56))
                            .tracking(1)
                        Text(viewModel.completedRunCounts ? "+\(viewModel.earnedMinutes) min" : "Not saved")
                            .font(.system(size: 28, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                            .monospacedDigit()
                    }

                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(Color.black.opacity(0.35), in: RoundedRectangle(cornerRadius: 16))

                Text(viewModel.finishedSubtitle)
                    .font(AppTypography.body)
                    .foregroundStyle(Color.white.opacity(0.80))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 12)

                Spacer()

                HStack(spacing: 12) {
                    if viewModel.completedRunCounts {
                        Button {
                            prepareShareImage()
                        } label: {
                            Text("Share")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(.white)
                                .frame(maxWidth: .infinity)
                                .frame(height: 52)
                                .background(Color.black.opacity(0.35), in: RoundedRectangle(cornerRadius: 14))
                        }
                        .disabled(isRenderingShareImage)
                    }

                    Button {
                        dismiss()
                    } label: {
                        Text("Done")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 52)
                            .background(Color.orange, in: RoundedRectangle(cornerRadius: 14))
                    }
                }
                .padding(.bottom, 12)
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

    private func finishedStat(value: String, label: String) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.75)

            Text(label)
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .foregroundStyle(Color.white.opacity(0.56))
                .tracking(1)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(Color.black.opacity(0.35), in: RoundedRectangle(cornerRadius: 14))
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
                .foregroundStyle(AppColors.textPrimary)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            Text(label)
                .font(AppTypography.caption2)
                .foregroundStyle(AppColors.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, AppSpacing.sm)
        .background(
            LinearGradient(
                colors: [
                    AppColors.backgroundPrimary.opacity(0.92),
                    AppColors.backgroundPrimary.opacity(0.72)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        )
        .clipShape(RoundedRectangle(cornerRadius: AppSpacing.cornerRadiusChip))
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
                        .fill(AppColors.info.opacity(0.10))
                        .frame(width: 38, height: 38)

                    Image(systemName: icon)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(AppColors.info)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(AppTypography.bodySemibold)
                        .foregroundStyle(AppColors.textPrimary)
                    Text(subtitle)
                        .font(AppTypography.caption2)
                        .foregroundStyle(AppColors.textSecondary)
                }

                Spacer()
            }
            .padding(AppSpacing.md)
            .background(AppColors.backgroundPrimary.opacity(0.65), in: RoundedRectangle(cornerRadius: AppSpacing.cornerRadiusCard))
        }
        .buttonStyle(.plain)
    }

    private func sectionEyebrow(title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(AppTypography.headline)
                .foregroundStyle(AppColors.textPrimary)
            Text(subtitle)
                .font(AppTypography.caption1)
                .foregroundStyle(AppColors.textSecondary)
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
                    .foregroundStyle(AppColors.textPrimary)

                HStack(spacing: AppSpacing.xs) {
                    Text(formatDurationSeconds(run.durationSeconds))
                    Text("•")
                    Text("+\(run.earnedMinutes)m")
                }
                .font(AppTypography.caption2)
                .foregroundStyle(AppColors.textSecondary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 3) {
                Text(formatDistance(run.distanceMeters))
                    .font(AppTypography.bodySemibold)
                    .foregroundStyle(AppColors.textPrimary)

                HStack(spacing: 6) {
                    Text(formatPace(run.avgPaceSecondsPerKm))
                        .font(AppTypography.caption1)
                        .foregroundStyle(AppColors.textSecondary)

                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(AppColors.textTertiary)
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

    private var effectiveDistanceMeters: Double {
#if DEBUG
        simulatedDistanceMeters ?? viewModel.distanceMeters
#else
        viewModel.distanceMeters
#endif
    }

    private func formatDistanceMeters(_ m: Double) -> String {
        if m >= 1000 {
            return String(format: "%.2f km", m / 1000.0)
        }
        return String(format: "%.0f m", m)
    }

#if DEBUG
    /// DIST during simulation uses tenths of a meter so the value steps visibly with the timer; live GPS uses `formatDistanceMeters`.
    private func displayDistancePillText() -> String {
        if simulatedDistanceMeters != nil {
            let m = effectiveDistanceMeters
            if m >= 1000 {
                return String(format: "%.2f km", m / 1000.0)
            }
            return String(format: "%.1f m", m)
        }
        return formatDistanceMeters(effectiveDistanceMeters)
    }

    private var testDistanceSimulationButton: some View {
        Button {
            startSimulatedKilometerTest()
        } label: {
            Text("Test 1 km (10s)")
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.9))
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(Color.white.opacity(0.18), in: Capsule())
        }
        .buttonStyle(.plain)
    }

    private func startSimulatedKilometerTest() {
        distanceSimulationTask?.cancel()
        simulatedDistanceMeters = 0

        let duration: TimeInterval = 10
        let targetMeters = 999.99
        let stepCount = 200
        let stepNanos = UInt64((duration / Double(stepCount)) * 1_000_000_000)

        distanceSimulationTask = Task { @MainActor in
            for step in 0...stepCount {
                guard !Task.isCancelled else { return }
                let t = Double(step) / Double(stepCount)
                simulatedDistanceMeters = t * targetMeters
                if step < stepCount {
                    try? await Task.sleep(nanoseconds: stepNanos)
                }
            }
            guard !Task.isCancelled else { return }
            simulatedDistanceMeters = nil
        }
    }
#endif

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


    private var musicSheet: some View {
        NavigationStack {
            ZStack {
                LinearGradient(
                    colors: [
                        Color(red: 0.05, green: 0.08, blue: 0.06),
                        Color(red: 0.08, green: 0.12, blue: 0.09),
                        AppColors.backgroundPrimary
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()

                ScrollView(showsIndicators: false) {
                    VStack(spacing: AppSpacing.lg) {
                        spotifyHeroCard
                        spotifyPlaybackCard
                        spotifyModeStudioCard
                        spotifyJamCard
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
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { showMusicSheet = false }
                }
            }
        }
    }

    private var spotifyHeroCard: some View {
        VStack(alignment: .leading, spacing: AppSpacing.md) {
            HStack(alignment: .top, spacing: AppSpacing.md) {
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color(red: 0.13, green: 0.81, blue: 0.41),
                                    Color(red: 0.05, green: 0.42, blue: 0.18)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 64, height: 64)

                    Image(systemName: "waveform.circle.fill")
                        .font(.system(size: 28, weight: .bold))
                        .foregroundStyle(.white)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("Spotify Run Control")
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)

                    Text(viewModel.spotifyConnected
                         ? "Connected audio, live playback status, and run-jam controls in one surface."
                         : "Connect Spotify once and turn your running screen into a live audio cockpit.")
                        .font(AppTypography.callout)
                        .foregroundStyle(Color.white.opacity(0.72))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            HStack(spacing: AppSpacing.xs) {
                spotifyStatusChip(
                    title: viewModel.spotifyProviderStatusLabel,
                    icon: viewModel.spotifyConnected ? "checkmark.seal.fill" : "bolt.horizontal.circle.fill",
                    tint: viewModel.spotifyConnected ? AppColors.success : Color.white.opacity(0.9)
                )
                spotifyStatusChip(
                    title: viewModel.spotifyAppInstalled ? "App ready" : "Web handoff",
                    icon: viewModel.spotifyAppInstalled ? "iphone.gen3.circle.fill" : "safari.fill",
                    tint: viewModel.spotifyAppInstalled ? AppColors.info : Color.white.opacity(0.9)
                )
                if let tier = viewModel.spotifyProductTier {
                    spotifyStatusChip(
                        title: tier,
                        icon: "sparkles.rectangle.stack.fill",
                        tint: Color.white.opacity(0.92)
                    )
                }
            }

            HStack(spacing: AppSpacing.sm) {
                spotifyActionButton(
                    title: viewModel.spotifyConnectActionTitle,
                    subtitle: viewModel.spotifyConnected ? "Refresh your auth session" : "PKCE login with redirect",
                    icon: viewModel.spotifyConnected ? "arrow.clockwise.circle.fill" : "link.circle.fill",
                    prominent: true
                ) {
                    viewModel.connectSpotify()
                }

                spotifyActionButton(
                    title: viewModel.spotifySecondaryActionTitle,
                    subtitle: viewModel.spotifyConnected ? "Remove this device session" : "Open Spotify directly",
                    icon: viewModel.spotifyConnected ? "xmark.circle.fill" : "arrow.up.forward.app.fill",
                    prominent: false
                ) {
                    viewModel.handleSpotifySecondaryAction()
                }
            }

            if viewModel.spotifyConnected {
                HStack(spacing: AppSpacing.sm) {
                    spotifyMiniStat(
                        title: "Account",
                        value: viewModel.spotifyAccountName ?? "Spotify User",
                        icon: "person.crop.circle.fill"
                    )
                    spotifyMiniStat(
                        title: "Status",
                        value: viewModel.spotifyStatusDetail,
                        icon: "dot.radiowaves.left.and.right"
                    )
                }

                Button {
                    viewModel.refreshSpotifyDetails()
                } label: {
                    HStack(spacing: AppSpacing.xs) {
                        Image(systemName: "arrow.triangle.2.circlepath.circle.fill")
                            .font(.system(size: 16, weight: .semibold))
                        Text("Refresh Spotify Status")
                            .font(.system(size: 14, weight: .bold, design: .rounded))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(Color.white.opacity(0.12), in: Capsule())
                }
                .buttonStyle(.plain)
            } else {
                Text(viewModel.spotifyStatusDetail)
                    .font(AppTypography.caption1)
                    .foregroundStyle(Color.white.opacity(0.64))
            }
        }
        .padding(AppSpacing.lg)
        .background(
            LinearGradient(
                colors: [
                    Color(red: 0.10, green: 0.16, blue: 0.12),
                    Color(red: 0.06, green: 0.11, blue: 0.09)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .stroke(Color.white.opacity(0.10), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.22), radius: 18, y: 10)
    }

    private var spotifyPlaybackCard: some View {
        VStack(alignment: .leading, spacing: AppSpacing.md) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Now Playing")
                        .font(AppTypography.captionSemibold)
                        .foregroundStyle(AppColors.textSecondary)
                        .textCase(.uppercase)

                    Text(viewModel.currentTrack.title)
                        .font(.system(size: 30, weight: .bold, design: .rounded))
                        .foregroundStyle(AppColors.textPrimary)
                        .lineLimit(2)
                        .minimumScaleFactor(0.75)

                    Text(viewModel.currentTrack.artist)
                        .font(AppTypography.bodySemibold)
                        .foregroundStyle(AppColors.textSecondary)
                }

                Spacer()

                ZStack {
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [
                                    AppColors.secondary.opacity(0.92),
                                    Color(red: 0.93, green: 0.28, blue: 0.18)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 92, height: 92)

                    Image(systemName: "music.note.list")
                        .font(.system(size: 34, weight: .bold))
                        .foregroundStyle(.white)
                }
            }

            Text(viewModel.currentTrack.vibe.uppercased())
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .tracking(1.4)
                .foregroundStyle(AppColors.info)

            VStack(alignment: .leading, spacing: AppSpacing.xs) {
                Text(viewModel.spotifyPlaybackLabel)
                    .font(AppTypography.bodySemibold)
                    .foregroundStyle(AppColors.textPrimary)

                HStack(spacing: 6) {
                    ForEach(0..<18, id: \.self) { index in
                        Capsule()
                            .fill(index.isMultiple(of: 3) ? AppColors.success : AppColors.info.opacity(0.72))
                            .frame(width: 6, height: [14, 24, 18, 28, 12, 20][index % 6])
                    }
                }
            }

            HStack(spacing: AppSpacing.sm) {
                spotifySurfaceButton(
                    title: viewModel.musicPrimaryActionTitle,
                    icon: viewModel.spotifyConnected ? "play.circle.fill" : "link.badge.plus"
                ) {
                    if !viewModel.spotifyConnected {
                        viewModel.connectSpotify()
                    } else if viewModel.jamActive {
                        viewModel.isCurrentUserInJam ? viewModel.leaveJam() : viewModel.joinJam()
                    } else if viewModel.selectedLiveRunSessionId != nil {
                        viewModel.startJam()
                    } else {
                        viewModel.nextTrack()
                    }
                }

                spotifySurfaceButton(
                    title: "Next Track",
                    icon: "forward.end.fill"
                ) {
                    viewModel.nextTrack()
                }
            }
        }
        .padding(AppSpacing.lg)
        .background(AppColors.backgroundSecondary.opacity(0.96), in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .stroke(Color.white.opacity(0.34), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.08), radius: 16, y: 8)
    }

    private var spotifyModeStudioCard: some View {
        VStack(alignment: .leading, spacing: AppSpacing.md) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Run Mode")
                        .font(AppTypography.headline)
                        .foregroundStyle(AppColors.textPrimary)
                    Text("Pick the audio mood you want the next handoff to open.")
                        .font(AppTypography.caption1)
                        .foregroundStyle(AppColors.textSecondary)
                }

                Spacer()

                Button {
                    viewModel.cycleAudioMode()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "shuffle")
                            .font(.system(size: 14, weight: .bold))
                        Text("Cycle")
                            .font(.system(size: 12, weight: .bold, design: .rounded))
                    }
                    .foregroundStyle(AppColors.textPrimary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(AppColors.fill, in: Capsule())
                }
                .buttonStyle(.plain)
            }

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: AppSpacing.sm) {
                ForEach(RunAudioMode.allCases) { mode in
                    Button {
                        viewModel.selectedAudioMode = mode
                    } label: {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Image(systemName: spotifyIcon(for: mode))
                                    .font(.system(size: 15, weight: .bold))
                                Spacer()
                                if viewModel.selectedAudioMode == mode {
                                    Image(systemName: "checkmark.circle.fill")
                                        .font(.system(size: 16, weight: .bold))
                                }
                            }
                            .foregroundStyle(viewModel.selectedAudioMode == mode ? .white : AppColors.textPrimary)

                            Text(mode.rawValue)
                                .font(.system(size: 18, weight: .bold, design: .rounded))
                                .foregroundStyle(viewModel.selectedAudioMode == mode ? .white : AppColors.textPrimary)

                            Text(spotifyModeSubtitle(for: mode))
                                .font(AppTypography.caption1)
                                .foregroundStyle(viewModel.selectedAudioMode == mode ? Color.white.opacity(0.74) : AppColors.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .frame(maxWidth: .infinity, minHeight: 108, alignment: .leading)
                        .padding(AppSpacing.md)
                        .background(
                            Group {
                                if viewModel.selectedAudioMode == mode {
                                    LinearGradient(
                                        colors: [
                                            Color(red: 0.13, green: 0.81, blue: 0.41),
                                            Color(red: 0.06, green: 0.46, blue: 0.19)
                                        ],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                } else {
                                    LinearGradient(
                                        colors: [
                                            AppColors.backgroundSecondary,
                                            AppColors.backgroundSecondary.opacity(0.86)
                                        ],
                                        startPoint: .top,
                                        endPoint: .bottom
                                    )
                                }
                            }
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 22, style: .continuous)
                                .stroke(viewModel.selectedAudioMode == mode ? Color.clear : AppColors.separator.opacity(0.25), lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(AppSpacing.lg)
        .background(AppColors.backgroundSecondary.opacity(0.96), in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .stroke(Color.white.opacity(0.34), lineWidth: 1)
        )
    }

    private var spotifyJamCard: some View {
        VStack(alignment: .leading, spacing: AppSpacing.md) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Run Jam")
                        .font(AppTypography.headline)
                        .foregroundStyle(AppColors.textPrimary)
                    Text(viewModel.jamStatusLabel)
                        .font(AppTypography.bodySemibold)
                        .foregroundStyle(AppColors.textPrimary)
                }

                Spacer()

                ZStack {
                    Circle()
                        .fill(AppColors.secondary.opacity(0.12))
                        .frame(width: 44, height: 44)

                    Image(systemName: viewModel.jamActive ? "person.2.wave.2.fill" : "speaker.wave.3.fill")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(AppColors.secondary)
                }
            }

            Text(viewModel.jamActive
                 ? "Hosted by \(viewModel.jamHostDisplayName). Everyone can move on the same soundtrack while the session stays live."
                 : "Start a jam when the run turns social. Crew members can join the same soundtrack without leaving the workout flow.")
                .font(AppTypography.caption1)
                .foregroundStyle(AppColors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: AppSpacing.sm) {
                spotifyMiniStat(
                    title: "Listeners",
                    value: "\(viewModel.jamListenerCount)",
                    icon: "person.2.fill"
                )
                spotifyMiniStat(
                    title: "Host",
                    value: viewModel.jamActive ? viewModel.jamHostDisplayName : "Not live",
                    icon: "dot.radiowaves.up.forward"
                )
            }
        }
        .padding(AppSpacing.lg)
        .background(AppColors.backgroundSecondary.opacity(0.96), in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .stroke(Color.white.opacity(0.34), lineWidth: 1)
        )
    }

    private func spotifyStatusChip(title: String, icon: String, tint: Color) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .bold))
            Text(title)
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .tracking(0.8)
                .lineLimit(1)
        }
        .foregroundStyle(tint)
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(Color.white.opacity(0.10), in: Capsule())
    }

    private func spotifyActionButton(
        title: String,
        subtitle: String,
        icon: String,
        prominent: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: icon)
                        .font(.system(size: 16, weight: .bold))
                    Spacer()
                    Image(systemName: "arrow.right")
                        .font(.system(size: 12, weight: .bold))
                }
                .foregroundStyle(prominent ? Color(red: 0.06, green: 0.13, blue: 0.08) : .white)

                Text(title)
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundStyle(prominent ? Color(red: 0.06, green: 0.13, blue: 0.08) : .white)

                Text(subtitle)
                    .font(AppTypography.caption1)
                    .foregroundStyle(prominent ? Color(red: 0.06, green: 0.13, blue: 0.08).opacity(0.72) : Color.white.opacity(0.72))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, minHeight: 112, alignment: .leading)
            .padding(AppSpacing.md)
            .background(
                Group {
                    if prominent {
                        LinearGradient(
                            colors: [
                                Color(red: 0.17, green: 0.92, blue: 0.46),
                                Color(red: 0.10, green: 0.74, blue: 0.34)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    } else {
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.16),
                                Color.white.opacity(0.08)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    }
                }
            )
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private func spotifyMiniStat(title: String, value: String, icon: String) -> some View {
        HStack(spacing: AppSpacing.sm) {
            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(AppColors.fill.opacity(0.9))
                    .frame(width: 42, height: 42)

                Image(systemName: icon)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(AppColors.secondary)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .tracking(1)
                    .foregroundStyle(AppColors.textSecondary)
                Text(value)
                    .font(AppTypography.bodySemibold)
                    .foregroundStyle(AppColors.textPrimary)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
            }

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(AppSpacing.sm)
        .background(AppColors.backgroundPrimary.opacity(0.72), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private func spotifySurfaceButton(title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .bold))
                Text(title)
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .foregroundStyle(AppColors.textPrimary)
            .padding(.vertical, 14)
            .background(AppColors.fill, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private func spotifyIcon(for mode: RunAudioMode) -> String {
        switch mode {
        case .base: return "figure.run"
        case .tempo: return "metronome.fill"
        case .longRun: return "road.lanes"
        case .race: return "bolt.fill"
        case .recovery: return "wind"
        }
    }

    private func spotifyModeSubtitle(for mode: RunAudioMode) -> String {
        switch mode {
        case .base: return "Balanced picks for everyday runs and warm starts."
        case .tempo: return "Higher energy handoff for pace work and fast efforts."
        case .longRun: return "Stable energy for long aerobic blocks and long Sundays."
        case .race: return "Aggressive handoff when the run needs sharp intent."
        case .recovery: return "Soft landing after hard intervals or cooldown blocks."
        }
    }


    private func summaryRow(icon: String, label: String, value: String) -> some View {
        HStack {
            Image(systemName: icon)
                .font(.system(size: 18))
                .foregroundStyle(AppColors.info)
                .frame(width: 28)

            Text(label)
                .font(AppTypography.body)
                .foregroundStyle(AppColors.textSecondary)

            Spacer()

            Text(value)
                .font(AppTypography.bodySemibold)
                .foregroundStyle(AppColors.textPrimary)
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
                .foregroundStyle(AppColors.textPrimary)
            Text(subtitle)
                .font(AppTypography.caption1)
                .foregroundStyle(AppColors.textSecondary)
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

// MARK: - Previews

#if DEBUG
#Preview("Jogging View") {
    JoggingView()
}
#endif
