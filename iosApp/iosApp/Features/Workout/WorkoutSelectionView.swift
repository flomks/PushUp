import SwiftUI

// MARK: - WorkoutSelectionView

/// The workout hub screen that displays all available exercises in a
/// visually appealing grid layout.
///
/// **Layout**
/// ```
/// +-----------------------------------+
/// |  Workouts              (nav title)|
/// |                                   |
/// |  [Hero Push-Up Card - full width] |
/// |                                   |
/// |  [Plank]        [Jumping Jacks]   |
/// |  [Squats]       [Crunches]        |
/// |                                   |
/// |  --- Coming Soon ---              |
/// |  [Jogging - locked]               |
/// +-----------------------------------+
/// ```
///
/// Push-Ups gets a prominent hero card since it is the primary exercise
/// with full camera tracking. Other exercises are shown in a 2-column
/// grid. Jogging is shown as "coming soon" with a lock overlay.
struct WorkoutSelectionView: View {

    // MARK: - State

    /// The selected workout type for navigation.
    @State private var selectedWorkout: WorkoutType? = nil

    /// Controls whether the push-up workout (camera) view is presented.
    @State private var showPushUpWorkout = false

    /// Controls whether the jogging workout view is presented.
    @State private var showJoggingWorkout = false

    /// Controls whether a timer-based workout view is presented.
    @State private var showTimerWorkout = false

    // MARK: - Body

    var body: some View {
        ScrollView {
            LazyVStack(spacing: AppSpacing.md) {

                // Section header
                sectionHeader(
                    title: "Choose Your Workout",
                    subtitle: "Earn screen time with every exercise"
                )

                // Hero card for Push-Ups (primary exercise)
                pushUpHeroCard

                // Jogging card (GPS-tracked)
                joggingCard

                // Grid of other available exercises
                exerciseGrid
            }
            .padding(.horizontal, AppSpacing.screenHorizontal)
            .padding(.top, AppSpacing.sm)
            .padding(.bottom, AppSpacing.screenVerticalBottom)
        }
        .background(AppColors.backgroundPrimary)
        .navigationTitle("Workouts")
        .navigationBarTitleDisplayMode(.large)
        .fullScreenCover(isPresented: $showPushUpWorkout) {
            WorkoutView()
        }
        .fullScreenCover(isPresented: $showJoggingWorkout) {
            JoggingView()
        }
        .sheet(item: $selectedWorkout) { workout in
            TimerWorkoutPlaceholderView(workoutType: workout)
        }
    }

    // MARK: - Section Header

    private func sectionHeader(title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.xxs) {
            Text(title)
                .font(AppTypography.title3)
                .foregroundStyle(AppColors.textPrimary)

            Text(subtitle)
                .font(AppTypography.subheadline)
                .foregroundStyle(AppColors.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.bottom, AppSpacing.xs)
    }

    // MARK: - Push-Up Hero Card

