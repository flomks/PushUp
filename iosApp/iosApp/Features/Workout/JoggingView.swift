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
    @State private var showStopConfirmation = false
    @State private var showShareSheet = false
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

            activeTrackDecoration
                .ignoresSafeArea()

            VStack(spacing: 0) {
                HStack {
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
                .padding(.horizontal, AppSpacing.screenHorizontal)
                .padding(.top, 24)

                Spacer()

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
                        activeInfoPill(title: "CAL", value: "\(viewModel.caloriesBurned)")
                    }
                }

                Spacer()

                HStack(spacing: 18) {
                    Circle()
                        .fill(Color.black.opacity(0.35))
                        .frame(width: 44, height: 44)
                        .overlay(
                            Image(systemName: "music.note")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(Color.white.opacity(0.85))
                        )

                    Button {
                        viewModel.requestStop()
                    } label: {
                        Circle()
                            .fill(Color.orange)
                            .frame(width: 82, height: 82)
                            .overlay(
                                Image(systemName: "stop.fill")
                                    .font(.system(size: 28, weight: .bold))
                                    .foregroundStyle(.white)
                            )
                    }

                    Circle()
                        .fill(Color.black.opacity(0.35))
                        .frame(width: 44, height: 44)
                        .overlay(
                            Image(systemName: "xmark")
                                .font(.system(size: 15, weight: .bold))
                                .foregroundStyle(Color.white.opacity(0.85))
                        )
                }
                .padding(.bottom, 24)
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
        ScrollView {
            VStack(spacing: 0) {
                // Top bar: title + share icon
                HStack {
                    Text("Run Complete")
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .foregroundStyle(AppColors.textPrimary)

                    Spacer()

                    // Share button (top-right icon)
                    Button {
                        prepareShareImage()
                    } label: {
                        ZStack {
                            Circle()
                                .fill(AppColors.backgroundSecondary)
                                .frame(width: 40, height: 40)

                            if isRenderingShareImage {
                                ProgressView()
                                    .scaleEffect(0.7)
                            } else {
                                Image(systemName: "square.and.arrow.up")
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundStyle(AppColors.textPrimary)
                            }
                        }
                    }
                    .disabled(isRenderingShareImage)
                }
                .padding(.horizontal, AppSpacing.screenHorizontal)
                .padding(.top, AppSpacing.lg)
                .padding(.bottom, AppSpacing.md)

                // Hero distance
                VStack(spacing: 4) {
                    Text(viewModel.formattedDistance)
                        .font(.system(size: 56, weight: .heavy, design: .rounded))
                        .foregroundStyle(AppColors.textPrimary)
                        .monospacedDigit()

                    Text("total distance")
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundStyle(AppColors.textTertiary)
                        .textCase(.uppercase)
                        .tracking(1)
                }
                .padding(.bottom, AppSpacing.lg)

                // Stats row
                HStack(spacing: 0) {
                    finishedStat(value: viewModel.formattedDuration, label: "Duration")
                    finishedDivider
                    finishedStat(value: viewModel.formattedPace, label: "Avg Pace")
                    finishedDivider
                    finishedStat(value: "\(viewModel.caloriesBurned)", label: "Calories")
                }
                .padding(.vertical, AppSpacing.md)
                .background(AppColors.backgroundSecondary)
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .padding(.horizontal, AppSpacing.screenHorizontal)

                // Earned screen time card
                HStack(spacing: 10) {
                    ZStack {
                        Circle()
                            .fill(AppColors.success.opacity(0.15))
                            .frame(width: 40, height: 40)
                        Image(systemName: "clock.badge.checkmark")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(AppColors.success)
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Screen Time Earned")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(AppColors.textTertiary)
                        Text("+\(viewModel.earnedMinutes) min")
                            .font(.system(size: 22, weight: .bold, design: .rounded))
                            .foregroundStyle(AppColors.success)
                    }

                    Spacer()
                }
                .padding(AppSpacing.md)
                .background(AppColors.backgroundSecondary)
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .padding(.horizontal, AppSpacing.screenHorizontal)
                .padding(.top, AppSpacing.sm)

                Spacer(minLength: AppSpacing.xl)

                // Done button
                Button {
                    dismiss()
                } label: {
                    Text("Done")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                        .background(AppColors.primary, in: RoundedRectangle(cornerRadius: 14))
                }
                .padding(.horizontal, AppSpacing.screenHorizontal)
                .padding(.bottom, AppSpacing.xl)
            }
        }
        .sheet(isPresented: $showShareSheet) {
            if let image = shareImage {
                ShareSheet(items: [image])
            }
        }
    }

    // MARK: - Finished View Helpers

    private func finishedStat(value: String, label: String) -> some View {
        VStack(spacing: 3) {
            Text(value)
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundStyle(AppColors.textPrimary)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Text(label.uppercased())
                .font(.system(size: 9, weight: .bold, design: .rounded))
                .foregroundStyle(AppColors.textTertiary)
                .tracking(0.5)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 4)
    }

    private var finishedDivider: some View {
        Rectangle()
            .fill(AppColors.separator.opacity(0.3))
            .frame(width: 1, height: 30)
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
