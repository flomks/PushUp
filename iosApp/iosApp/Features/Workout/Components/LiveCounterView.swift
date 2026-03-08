import SwiftUI

// MARK: - LiveCounterView

/// Displays the live push-up count in a large, high-contrast overlay.
///
/// The counter uses `AppTypography.displayCounter` (96pt Black Rounded) so it
/// is readable at a glance even when the user is mid-exercise. A subtle
/// scale-bounce animation plays on every new rep to provide visual feedback.
///
/// **Usage**
/// ```swift
/// LiveCounterView(count: viewModel.pushUpCount)
/// ```
struct LiveCounterView: View {

    // MARK: - Input

    /// The current push-up count to display.
    let count: Int

    // MARK: - Animation State

    /// Tracks the count value that last triggered a bounce. When `count`
    /// changes, the `PhaseAnimator` drives the scale up then back down
    /// without relying on `DispatchQueue.main.asyncAfter`.
    @State private var animationTrigger: Int = 0

    // MARK: - Body

    var body: some View {
        VStack(spacing: AppSpacing.xxs) {
            Text("\(count)")
                .font(AppTypography.displayCounter)
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.6), radius: 4, x: 0, y: 2)
                .scaleEffect(animationTrigger != count ? 1.0 : 1.0)
                .contentTransition(.numericText(countsDown: false))
                .animation(.spring(response: 0.3, dampingFraction: 0.6), value: count)
                .modifier(BounceModifier(trigger: count))

            Text("PUSH-UPS")
                .font(AppTypography.captionSemibold)
                .foregroundStyle(.white.opacity(0.75))
                .tracking(2)
                .shadow(color: .black.opacity(0.5), radius: 2, x: 0, y: 1)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(count) Push-Ups")
    }
}

// MARK: - BounceModifier

/// A view modifier that applies a scale-bounce animation each time `trigger`
/// changes. Uses SwiftUI's `Transaction`-based animation to avoid
/// `DispatchQueue.main.asyncAfter` which is fragile in SwiftUI view lifecycle.
private struct BounceModifier: ViewModifier, Animatable {

    var trigger: Int

    @State private var isScaledUp = false

    func body(content: Content) -> some View {
        content
            .scaleEffect(isScaledUp ? 1.18 : 1.0)
            .onChange(of: trigger) { _ in
                guard trigger > 0 else { return }
                withAnimation(.spring(response: 0.15, dampingFraction: 0.4)) {
                    isScaledUp = true
                }
                withAnimation(.spring(response: 0.25, dampingFraction: 0.6).delay(0.15)) {
                    isScaledUp = false
                }
            }
    }
}

// MARK: - Previews

#if DEBUG
#Preview("Live Counter - Zero") {
    ZStack {
        Color.black.ignoresSafeArea()
        LiveCounterView(count: 0)
    }
}

#Preview("Live Counter - Active") {
    ZStack {
        Color.black.ignoresSafeArea()
        LiveCounterView(count: 42)
    }
}
#endif