    private var pushUpHeroCard: some View {
        Button {
            showPushUpWorkout = true
        } label: {
            HStack(spacing: AppSpacing.md) {
                // Left: Icon with gradient background
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: WorkoutType.pushUps.gradientColors,
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 72, height: 72)

                    Image(icon: WorkoutType.pushUps.icon)
                        .font(.system(size: 32, weight: .semibold))
                        .foregroundStyle(.white)
                        .symbolRenderingMode(.hierarchical)
                }

                // Middle: Text content
                VStack(alignment: .leading, spacing: AppSpacing.xxs) {
                    HStack(spacing: AppSpacing.xs) {
                        Text(WorkoutType.pushUps.displayName)
                            .font(AppTypography.title3)
                            .foregroundStyle(AppColors.textPrimary)

                        // "Camera" badge
                        Text("AI")
                            .font(AppTypography.captionSemibold)
                            .foregroundStyle(.white)
                            .padding(.horizontal, AppSpacing.xs)
                            .padding(.vertical, 2)
                            .background(
                                AppColors.primary,
                                in: Capsule()
                            )
                    }

                    Text(WorkoutType.pushUps.subtitle)
                        .font(AppTypography.subheadline)
                        .foregroundStyle(AppColors.textSecondary)

                    // Earn rate
                    HStack(spacing: AppSpacing.xxs) {
                        Image(icon: .clockBadgeCheckmark)
                            .font(.system(size: AppSpacing.iconSizeSmall))
                            .foregroundStyle(AppColors.success)

                        Text(WorkoutType.pushUps.earnHint)
                            .font(AppTypography.caption1)
                            .foregroundStyle(AppColors.success)
                    }
                    .padding(.top, AppSpacing.xxs)
                }

                Spacer()

                // Right: Chevron
                Image(icon: .chevronRight)
                    .font(.system(size: AppSpacing.iconSizeStandard, weight: .semibold))
                    .foregroundStyle(AppColors.textTertiary)
            }
            .padding(AppSpacing.md)
            .background(AppColors.backgroundSecondary)
            .clipShape(RoundedRectangle(cornerRadius: AppSpacing.cornerRadiusCard))
            .shadow(color: Color.black.opacity(0.08), radius: 10, x: 0, y: 4)
            .overlay(
                RoundedRectangle(cornerRadius: AppSpacing.cornerRadiusCard)
                    .strokeBorder(
                        LinearGradient(
                            colors: [AppColors.primary.opacity(0.3), AppColors.primary.opacity(0.1)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            )
        }
        .buttonStyle(ScaleButtonStyle())
    }

    // MARK: - Jogging Card

    private var joggingCard: some View {
        Button {
            showJoggingWorkout = true
        } label: {
            HStack(spacing: AppSpacing.md) {
                // Left: Icon with gradient background
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: WorkoutType.jogging.gradientColors,
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 60, height: 60)

                    Image(icon: WorkoutType.jogging.icon)
                        .font(.system(size: 28, weight: .semibold))
                        .foregroundStyle(.white)
                        .symbolRenderingMode(.hierarchical)
                }

                // Middle: Text content
                VStack(alignment: .leading, spacing: AppSpacing.xxs) {
                    HStack(spacing: AppSpacing.xs) {
                        Text(WorkoutType.jogging.displayName)
                            .font(AppTypography.subheadlineSemibold)
                            .foregroundStyle(AppColors.textPrimary)

                        // "GPS" badge
                        Text("GPS")
                            .font(AppTypography.captionSemibold)
                            .foregroundStyle(.white)
                            .padding(.horizontal, AppSpacing.xs)
                            .padding(.vertical, 2)
                            .background(
                                AppColors.info,
                                in: Capsule()
                            )
                    }

                    Text(WorkoutType.jogging.subtitle)
                        .font(AppTypography.caption1)
                        .foregroundStyle(AppColors.textSecondary)

                    // Earn rate
                    HStack(spacing: AppSpacing.xxs) {
                        Image(icon: .clockBadgeCheckmark)
                            .font(.system(size: AppSpacing.iconSizeSmall))
                            .foregroundStyle(AppColors.success)

                        Text(WorkoutType.jogging.earnHint)
                            .font(AppTypography.caption1)
                            .foregroundStyle(AppColors.success)
                    }
                }

                Spacer()

                // Right: Chevron
                Image(icon: .chevronRight)
                    .font(.system(size: AppSpacing.iconSizeStandard, weight: .semibold))
                    .foregroundStyle(AppColors.textTertiary)
            }
            .padding(AppSpacing.md)
            .background(AppColors.backgroundSecondary)
            .clipShape(RoundedRectangle(cornerRadius: AppSpacing.cornerRadiusCard))
            .shadow(color: Color.black.opacity(0.05), radius: 6, x: 0, y: 2)
            .overlay(
                RoundedRectangle(cornerRadius: AppSpacing.cornerRadiusCard)
                    .strokeBorder(
                        LinearGradient(
                            colors: [AppColors.info.opacity(0.3), AppColors.info.opacity(0.1)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            )
        }
        .buttonStyle(ScaleButtonStyle())
    }

    // MARK: - Exercise Grid

    private var exerciseGrid: some View {
        let availableExercises: [WorkoutType] = [.plank, .jumpingJacks, .squats, .crunches]

        return LazyVGrid(
            columns: [
                GridItem(.flexible(), spacing: AppSpacing.sm),
                GridItem(.flexible(), spacing: AppSpacing.sm),
            ],
            spacing: AppSpacing.sm
        ) {
            ForEach(availableExercises) { workout in
                ExerciseCard(workoutType: workout) {
                    selectedWorkout = workout
                }
            }
        }
    }

}

// MARK: - ExerciseCard

/// A compact card for a single exercise in the selection grid.
///
/// Shows the exercise icon, name, difficulty dots, and earn rate.
/// Tapping the card triggers the provided action.
struct ExerciseCard: View {

    let workoutType: WorkoutType
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: AppSpacing.sm) {
                // Icon with colored background
                ZStack {
                    RoundedRectangle(cornerRadius: AppSpacing.cornerRadiusChip)
                        .fill(workoutType.accentColor.opacity(0.12))
                        .frame(width: 56, height: 56)

                    Image(icon: workoutType.icon)
                        .font(.system(size: 28, weight: .semibold))
                        .foregroundStyle(workoutType.accentColor)
                        .symbolRenderingMode(.hierarchical)
                }

                // Name
                Text(workoutType.displayName)
                    .font(AppTypography.subheadlineSemibold)
                    .foregroundStyle(AppColors.textPrimary)
                    .lineLimit(1)

                // Difficulty dots
                DifficultyIndicator(difficulty: workoutType.difficulty)

                // Earn rate
                HStack(spacing: AppSpacing.xxs) {
                    Image(icon: .boltFill)
                        .font(.system(size: 10))
                        .foregroundStyle(AppColors.success)

                    Text(workoutType.earnHint)
                        .font(AppTypography.caption2)
                        .foregroundStyle(AppColors.textSecondary)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, AppSpacing.md)
            .padding(.horizontal, AppSpacing.sm)
            .background(AppColors.backgroundSecondary)
            .clipShape(RoundedRectangle(cornerRadius: AppSpacing.cornerRadiusCard))
            .shadow(color: Color.black.opacity(0.05), radius: 6, x: 0, y: 2)
        }
        .buttonStyle(ScaleButtonStyle())
    }
}

