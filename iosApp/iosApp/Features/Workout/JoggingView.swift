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
        VStack(spacing: AppSpacing.xl) {
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
            .padding(.horizontal, AppSpacing.screenHorizontal)
            .padding(.top, AppSpacing.md)

            Spacer()

            // Icon
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [AppColors.info, AppColors.info.opacity(0.7)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 120, height: 120)

                Image(icon: .figureRun)
                    .font(.system(size: 56, weight: .semibold))
                    .foregroundStyle(.white)
                    .symbolRenderingMode(.hierarchical)
            }

            VStack(spacing: AppSpacing.sm) {
                Text("Ready to Run?")
                    .font(AppTypography.title1)
                    .foregroundStyle(AppColors.textPrimary)

                Text("Track your route, distance, and pace.\nEarn 1 min screen time per km.")
                    .font(AppTypography.subheadline)
                    .foregroundStyle(AppColors.textSecondary)
                    .multilineTextAlignment(.center)
            }

            Spacer()

            if !viewModel.hasLocationPermission {
                // Permission request
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
                .padding(.horizontal, AppSpacing.xl)
            } else {
                // Start button
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
                .padding(.horizontal, AppSpacing.xl)
            }

            Spacer()
                .frame(height: AppSpacing.xl)
        }
    }

    // MARK: - Active View

    private var activeView: some View {
        VStack(spacing: 0) {
            // Route map (top half)
            routeMapView
                .frame(maxHeight: .infinity)

            // Stats panel (bottom half)
            VStack(spacing: AppSpacing.md) {
                // Primary stat: Distance
                VStack(spacing: AppSpacing.xxs) {
                    Text(viewModel.formattedDistance)
                        .font(.system(size: 48, weight: .bold, design: .rounded))
                        .foregroundStyle(AppColors.textPrimary)
                        .monospacedDigit()

                    Text("Distance")
                        .font(AppTypography.caption1)
                        .foregroundStyle(AppColors.textSecondary)
                }
                .padding(.top, AppSpacing.md)

                // Secondary stats grid
                HStack(spacing: AppSpacing.md) {
                    statItem(value: viewModel.formattedDuration, label: "Duration", icon: "clock")
                    statItem(value: viewModel.formattedPace, label: "Pace", icon: "speedometer")
                    statItem(value: viewModel.formattedSpeed, label: "Speed", icon: "gauge.with.dots.needle.33percent")
                }
                .padding(.horizontal, AppSpacing.md)

                // Calories
                HStack(spacing: AppSpacing.xs) {
                    Image(systemName: "flame.fill")
                        .foregroundStyle(AppColors.warning)
                    Text("\(viewModel.caloriesBurned) cal")
                        .font(AppTypography.subheadlineSemibold)
                        .foregroundStyle(AppColors.textPrimary)
                }

                // Stop button
                Button {
                    viewModel.requestStop()
                } label: {
                    HStack(spacing: AppSpacing.sm) {
                        Image(systemName: "stop.fill")
                            .font(.system(size: 16))
                        Text("End Run")
                            .font(AppTypography.bodySemibold)
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, AppSpacing.md)
                    .background(AppColors.error, in: RoundedRectangle(cornerRadius: AppSpacing.cornerRadiusButton))
                }
                .padding(.horizontal, AppSpacing.xl)
                .padding(.bottom, AppSpacing.lg)
            }
            .background(AppColors.backgroundSecondary)
            .clipShape(
                UnevenRoundedRectangle(
                    topLeadingRadius: AppSpacing.cornerRadiusCard,
                    topTrailingRadius: AppSpacing.cornerRadiusCard
                )
            )
            .shadow(color: Color.black.opacity(0.1), radius: 10, x: 0, y: -4)
        }
        .ignoresSafeArea(edges: .top)
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
}

// MARK: - Previews

#if DEBUG
#Preview("Jogging View") {
    JoggingView()
}
#endif
