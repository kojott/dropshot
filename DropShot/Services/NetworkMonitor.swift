import Foundation
import Network

// MARK: - Connection Type

extension NetworkMonitor {
    enum ConnectionType: String, CustomStringConvertible {
        case wifi
        case cellular
        case wiredEthernet
        case unknown

        var description: String {
            switch self {
            case .wifi: return "Wi-Fi"
            case .cellular: return "Cellular"
            case .wiredEthernet: return "Ethernet"
            case .unknown: return "Unknown"
            }
        }
    }
}

// MARK: - Network Monitor

@MainActor
final class NetworkMonitor: ObservableObject {
    static let shared = NetworkMonitor()

    @Published private(set) var isConnected: Bool = true
    @Published private(set) var connectionType: ConnectionType = .unknown

    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "com.dropshot.networkmonitor", qos: .utility)
    private var isMonitoring = false

    private init() {}

    // MARK: - Public API

    /// Starts monitoring network path changes. Safe to call multiple times;
    /// subsequent calls are no-ops if monitoring is already active.
    func startMonitoring() {
        guard !isMonitoring else { return }
        isMonitoring = true

        monitor.pathUpdateHandler = { [weak self] path in
            guard let self = self else { return }

            let connected = (path.status == .satisfied)
            let type = Self.resolveConnectionType(from: path)

            Task { @MainActor [weak self] in
                guard let self = self else { return }
                self.isConnected = connected
                self.connectionType = type
            }
        }

        monitor.start(queue: queue)
    }

    /// Stops monitoring network path changes. Safe to call even if monitoring
    /// has not been started.
    func stopMonitoring() {
        guard isMonitoring else { return }
        monitor.cancel()
        isMonitoring = false
    }

    // MARK: - Private Helpers

    /// Determines the connection type from an NWPath by inspecting which
    /// interface types are available. The order of checks reflects priority:
    /// Wi-Fi and Ethernet are most common on macOS.
    private static func resolveConnectionType(from path: NWPath) -> ConnectionType {
        if path.usesInterfaceType(.wifi) {
            return .wifi
        } else if path.usesInterfaceType(.wiredEthernet) {
            return .wiredEthernet
        } else if path.usesInterfaceType(.cellular) {
            return .cellular
        } else {
            return .unknown
        }
    }
}
