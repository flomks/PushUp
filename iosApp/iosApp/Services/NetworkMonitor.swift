import Foundation
import Network
import os.log

// MARK: - NetworkMonitor

/// Observes real-time network connectivity changes using Apple's Network framework.
///
/// **Responsibilities**
/// - Publishes the current connectivity state (`isConnected`) as a reactive
///   `@Published` property so SwiftUI views re-render automatically.
/// - Fires a callback (`onReconnect`) when the device transitions from offline
///   to online, enabling automatic sync triggers.
/// - Provides a `connectionType` property describing the active interface
///   (Wi-Fi, cellular, wired, or unknown).
///
/// **Architecture**
/// The KMP shared module already contains `IosNetworkMonitor` (backed by
/// `nw_path_monitor` via Kotlin/Native C-interop). This Swift-native
/// `NetworkMonitor` is a **presentation-layer** wrapper that:
/// 1. Uses `NWPathMonitor` directly (the Swift API, not the C API) for
///    cleaner integration with SwiftUI's `@Published` / `ObservableObject`.
/// 2. Publishes reactive state that views and view models can observe.
/// 3. Fires the `onReconnect` closure for automatic post-reconnect sync.
///
/// The KMP `IosNetworkMonitor` continues to serve the shared sync use-cases
/// (which only need a snapshot `isConnected()` check). This class serves the
/// iOS UI layer.
///
/// **Threading**
/// Path updates arrive on a dedicated serial `DispatchQueue`. Published
/// property updates are dispatched to the main actor so SwiftUI bindings
/// are always updated on the main thread.
///
/// **Lifecycle**
/// Created as a singleton (`NetworkMonitor.shared`) and started once at app
/// launch. The monitor runs for the entire application lifetime. There is no
/// `stop()` method because the cost of an idle `NWPathMonitor` is negligible.
@MainActor
final class NetworkMonitor: ObservableObject {

    // MARK: - Singleton

    static let shared = NetworkMonitor()

    // MARK: - Published State

    /// `true` when the device has a usable internet connection.
    ///
    /// Defaults to `true` (optimistic) so the UI does not flash an offline
    /// banner before the first path update arrives (typically < 100ms).
    @Published private(set) var isConnected: Bool = true

    /// Describes the type of the current network connection.
    @Published private(set) var connectionType: ConnectionType = .unknown

    // MARK: - Callbacks

    /// Called on the main actor when the device transitions from offline to
    /// online. Set this to trigger an automatic sync after reconnection.
    ///
    /// The closure is intentionally non-escaping from the caller's perspective
    /// (it is stored as a property, but always invoked on `@MainActor`).
    var onReconnect: (() -> Void)?

    // MARK: - Private

    private let monitor = NWPathMonitor()
    private let monitorQueue = DispatchQueue(
        label: "com.pushup.networkMonitor",
        qos: .utility
    )
    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "com.pushup",
        category: "NetworkMonitor"
    )

    // MARK: - Init

    private init() {
        startMonitoring()
    }

    // MARK: - Private Methods

    private func startMonitoring() {
        monitor.pathUpdateHandler = { [weak self] path in
            let connected = path.status == .satisfied
            let type = ConnectionType(path: path)

            Task { @MainActor [weak self] in
                guard let self else { return }

                let previouslyConnected = self.isConnected
                self.isConnected = connected
                self.connectionType = type

                if connected && !previouslyConnected {
                    self.logger.info("Network restored (\(type.label)). Triggering reconnect handler.")
                    self.onReconnect?()
                } else if !connected && previouslyConnected {
                    self.logger.info("Network lost. Device is offline.")
                }
            }
        }
        monitor.start(queue: monitorQueue)
        logger.info("NWPathMonitor started on dedicated queue.")
    }
}

// MARK: - ConnectionType

/// Describes the type of the active network interface.
enum ConnectionType: Equatable {
    case wifi
    case cellular
    case wiredEthernet
    case unknown

    /// Human-readable label for display in debug UI or logs.
    var label: String {
        switch self {
        case .wifi:          return "Wi-Fi"
        case .cellular:      return "Cellular"
        case .wiredEthernet: return "Ethernet"
        case .unknown:       return "Unknown"
        }
    }

    /// Initialises from an `NWPath` by inspecting the available interfaces.
    ///
    /// The order of checks matters: if both Wi-Fi and cellular are available,
    /// Wi-Fi takes precedence (it is the preferred interface on iOS).
    init(path: NWPath) {
        if path.usesInterfaceType(.wifi) {
            self = .wifi
        } else if path.usesInterfaceType(.cellular) {
            self = .cellular
        } else if path.usesInterfaceType(.wiredEthernet) {
            self = .wiredEthernet
        } else {
            self = .unknown
        }
    }
}
