import ManagedSettings
import ManagedSettingsUI
import UIKit

// MARK: - ShieldConfigurationExtension

/// Customises the appearance of the system app shield (lock screen).
///
/// Shown when a blocked app is opened. Displays the PushUp branding
/// with a motivational message and a button to open the workout screen.
///
/// **Bundle ID:** `com.flomks.sinura.ShieldConfiguration`
class ShieldConfigurationExtension: ShieldConfigurationDataSource {

    override func configuration(shielding application: Application) -> ShieldConfiguration {
        makeConfiguration()
    }

    override func configuration(
        shielding application: Application,
        in category: ActivityCategory
    ) -> ShieldConfiguration {
        makeConfiguration()
    }

    override func configuration(shielding webDomain: WebDomain) -> ShieldConfiguration {
        makeConfiguration()
    }

    override func configuration(
        shielding webDomain: WebDomain,
        in category: ActivityCategory
    ) -> ShieldConfiguration {
        makeConfiguration()
    }

    // MARK: - Shared Builder

    private func makeConfiguration() -> ShieldConfiguration {
        ShieldConfiguration(
            backgroundBlurStyle: .systemUltraThinMaterial,
            backgroundColor: UIColor.systemBackground,
            icon: UIImage(named: "AppIcon"),
            title: ShieldConfiguration.Label(
                text: "Time Credit Exhausted",
                color: UIColor.label
            ),
            subtitle: ShieldConfiguration.Label(
                text: "Do a workout to earn more screen time!",
                color: UIColor.secondaryLabel
            ),
            primaryButtonLabel: ShieldConfiguration.Label(
                text: "Train Now",
                color: .white
            ),
            primaryButtonBackgroundColor: UIColor(
                red: 0.0, green: 0.478, blue: 1.0, alpha: 1.0
            ),
            secondaryButtonLabel: ShieldConfiguration.Label(
                text: "Not Now",
                color: UIColor.secondaryLabel
            )
        )
    }
}