// MARK: - DifficultyIndicator

/// Shows the difficulty level as colored dots (1 = easy, 2 = medium, 3 = hard).
struct DifficultyIndicator: View {

    let difficulty: WorkoutType.Difficulty

    var body: some View {
        HStack(spacing: 3) {
            ForEach(0..<3, id: \.self) { index in
                Circle()
                    .fill(index < difficulty.dotCount ? difficulty.color : AppColors.fill)
                    .frame(width: 6, height: 6)
            }

            Text(difficulty.displayName)
                .font(AppTypography.caption2)
                .foregroundStyle(difficulty.color)
        }
    }
}

// MARK: - ComingSoonCard

/// A locked exercise card shown in the "Coming Soon" section.
struct ComingSoonCard: View {

    let workoutType: WorkoutType

    var body: some View {
        HStack(spacing: AppSpacing.md) {
            // Icon
            ZStack {
                RoundedRectangle(cornerRadius: AppSpacing.cornerRadiusChip)
                    .fill(workoutType.accentColor.opacity(0.08))
                    .frame(width: 52, height: 52)

                Image(icon: workoutType.icon)
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(workoutType.accentColor.opacity(0.5))
                    .symbolRenderingMode(.hierarchical)
            }

            // Text
            VStack(alignment: .leading, spacing: AppSpacing.xxs) {
                HStack(spacing: AppSpacing.xs) {
                    Text(workoutType.displayName)
                        .font(AppTypography.subheadlineSemibold)
                        .foregroundStyle(AppColors.textSecondary)

                    Image(systemName: "lock.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(AppColors.textTertiary)
                }

                Text(workoutType.subtitle)
                    .font(AppTypography.caption1)
                    .foregroundStyle(AppColors.textTertiary)
            }

            Spacer()
        }
        .padding(AppSpacing.md)
        .background(AppColors.backgroundSecondary.opacity(0.6))
        .clipShape(RoundedRectangle(cornerRadius: AppSpacing.cornerRadiusCard))
        .overlay(
            RoundedRectangle(cornerRadius: AppSpacing.cornerRadiusCard)
                .strokeBorder(AppColors.separator.opacity(0.5), lineWidth: 1)
        )
    }
}

// MARK: - TimerWorkoutPlaceholderView

/// Placeholder view for timer-based workouts (Plank, Jumping Jacks, Squats, Crunches).
///
/// This will be replaced with the full workout implementation later.
/// For now it shows the exercise info and a "coming soon" message.
struct TimerWorkoutPlaceholderView: View {

