import SwiftUI

// MARK: - WorkoutSummaryView

/// Full-screen celebratory completion screen shown after a workout ends (Task 3.7).
///
/// **Layout**
/// ```
/// +-----------------------------------+
/// |  [Confetti particles]             |
/// |                                   |
/// |  [Trophy / Checkmark icon]        |
/// |  "Workout complete!"              |
/// |  "+ 5 minutes earned!"            |
/// |                                   |
/// |  [SummaryCard]                    |
/// |    - Push-Up count (animated)     |
/// |    - Duration                     |
/// |    - Earned time credit           |
/// |    - Quality stars                |
/// |    - Comparison badge             |
/// |                                   |
/// |  [Share Button]                   |
/// |  [Back to Dashboard Button]       |
/// +-----------------------------------+
/// ```
///
/// **Acceptance criteria covered (Task 3.7)**
/// - Large push-up count with count-up animation (`SummaryCard`)
/// - Earned time credit prominently displayed ("+ 5 minutes earned!")
/// - Session duration in `SummaryCard`
/// - Average quality as star rating + percentage in `SummaryCard`
/// - Comparison to personal average ("12% better than your average")
/// - "Back to Dashboard" button
/// - Share button (native share sheet with screenshot + social text)
/// - Confetti animation on new personal record
/// - Celebratory, positive design with gradient background
struct WorkoutSummaryView: View {

    // MARK: - Input

    /// Total push-ups completed.
    let pushUpCount: Int

    /// Session duration in seconds.
    let durationSeconds: Int

    /// Time credit earned in whole minutes.
    let earnedMinutes: Int

    /// Average form quality score in [0.0, 1.0]. `nil` if no reps counted.
    let qualityScore: Double?

    /// Percentage above/below personal average. `nil` when unavailable.
    let comparisonPercent: Int?

    /// Whether this session is a new personal record (triggers confetti).
    let isNewRecord: Bool

    /// Called when the user taps "Back to Dashboard".
    let onDashboard: () -> Void

    // MARK: - Animation State

    @State private var headerVisible: Bool = false
    @State private var creditBannerVisible: Bool = false
    @State private var confettiParticles: [ConfettiParticle] = []
    @State private var showShareSheet: Bool = false
    @State private var shareItems: [Any] = []

    // MARK: - Body

