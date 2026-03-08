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

    @State private var scale: CGFloat = 1.0

    // MARK: - Body

    var body: some View {
        VStack(spacing: AppSpacing.xxs) {
            Text("\(count)")
                .font(AppTypography.displayCounter)
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.6), radius: 4, x: 0, y: 2)
                .scaleEffect(scale)
                .contentTransition(.numericText(countsDown: false))
                .animation(.spring(response: 0.3, dampingFraction: 0.6), value: count)

            Text("PUSH-UPS")
                .font(AppTypography.captionSemibold)
                .foregroundStyle(.white.opacity(0.75))
                .tracking(2)
                .shadow(color: .black.opacity(0.5), radius: 2, x: 0, y: 1)
        }
        .onChange(of: count) { _ in
            bounceAnimation()
        }
    }

    // MARK: - Private

    private func bounceAnimation() {
        withAnimation(.spring(response: 0.15, dampingFraction: 0.4)) {
            scale = 1.18
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            withAnimation(.spring(response: 0.25, dampingFraction: 0.6)) {
                scale = 1.0
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
