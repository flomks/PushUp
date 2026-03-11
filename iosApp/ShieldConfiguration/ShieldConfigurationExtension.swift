import ManagedSettings
import ManagedSettingsUI
import UIKit

// MARK: - ShieldConfigurationExtension

/// Shield Configuration Extension.
///
/// Customises the appearance of the system-provided app shield (lock screen)
/// that appears when a blocked app is opened.
///
/// The shield shows:
/// - The PushUp app icon
/// - A motivational title ("Time Credit Exhausted")
/// - A subtitle explaining how to regain access
/// - A primary button that opens the PushUp app to start a workout
///
/// **Bundle ID:** `com.flomks.pushup.ShieldConfiguration`
/// **App Group:** `group.com.flomks.pushup`
///
/// **Note:** The primary button action (opening the main app) is handled
/// by the `ShieldActionExtension`, not here. This extension only controls
/// the visual appearance.
class ShieldConfigurationExtension: ShieldConfigurationDataSource {

    // MARK: - Application Shield

    override func configuration(
        shielding application: Application
    ) -> ShieldConfiguration {
        makeConfiguration(
            subtitle: "This app is blocked because your time credit has run out."
        )
    }

    // MARK: - Application Category Shield

    override func configuration(
        shielding application: Application,
        in category: ActivityCategory
    ) -> ShieldConfiguration {
        makeConfiguration(
            subtitle: "Apps in this category are blocked because your time credit has run out."
        )
    }

    // MARK: - Web Domain Shield

    override func configuration(
        shielding webDomain: WebDomain
    ) -> ShieldConfiguration {
        makeConfiguration(
            subtitle: "This website is blocked because your time credit has run out."
        )
    }

    // MARK: - Web Domain Category Shield

    override func configuration(
        shielding webDomain: WebDomain,
        in category: ActivityCategory
    ) -> ShieldConfiguration {
        makeConfiguration(
            subtitle: "Websites in this category are blocked because your time credit has run out."
        )
    }

    // MARK: - Shared Configuration Builder

    private func makeConfiguration(subtitle: String) -> ShieldConfiguration {
        ShieldConfiguration(
            backgroundBlurStyle: .systemUltraThinMaterial,
            backgroundColor: UIColor.systemBackground,
            icon: UIImage(named: "AppIcon"),
            title: ShieldConfiguration.Label(
                text: "Time Credit Exhausted",
                color: UIColor.label
            ),
            subtitle: ShieldConfiguration.Label(
                text: subtitle,
                color: UIColor.secondaryLabel
            ),
            primaryButtonLabel: ShieldConfiguration.Label(
                text: "Do Push-Ups to Earn More",
                color: .white
            ),
            primaryButtonBackgroundColor: UIColor(
                red: 0.0, green: 0.478, blue: 1.0, alpha: 1.0  // #007AFF
            ),
            secondaryButtonLabel: ShieldConfiguration.Label(
                text: "Not Now",
                color: UIColor.secondaryLabel
            )
        )
    }
}