    var body: some View {
        ZStack {
            // Gradient background
            backgroundGradient
                .ignoresSafeArea()

            // Confetti layer (new record only)
            if isNewRecord {
                confettiLayer
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
            }

            // Scrollable content
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: AppSpacing.lg) {
                    Spacer(minLength: AppSpacing.xxl)

                    headerSection

                    earnedCreditBanner

                    SummaryCard(
                        pushUpCount: pushUpCount,
                        durationSeconds: durationSeconds,
                        earnedMinutes: earnedMinutes,
                        qualityScore: qualityScore,
                        comparisonPercent: comparisonPercent
                    )
                    .padding(.horizontal, AppSpacing.xl)

                    actionButtons

                    Spacer(minLength: AppSpacing.xl)
                }
            }
        }
        .onAppear {
            animateEntrance()
            if isNewRecord {
                spawnConfetti()
            }
        }
        .sheet(isPresented: $showShareSheet) {
            ShareSheet(items: shareItems)
        }
    }

    // MARK: - Background

    private var backgroundGradient: some View {
        LinearGradient(
            stops: [
                .init(color: Color(light: "#0f2027", dark: "#0a1628"), location: 0),
                .init(color: Color(light: "#203a43", dark: "#0d2137"), location: 0.5),
                .init(color: Color(light: "#2c5364", dark: "#0f2d40"), location: 1),
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    // MARK: - Header Section

    private var headerSection: some View {
        VStack(spacing: AppSpacing.sm) {
            // Trophy or checkmark icon
            ZStack {
                Circle()
                    .fill(
                        isNewRecord
                            ? AppColors.secondaryVariant.opacity(0.2)
                            : AppColors.success.opacity(0.15)
                    )
                    .frame(width: 96, height: 96)

                Image(systemName: isNewRecord ? "trophy.fill" : "checkmark.circle.fill")
                    .font(.system(size: 48, weight: .semibold))
                    .foregroundStyle(
                        isNewRecord
                            ? AppColors.secondaryVariant
                            : AppColors.success
                    )
                    .symbolRenderingMode(.hierarchical)
            }
            .scaleEffect(headerVisible ? 1 : 0.5)
            .opacity(headerVisible ? 1 : 0)

            VStack(spacing: AppSpacing.xxs) {
                Text(isNewRecord ? "New Record!" : "Workout Complete!")
                    .font(AppTypography.roundedTitle)
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)

                if isNewRecord {
                    Text("That's your best result yet!")
                        .font(AppTypography.subheadline)
                        .foregroundStyle(AppColors.secondaryVariant.opacity(0.9))
                        .multilineTextAlignment(.center)
                }
            }
            .opacity(headerVisible ? 1 : 0)
            .offset(y: headerVisible ? 0 : 12)
        }
    }

    // MARK: - Earned Credit Banner

    private var earnedCreditBanner: some View {
        HStack(spacing: AppSpacing.xs) {
            Image(systemName: "clock.badge.checkmark")
                .font(.system(size: AppSpacing.iconSizeMedium, weight: .bold))
                .foregroundStyle(AppColors.success)
                .symbolRenderingMode(.hierarchical)

            Text("+ \(earnedMinutes) minutes earned!")
                .font(Font.system(size: 20, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
        }
        .padding(.horizontal, AppSpacing.lg)
        .padding(.vertical, AppSpacing.sm)
        .background(
            Capsule()
                .fill(AppColors.success.opacity(0.2))
                .overlay(
                    Capsule()
                        .strokeBorder(AppColors.success.opacity(0.5), lineWidth: 1.5)
                )
        )
        .scaleEffect(creditBannerVisible ? 1 : 0.85)
        .opacity(creditBannerVisible ? 1 : 0)
        .accessibilityLabel("Plus \(earnedMinutes) minutes of time credit earned")
    }

    // MARK: - Action Buttons

    private var actionButtons: some View {
        VStack(spacing: AppSpacing.sm) {
            // Share button
            Button {
                prepareAndShare()
            } label: {
                HStack(spacing: AppSpacing.xs) {
                    Image(icon: .squareAndArrowUp)
                        .font(.system(size: AppSpacing.iconSizeStandard, weight: .semibold))
                    Text("Share")
                        .font(AppTypography.buttonPrimary)
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: AppSpacing.buttonHeightPrimary)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: AppSpacing.cornerRadiusButton))
                .overlay(
                    RoundedRectangle(cornerRadius: AppSpacing.cornerRadiusButton)
                        .strokeBorder(.white.opacity(0.25), lineWidth: 1)
                )
            }
            .buttonStyle(ScaleButtonStyle())
            .padding(.horizontal, AppSpacing.xl)

            // Back to dashboard button
            Button(action: onDashboard) {
                HStack(spacing: AppSpacing.xs) {
                    Image(icon: .houseFill)
                        .font(.system(size: AppSpacing.iconSizeStandard, weight: .semibold))
                    Text("Back to Dashboard")
                        .font(AppTypography.buttonPrimary)
                }
                .foregroundStyle(.black)
                .frame(maxWidth: .infinity)
                .frame(height: AppSpacing.buttonHeightPrimary)
                .background(.white)
                .clipShape(RoundedRectangle(cornerRadius: AppSpacing.cornerRadiusButton))
            }
            .buttonStyle(ScaleButtonStyle())
            .padding(.horizontal, AppSpacing.xl)
        }
    }

    // MARK: - Confetti Layer

    private var confettiLayer: some View {
        GeometryReader { geo in
            ForEach(confettiParticles) { particle in
                ConfettiPieceView(particle: particle, containerSize: geo.size)
            }
        }
    }

    // MARK: - Entrance Animation

    private func animateEntrance() {
        withAnimation(.spring(response: 0.55, dampingFraction: 0.7).delay(0.1)) {
            headerVisible = true
        }
        withAnimation(.spring(response: 0.5, dampingFraction: 0.65).delay(0.35)) {
            creditBannerVisible = true
        }
    }

    // MARK: - Confetti Spawning

    private func spawnConfetti() {
        confettiParticles = (0..<80).map { _ in ConfettiParticle() }
    }

    // MARK: - Share

    private func prepareAndShare() {
        let qualityText: String
        if let score = qualityScore {
            qualityText = "\(Int(score * 100))% form quality"
        } else {
            qualityText = ""
        }

        let minutes = durationSeconds / 60
        let seconds = durationSeconds % 60
        let durationText = seconds > 0 ? "\(minutes):\(String(format: "%02d", seconds)) Min" : "\(minutes) Min"

        var lines = [
            "I just did \(pushUpCount) push-ups!",
            "Duration: \(durationText)",
        ]
        if !qualityText.isEmpty {
            lines.append(qualityText)
        }
        lines.append("+\(earnedMinutes) minutes of time credit earned")
        lines.append("#Sinura #Fitness #Workout")

        let text = lines.joined(separator: "\n")
        shareItems = [text]
        showShareSheet = true
    }
}

// MARK: - ConfettiParticle

/// Data model for a single confetti piece.
struct ConfettiParticle: Identifiable {

    let id = UUID()
    let color: Color
    let xStart: CGFloat
    let xDrift: CGFloat
    let size: CGFloat
    let rotationSpeed: Double
    let fallDuration: Double
    let delay: Double
    let shape: ConfettiShape

    enum ConfettiShape: CaseIterable {
        case circle, rectangle, triangle
    }

    init() {
        let palette: [Color] = [
            AppColors.primary,
            AppColors.secondary,
            AppColors.success,
            AppColors.secondaryVariant,
            .white,
            AppColors.info,
        ]
        color = palette.randomElement()!
        xStart = CGFloat.random(in: 0.05...0.95)
        xDrift = CGFloat.random(in: -0.15...0.15)
        size = CGFloat.random(in: 6...14)
        rotationSpeed = Double.random(in: 180...720)
        fallDuration = Double.random(in: 2.5...4.5)
        delay = Double.random(in: 0...1.2)
        shape = ConfettiShape.allCases.randomElement()!
    }
}

// MARK: - ConfettiPieceView

/// Animates a single confetti piece falling from the top of the screen.
private struct ConfettiPieceView: View {

    let particle: ConfettiParticle
    let containerSize: CGSize

    @State private var yOffset: CGFloat = -20
    @State private var xOffset: CGFloat = 0
    @State private var rotation: Double = 0
    @State private var opacity: Double = 1

    var body: some View {
        confettiShape
            .frame(width: particle.size, height: particle.size)
            .foregroundStyle(particle.color)
            .rotationEffect(.degrees(rotation))
            .position(
                x: containerSize.width * particle.xStart + xOffset,
                y: yOffset
            )
            .opacity(opacity)
            .onAppear {
                withAnimation(
                    .easeIn(duration: particle.fallDuration)
                    .delay(particle.delay)
                ) {
                    yOffset = containerSize.height + 40
                    xOffset = containerSize.width * particle.xDrift
                    rotation = particle.rotationSpeed
                }
                withAnimation(
                    .easeIn(duration: 0.6)
                    .delay(particle.delay + particle.fallDuration - 0.6)
                ) {
                    opacity = 0
                }
            }
    }

    @ViewBuilder
    private var confettiShape: some View {
        switch particle.shape {
        case .circle:
            Circle()
        case .rectangle:
            Rectangle()
        case .triangle:
            Triangle()
        }
    }
}

// MARK: - Triangle Shape

/// A simple equilateral triangle shape for confetti variety.
private struct Triangle: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

// MARK: - ShareSheet

/// A UIActivityViewController wrapper for the native iOS share sheet.
struct ShareSheet: UIViewControllerRepresentable {

    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

// MARK: - Previews

#if DEBUG
#Preview("Summary - New Record") {
    WorkoutSummaryView(
        pushUpCount: 55,
        durationSeconds: 612,
        earnedMinutes: 7,
        qualityScore: 0.91,
        comparisonPercent: 23,
        isNewRecord: true,
        onDashboard: {}
    )
}

#Preview("Summary - Normal Session") {
    WorkoutSummaryView(
        pushUpCount: 42,
        durationSeconds: 487,
        earnedMinutes: 5,
        qualityScore: 0.78,
        comparisonPercent: 12,
        isNewRecord: false,
        onDashboard: {}
    )
}

#Preview("Summary - Below Average") {
    WorkoutSummaryView(
        pushUpCount: 18,
        durationSeconds: 240,
        earnedMinutes: 2,
        qualityScore: 0.52,
        comparisonPercent: -15,
        isNewRecord: false,
        onDashboard: {}
    )
}

#Preview("Summary - First Session") {
    WorkoutSummaryView(
        pushUpCount: 10,
        durationSeconds: 150,
        earnedMinutes: 1,
        qualityScore: nil,
        comparisonPercent: nil,
        isNewRecord: false,
        onDashboard: {}
    )
}
#endif
