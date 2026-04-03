import SwiftUI
import MapKit

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
        .alert("End Run?", isPresented: $showStopConfirmation) {
            Button("Keep Running", role: .cancel) {
                viewModel.cancelStop()
            }
            Button("End Run", role: .destructive) {
                viewModel.confirmStop()
            }
        } message: {
            Text("Are you sure you want to end your run?")
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
    }

    // MARK: - Idle View

    private var idleView: some View {
        ScrollView {
            VStack(spacing: AppSpacing.md) {
                idleTopBar
                    .padding(.top, AppSpacing.md)

                runningHubHero
                runLaunchCard
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
                        recentRunRow(run)
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
                    Text("Run Complete")
                        .font(.system(size: 30, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)

                    Spacer()

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
                    finishedStat(value: "\(viewModel.caloriesBurned)", label: "CAL")
                }

                HStack(spacing: 10) {
                    Circle()
                        .fill(Color.orange.opacity(0.18))
                        .frame(width: 42, height: 42)
                        .overlay(
                            Image(systemName: "clock.badge.checkmark")
                                .font(.system(size: 17, weight: .semibold))
                                .foregroundStyle(Color.orange)
                        )

                    VStack(alignment: .leading, spacing: 4) {
                        Text("SCREEN TIME EARNED")
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                            .foregroundStyle(Color.white.opacity(0.56))
                            .tracking(1)
                        Text("+\(viewModel.earnedMinutes) min")
                            .font(.system(size: 28, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                            .monospacedDigit()
                    }

                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(Color.black.opacity(0.35), in: RoundedRectangle(cornerRadius: 16))

                Spacer()

                HStack(spacing: 12) {
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

                Text(formatPace(run.avgPaceSecondsPerKm))
                    .font(AppTypography.caption1)
                    .foregroundStyle(AppColors.textSecondary)
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
            List {
                Section("Provider") {
                    HStack {
                        Label("Spotify", systemImage: "waveform")
                            .font(AppTypography.bodySemibold)
                        Spacer()
                        Text(viewModel.spotifyProviderStatusLabel)
                            .font(AppTypography.captionSemibold)
                            .foregroundStyle(viewModel.spotifyConnected ? AppColors.success : AppColors.textSecondary)
                    }

                    Button(viewModel.spotifyConnectActionTitle) {
                        viewModel.connectSpotify()
                    }
                }

                Section("Run mode") {
                    Picker("Mode", selection: $viewModel.selectedAudioMode) {
                        ForEach(RunAudioMode.allCases) { mode in
                            Text(mode.rawValue).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)

                    Button("Cycle Mode Preset") {
                        viewModel.cycleAudioMode()
                    }
                }

                Section("Now playing") {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(viewModel.currentTrack.title)
                            .font(AppTypography.bodySemibold)
                        Text(viewModel.currentTrack.artist)
                            .font(AppTypography.caption1)
                            .foregroundStyle(AppColors.textSecondary)
                        Text(viewModel.currentTrack.vibe)
                            .font(AppTypography.captionSemibold)
                            .foregroundStyle(AppColors.info)
                    }

                    HStack(spacing: 12) {
                        Button(viewModel.musicPrimaryActionTitle) {
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

                        Button("Next Track") {
                            viewModel.nextTrack()
                        }
                    }
                }

                Section("Run jam") {
                    Text(viewModel.jamStatusLabel)
                        .font(AppTypography.bodySemibold)
                    if viewModel.jamActive {
                        Text("Hosted by \(viewModel.jamHostDisplayName)")
                            .font(AppTypography.caption1)
                            .foregroundStyle(AppColors.textSecondary)
                    } else {
                        Text("Start a jam when you want the crew to move on the same soundtrack.")
                            .font(AppTypography.caption1)
                            .foregroundStyle(AppColors.textSecondary)
                    }
                }
            }
            .navigationTitle("Run Audio")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { showMusicSheet = false }
                }
            }
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
}

// MARK: - Previews

#if DEBUG
#Preview("Jogging View") {
    JoggingView()
}
#endif