    let workoutType: WorkoutType

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                AppColors.backgroundPrimary
                    .ignoresSafeArea()

                VStack(spacing: AppSpacing.xl) {
                    Spacer()

                    // Exercise icon
                    ZStack {
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: workoutType.gradientColors,
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 120, height: 120)

                        Image(icon: workoutType.icon)
                            .font(.system(size: 56, weight: .semibold))
                            .foregroundStyle(.white)
                            .symbolRenderingMode(.hierarchical)
                    }

                    VStack(spacing: AppSpacing.sm) {
                        Text(workoutType.displayName)
                            .font(AppTypography.title1)
                            .foregroundStyle(AppColors.textPrimary)

                        Text("Workout tracking for \(workoutType.displayName) is being built.")
                            .font(AppTypography.subheadline)
                            .foregroundStyle(AppColors.textSecondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, AppSpacing.xl)

                        // Earn rate info
                        HStack(spacing: AppSpacing.xs) {
                            Image(icon: .clockBadgeCheckmark)
                                .font(.system(size: AppSpacing.iconSizeStandard))
                                .foregroundStyle(AppColors.success)

                            Text(workoutType.earnHint)
                                .font(AppTypography.bodySemibold)
                                .foregroundStyle(AppColors.success)
                        }
                        .padding(.top, AppSpacing.sm)
                    }

                    Spacer()

                    // Difficulty info
                    Card {
                        HStack {
                            VStack(alignment: .leading, spacing: AppSpacing.xxs) {
                                Text("Difficulty")
                                    .font(AppTypography.caption1)
                                    .foregroundStyle(AppColors.textSecondary)

                                DifficultyIndicator(difficulty: workoutType.difficulty)
                            }

                            Spacer()

                            VStack(alignment: .trailing, spacing: AppSpacing.xxs) {
                                Text("Earn Rate")
                                    .font(AppTypography.caption1)
                                    .foregroundStyle(AppColors.textSecondary)

                                Text(workoutType.earnHint)
                                    .font(AppTypography.subheadlineSemibold)
                                    .foregroundStyle(workoutType.accentColor)
                            }
                        }
                    }
                    .padding(.horizontal, AppSpacing.md)

                    // Coming soon notice
                    VStack(spacing: AppSpacing.xs) {
                        Image(systemName: "wrench.and.screwdriver")
                            .font(.system(size: AppSpacing.iconSizeLarge))
                            .foregroundStyle(AppColors.textTertiary)

                        Text("Full tracking coming soon!")
                            .font(AppTypography.subheadline)
                            .foregroundStyle(AppColors.textTertiary)
                    }
                    .padding(.bottom, AppSpacing.xl)
                }
            }
            .navigationTitle(workoutType.displayName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                    .foregroundStyle(AppColors.primary)
                }
            }
        }
    }
}

// MARK: - Previews

#if DEBUG
#Preview("Workout Selection") {
    NavigationStack {
        WorkoutSelectionView()
    }
}

#Preview("Workout Selection - Dark") {
    NavigationStack {
        WorkoutSelectionView()
    }
    .preferredColorScheme(.dark)
}

#Preview("Exercise Card") {
    ExerciseCard(workoutType: .plank) {}
        .frame(width: 180)
        .padding()
        .background(AppColors.backgroundPrimary)
}

#Preview("Timer Workout Placeholder") {
    TimerWorkoutPlaceholderView(workoutType: .plank)
}
#endif
