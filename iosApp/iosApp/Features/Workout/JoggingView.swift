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
    @State private var showParticipantsSheet = false
    @State private var isMapFocusMode = false
    @State private var shareImage: UIImage?
    @State private var isRenderingShareImage = false

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
        .sheet(isPresented: $showParticipantsSheet) {
            runParticipantsSheet
        }
    }

    // MARK: - Idle View

    private var idleView: some View {
        ScrollView {
            VStack(spacing: AppSpacing.md) {
                // Back button
                HStack {
                    Button {
                        dismiss()
                    } label: {
                        HStack(spacing: AppSpacing.xs) {
                            Image(systemName: "chevron.left")
                                .font(.system(size: 16, weight: .semibold))
                            Text("Back")
                                .font(AppTypography.bodySemibold)
                        }
                        .foregroundStyle(AppColors.textSecondary)
                        .padding(.horizontal, AppSpacing.md)
                        .padding(.vertical, AppSpacing.sm)
                        .background(.ultraThinMaterial, in: Capsule())
                    }
                    Spacer()
                }
                .padding(.top, AppSpacing.md)

                // Hero
                Card {
                    VStack(spacing: AppSpacing.sm) {
                        ZStack {
                            Circle()
                                .fill(
                                    LinearGradient(
                                        colors: [AppColors.info, AppColors.info.opacity(0.7)],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                                .frame(width: 90, height: 90)

                            Image(icon: .figureRun)
                                .font(.system(size: 44, weight: .semibold))
                                .foregroundStyle(.white)
                                .symbolRenderingMode(.hierarchical)
                        }

                        Text("Running Dashboard")
                            .font(AppTypography.title3)
                            .foregroundStyle(AppColors.textPrimary)

                        Text("Track your route, progress, and pace. Earn 1 min per km.")
                            .font(AppTypography.subheadline)
                            .foregroundStyle(AppColors.textSecondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                }

                runningHighlightsCard
                runningPersonalBestCard
                recentRunsCard

                if !viewModel.hasLocationPermission {
                    VStack(spacing: AppSpacing.md) {
                        HStack(spacing: AppSpacing.sm) {
                            Image(systemName: "location.fill")
                                .foregroundStyle(AppColors.warning)
                            Text("Location access required")
                                .font(AppTypography.subheadlineSemibold)
                                .foregroundStyle(AppColors.textPrimary)
                        }

                        Button {
                            viewModel.requestLocationPermission()
                        } label: {
                            Text("Grant Location Access")
                                .font(AppTypography.bodySemibold)
                                .foregroundStyle(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, AppSpacing.md)
                                .background(AppColors.info, in: RoundedRectangle(cornerRadius: AppSpacing.cornerRadiusButton))
                        }
                    }
                    .padding(AppSpacing.md)
                    .background(AppColors.backgroundSecondary)
                    .clipShape(RoundedRectangle(cornerRadius: AppSpacing.cornerRadiusCard))
                }

                Button {
                    viewModel.startWorkout()
                } label: {
                    HStack(spacing: AppSpacing.sm) {
                        Image(systemName: "play.fill")
                            .font(.system(size: 20))
                        Text("Start Run")
                            .font(AppTypography.title3)
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, AppSpacing.lg)
                    .background(
                        LinearGradient(
                            colors: [AppColors.info, AppColors.info.opacity(0.8)],
                            startPoint: .leading,
                            endPoint: .trailing
                        ),
                        in: RoundedRectangle(cornerRadius: AppSpacing.cornerRadiusButton)
                    )
                    .shadow(color: AppColors.info.opacity(0.4), radius: 12, x: 0, y: 6)
                }
                .disabled(!viewModel.hasLocationPermission)
                .opacity(viewModel.hasLocationPermission ? 1 : 0.6)
                .padding(.top, AppSpacing.xs)
            }
            .padding(.horizontal, AppSpacing.screenHorizontal)
            .padding(.bottom, AppSpacing.screenVerticalBottom)
        }
    }

    private var runningHighlightsCard: some View {
        Card {
            VStack(alignment: .leading, spacing: AppSpacing.sm) {
                Label("This Week", icon: .chartBar)
                    .font(AppTypography.headline)
                    .foregroundStyle(AppColors.textPrimary)

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
            VStack(alignment: .leading, spacing: AppSpacing.sm) {
                Label("Personal Best", icon: .starFill)
                    .font(AppTypography.headline)
                    .foregroundStyle(AppColors.textPrimary)

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
            VStack(alignment: .leading, spacing: AppSpacing.sm) {
                Label("Recent Runs", icon: .clockArrowCirclepath)
                    .font(AppTypography.headline)
                    .foregroundStyle(AppColors.textPrimary)

                if viewModel.dashboard.recentRuns.isEmpty {
                    Text("No runs yet. Start your first run to build your progress.")
                        .font(AppTypography.caption1)
                        .foregroundStyle(AppColors.textSecondary)
                } else {
                    ForEach(viewModel.dashboard.recentRuns) { run in
                        HStack(spacing: AppSpacing.sm) {
                            VStack(alignment: .leading, spacing: AppSpacing.xxs) {
                                Text(Self.shortDateFormatter.string(from: run.date))
                                    .font(AppTypography.captionSemibold)
                                    .foregroundStyle(AppColors.textPrimary)
                                Text(formatDurationSeconds(run.durationSeconds))
                                    .font(AppTypography.caption2)
                                    .foregroundStyle(AppColors.textSecondary)
                            }

                            Spacer()

                            Text(formatDistance(run.distanceMeters))
                                .font(AppTypography.bodySemibold)
                                .foregroundStyle(AppColors.textPrimary)

                            Text(formatPace(run.avgPaceSecondsPerKm))
                                .font(AppTypography.caption1)
                                .foregroundStyle(AppColors.textSecondary)
                        }
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
        ZStack {
            routeMapView
                .ignoresSafeArea()

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

            if !isMapFocusMode {
                activeTrackDecoration
                    .ignoresSafeArea()
            }

            VStack(spacing: 0) {
                if !isMapFocusMode {
                    ZStack(alignment: .topTrailing) {
                        HStack(alignment: .firstTextBaseline) {
                            Text(speedValueDisplay)
                                .font(.system(size: 62, weight: .bold, design: .rounded))
                                .foregroundStyle(.white)
                                .monospacedDigit()
                                .lineLimit(1)
                                .minimumScaleFactor(0.7)

                            Spacer(minLength: 8)

                            Text("KM/H")
                                .font(.system(size: 12, weight: .semibold, design: .rounded))
                                .foregroundStyle(Color.white.opacity(0.7))
                                .tracking(1)
                        }

                        Button {
                            showParticipantsSheet = true
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
                        if viewModel.isPaused {
                            Text("PAUSED")
                                .font(.system(size: 12, weight: .bold, design: .rounded))
                                .foregroundStyle(Color.orange)
                                .tracking(2)
                                .padding(.top, 78)
                        }
                    }
                } else {
                    Spacer().frame(height: 24)
                }

                Spacer()

                if !isMapFocusMode {
                    VStack(spacing: 14) {
                        Circle()
                            .stroke(Color.orange.opacity(0.8), lineWidth: 2)
                            .frame(width: 255, height: 255)
                            .overlay(
                                Circle()
                                    .fill(Color.black.opacity(0.45))
                                    .overlay(
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
                                    )
                            )

                        HStack(spacing: 18) {
                            activeInfoPill(title: "DIST", value: viewModel.formattedDistance)
                            activeInfoPill(title: "PAUSE", value: formatDurationSeconds(Int(viewModel.pauseDuration)))
                        }
                    }
                }

                Spacer()

                if !isMapFocusMode {
                    HStack(spacing: 18) {
                        Button {
                            openMusicApp()
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
                    .padding(.bottom, 24)
                } else {
                    Spacer().frame(height: 34)
                }
            }

            mapFocusToggleButton
        }
    }

    private var mapFocusToggleButton: some View {
        VStack {
            Spacer()
            HStack {
                Spacer()
                Button {
                    withAnimation(.spring(duration: 0.35)) {
                        isMapFocusMode.toggle()
                    }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 13, weight: .bold))
                        Text(isMapFocusMode ? "Stats" : "Map")
                            .font(.system(size: 12, weight: .bold, design: .rounded))
                    }
                    .foregroundStyle(.white)
                    .padding(.leading, 14)
                    .padding(.trailing, 12)
                    .padding(.vertical, 12)
                    .background(Color.black.opacity(0.45), in: Capsule())
                    .overlay(
                        Capsule()
                            .stroke(Color.white.opacity(0.10), lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
                // Make it look like it comes from the edge
                .offset(x: 24, y: -22)
            }
        }
    }

    // MARK: - Route Map

    private var routeMapView: some View {
        Map {
            // Route polyline
            if viewModel.routeLocations.count >= 2 {
                MapPolyline(
                    coordinates: viewModel.routeLocations.map { $0.coordinate }
                )
                .stroke(AppColors.info, lineWidth: 4)
            }

            // Current position marker
            if let current = viewModel.routeLocations.last {
                Annotation("", coordinate: current.coordinate) {
                    ZStack {
                        Circle()
                            .fill(AppColors.info)
                            .frame(width: 16, height: 16)
                        Circle()
                            .fill(.white)
                            .frame(width: 8, height: 8)
                    }
                    .shadow(color: AppColors.info.opacity(0.5), radius: 6)
                }
            }
        }
        .mapStyle(.standard(elevation: .flat))
        .mapControlVisibility(.hidden)
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

            activeTrackDecoration
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

        let coordinates = viewModel.routeLocations.map { $0.coordinate }
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
                .foregroundStyle(AppColors.info)

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
        .background(AppColors.backgroundPrimary.opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: AppSpacing.cornerRadiusChip))
    }

    private var speedValueDisplay: String {
        String(format: "%.2f", viewModel.currentSpeed * 3.6)
    }

    private var paceValueDisplay: String {
        guard let pace = viewModel.currentPaceSecondsPerKm, pace > 0 else { return "--.--" }
        let paceMinutes = Double(pace) / 60.0
        return String(format: "%.2f", paceMinutes)
    }

    private var activeTrackDecoration: some View {
        GeometryReader { proxy in
            Path { path in
                let w = proxy.size.width
                let h = proxy.size.height
                path.move(to: CGPoint(x: w * 0.04, y: h * 0.52))
                path.addCurve(
                    to: CGPoint(x: w * 0.92, y: h * 0.61),
                    control1: CGPoint(x: w * 0.22, y: h * 0.42),
                    control2: CGPoint(x: w * 0.68, y: h * 0.77)
                )
                path.addCurve(
                    to: CGPoint(x: w * 0.60, y: h * 0.96),
                    control1: CGPoint(x: w * 1.05, y: h * 0.44),
                    control2: CGPoint(x: w * 0.78, y: h * 0.90)
                )
            }
            .stroke(
                Color.orange,
                style: StrokeStyle(lineWidth: 8, lineCap: .round, lineJoin: .round)
            )

            Circle()
                .fill(Color.green)
                .frame(width: 20, height: 20)
                .position(x: proxy.size.width * 0.61, y: proxy.size.height * 0.96)
        }
        .allowsHitTesting(false)
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

    private var runParticipantsSheet: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if viewModel.isLoadingRunSocialData {
                    Spacer()
                    ProgressView("Loading runners...")
                    Spacer()
                } else {
                    List {
                        Section("Who’s running") {
                            if viewModel.runParticipants.isEmpty {
                                Text("No one has joined this run yet.")
                                    .foregroundStyle(AppColors.textSecondary)
                            } else {
                                ForEach(viewModel.runParticipants) { participant in
                                    participantRow(participant)
                                }
                            }
                        }

                        Section("Invite friends") {
                            if viewModel.inviteableFriends.isEmpty {
                                Text("No friends available to invite.")
                                    .foregroundStyle(AppColors.textSecondary)
                            } else {
                                ForEach(viewModel.inviteableFriends) { friend in
                                    HStack(spacing: 12) {
                                        participantAvatar(initials: friend.initials)

                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(friend.displayName)
                                                .font(AppTypography.bodySemibold)
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
                                            Text("Invite")
                                                .font(AppTypography.captionSemibold)
                                                .foregroundStyle(.white)
                                                .padding(.horizontal, 12)
                                                .padding(.vertical, 6)
                                                .background(Color.orange, in: Capsule())
                                        }
                                        .buttonStyle(.plain)
                                    }
                                    .padding(.vertical, 2)
                                }
                            }
                        }
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .navigationTitle("Run group")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { showParticipantsSheet = false }
                }
            }
            .task {
                await viewModel.loadRunSocialData()
            }
        }
    }

    private func participantRow(_ participant: RunParticipant) -> some View {
        HStack(spacing: 12) {
            participantAvatar(initials: participant.initials)

            VStack(alignment: .leading, spacing: 2) {
                Text(participant.displayName)
                    .font(AppTypography.bodySemibold)
                if let username = participant.username {
                    Text("@\(username)")
                        .font(AppTypography.caption1)
                        .foregroundStyle(AppColors.textSecondary)
                }
            }

            Spacer()

            Text(participant.status == .running ? "Running" : "Invited")
                .font(AppTypography.captionSemibold)
                .foregroundStyle(participant.status == .running ? AppColors.success : AppColors.warning)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(
                    (participant.status == .running ? AppColors.success : AppColors.warning).opacity(0.14),
                    in: Capsule()
                )
        }
        .padding(.vertical, 2)
    }

    private func participantAvatar(initials: String) -> some View {
        Circle()
            .fill(Color.orange.opacity(0.18))
            .frame(width: 34, height: 34)
            .overlay(
                Text(initials)
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.orange)
            )
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
