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
        VStack(spacing: AppSpacing.xl) {
            Spacer()

            // Celebration
            VStack(spacing: AppSpacing.md) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 72))
                    .foregroundStyle(AppColors.success)

                Text("Run Complete!")
                    .font(AppTypography.title1)
                    .foregroundStyle(AppColors.textPrimary)
            }

            // Stats summary
            VStack(spacing: AppSpacing.md) {
                summaryRow(icon: "figure.run", label: "Distance", value: viewModel.formattedDistance)
                summaryRow(icon: "clock", label: "Duration", value: viewModel.formattedDuration)
                summaryRow(icon: "speedometer", label: "Avg Pace", value: viewModel.formattedPace)
                summaryRow(icon: "flame.fill", label: "Calories", value: "\(viewModel.caloriesBurned) cal")

                Divider()
                    .padding(.vertical, AppSpacing.xs)

                // Earned time
                HStack {
                    Image(icon: .clockBadgeCheckmark)
                        .font(.system(size: 24))
                        .foregroundStyle(AppColors.success)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Screen Time Earned")
                            .font(AppTypography.caption1)
                            .foregroundStyle(AppColors.textSecondary)
                        Text("\(viewModel.earnedMinutes) min")
                            .font(AppTypography.title2)
                            .foregroundStyle(AppColors.success)
                    }

                    Spacer()
                }
            }
            .padding(AppSpacing.lg)
            .background(AppColors.backgroundSecondary)
            .clipShape(RoundedRectangle(cornerRadius: AppSpacing.cornerRadiusCard))
            .padding(.horizontal, AppSpacing.screenHorizontal)

            Spacer()

            // Done button
            Button {
                dismiss()
            } label: {
                Text("Back to Workouts")
                    .font(AppTypography.bodySemibold)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, AppSpacing.md)
                    .background(AppColors.primary, in: RoundedRectangle(cornerRadius: AppSpacing.cornerRadiusButton))
            }
            .padding(.horizontal, AppSpacing.xl)
            .padding(.bottom, AppSpacing.xl)
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
