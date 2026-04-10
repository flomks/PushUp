import SwiftUI

// MARK: - OnboardingSlide Model

/// Data model for a single onboarding slide.
struct OnboardingSlide {
    let icon: AppIcon
    let imageColor: Color
    let title: String
    let description: String
}

// MARK: - OnboardingView

/// Full-screen onboarding flow shown only on the first app launch.
///
/// Displays 3 slides:
///   1. Welcome to Sinura
///   2. Camera explanation
///   3. Time credit explanation
///
/// After the user taps "Loslegen" on the last slide, `hasSeenOnboarding`
/// is persisted to `UserDefaults` and `onComplete` is called so the parent
/// can transition to the auth flow.
struct OnboardingView: View {

    // MARK: - Properties

    /// Called when the user finishes or skips onboarding.
    let onComplete: () -> Void

    @State private var currentPage: Int = 0
    @State private var animateContent: Bool = false

    // MARK: - Slides

    private let slides: [OnboardingSlide] = [
        OnboardingSlide(
            icon: .figureStrengthTraining,
            imageColor: AppColors.primary,
            title: "Welcome to Sinura",
            description: "Earn screen time through real activity. Work out, go for a run, and receive time credit for your favourite apps."
        ),
        OnboardingSlide(
            icon: .cameraViewfinder,
            imageColor: AppColors.secondary,
            title: "Camera detects you",
            description: "Hold your iPhone so the camera can see your whole body. AI automatically detects your exercises and rates your form."
        ),
        OnboardingSlide(
            icon: .clockBadgeCheckmark,
            imageColor: AppColors.success,
            title: "Earn time credit",
            description: "Every workout earns you screen time. The more active you are, the more time you earn. Start now!"
        )
    ]

    // MARK: - Body

    var body: some View {
        ZStack {
            // Background gradient
            backgroundGradient
                .ignoresSafeArea()

            VStack(spacing: 0) {
                // Skip button
                skipButton
                    .padding(.top, AppSpacing.screenVerticalTop)
                    .padding(.horizontal, AppSpacing.screenHorizontal)

                // Slide content (paged)
                TabView(selection: $currentPage) {
                    ForEach(slides.indices, id: \.self) { index in
                        slideView(slides[index])
                            .tag(index)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .animation(.easeInOut(duration: 0.4), value: currentPage)

                // Bottom controls
                bottomControls
                    .padding(.horizontal, AppSpacing.screenHorizontal)
                    .padding(.bottom, AppSpacing.xxl)
            }
        }
        .onAppear {
            withAnimation(.easeOut(duration: 0.5)) {
                animateContent = true
            }
        }
    }

    // MARK: - Subviews

    private var backgroundGradient: some View {
        LinearGradient(
            colors: [
                AppColors.backgroundPrimary,
                AppColors.backgroundSecondary
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    private var skipButton: some View {
        HStack {
            Spacer()
            if currentPage < slides.count - 1 {
                Button("Skip") {
                    completeOnboarding()
                }
                .font(AppTypography.buttonSecondary)
                .foregroundStyle(AppColors.textSecondary)
            }
        }
        .frame(height: AppSpacing.minimumTapTarget)
    }

    @ViewBuilder
    private func slideView(_ slide: OnboardingSlide) -> some View {
        VStack(spacing: AppSpacing.xl) {
            Spacer()

            // Illustration
            ZStack {
                Circle()
                    .fill(slide.imageColor.opacity(0.12))
                    .frame(width: 200, height: 200)

                Circle()
                    .fill(slide.imageColor.opacity(0.06))
                    .frame(width: 240, height: 240)

                Image(icon: slide.icon)
                    .font(.system(size: 80, weight: .light))
                    .foregroundStyle(slide.imageColor)
                    .symbolRenderingMode(.hierarchical)
            }
            .scaleEffect(animateContent ? 1.0 : 0.7)
            .opacity(animateContent ? 1.0 : 0)
            .animation(.spring(response: 0.6, dampingFraction: 0.7), value: animateContent)

            // Text content
            VStack(spacing: AppSpacing.md) {
                Text(slide.title)
                    .font(AppTypography.title1)
                    .foregroundStyle(AppColors.textPrimary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)

                Text(slide.description)
                    .font(AppTypography.body)
                    .foregroundStyle(AppColors.textSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .lineSpacing(4)
            }
            .padding(.horizontal, AppSpacing.lg)
            .opacity(animateContent ? 1.0 : 0)
            .offset(y: animateContent ? 0 : 20)
            .animation(.easeOut(duration: 0.5).delay(0.15), value: animateContent)

            Spacer()
        }
        .padding(.horizontal, AppSpacing.screenHorizontal)
    }

    private var bottomControls: some View {
        VStack(spacing: AppSpacing.lg) {
            // Page indicator dots
            pageIndicator

            // Action button
            if currentPage < slides.count - 1 {
                PrimaryButton("Next", icon: .arrowRight) {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        currentPage += 1
                    }
                    // Reset animation for next slide
                    animateContent = false
                    withAnimation(.easeOut(duration: 0.5).delay(0.1)) {
                        animateContent = true
                    }
                }
            } else {
                PrimaryButton("Get Started", icon: .checkmark) {
                    completeOnboarding()
                }
            }
        }
    }

    private var pageIndicator: some View {
        HStack(spacing: AppSpacing.xs) {
            ForEach(slides.indices, id: \.self) { index in
                Capsule()
                    .fill(index == currentPage ? AppColors.primary : AppColors.separator)
                    .frame(
                        width: index == currentPage ? 24 : 8,
                        height: 8
                    )
                    .animation(.spring(response: 0.4, dampingFraction: 0.7), value: currentPage)
            }
        }
    }

    // MARK: - Actions

    private func completeOnboarding() {
        // Persistence is handled by the parent (RootView) via @AppStorage
        // when onComplete fires. Do not write UserDefaults here to avoid
        // dual-write inconsistency.
        onComplete()
    }
}

// MARK: - Preview

#if DEBUG
#Preview("Onboarding") {
    OnboardingView(onComplete: {})
}
#endif
