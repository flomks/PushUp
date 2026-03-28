import UIKit

// MARK: - DashboardHaptics

/// Respects the in-app “Haptic Feedback” setting from Settings.
enum DashboardHaptics {

    private static var feedbackEnabled: Bool {
        if UserDefaults.standard.object(forKey: SettingsKeys.hapticFeedback) == nil {
            return true
        }
        return UserDefaults.standard.bool(forKey: SettingsKeys.hapticFeedback)
    }

    static func lightImpact() {
        guard feedbackEnabled else { return }
        let g = UIImpactFeedbackGenerator(style: .light)
        g.prepare()
        g.impactOccurred(intensity: 0.85)
        g.prepare()
    }

    static func mediumImpact() {
        guard feedbackEnabled else { return }
        let g = UIImpactFeedbackGenerator(style: .medium)
        g.prepare()
        g.impactOccurred(intensity: 0.9)
        g.prepare()
    }

    static func success() {
        guard feedbackEnabled else { return }
        let g = UINotificationFeedbackGenerator()
        g.prepare()
        g.notificationOccurred(.success)
        g.prepare()
    }
}
