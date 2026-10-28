import Foundation
import Network
import Observation

/// Tracks whether the network is usable so services can go straight to on-device engines in flight
/// instead of waiting for requests to time out.
@Observable
final class Connectivity {
    static let shared = Connectivity()
    private static let preferOnDeviceKey = "preferOnDevice"

    private(set) var isOnline = true
    var preferOnDevice: Bool {
        didSet { UserDefaults.standard.set(preferOnDevice, forKey: Self.preferOnDeviceKey) }
    }

    private let monitor = NWPathMonitor()

    private init() {
        preferOnDevice = UserDefaults.standard.bool(forKey: Self.preferOnDeviceKey)
        monitor.pathUpdateHandler = { path in
            let online = path.status == .satisfied
            Task { @MainActor in Connectivity.shared.isOnline = online }
            CloudReachability.set(online: online && !UserDefaults.standard.bool(forKey: Connectivity.preferOnDeviceKey))
        }
        monitor.start(queue: DispatchQueue(label: "pinguo.connectivity"))
    }

    var usesOnDeviceEngines: Bool { !isOnline || preferOnDevice }

    func setPreferOnDevice(_ value: Bool) {
        preferOnDevice = value
        CloudReachability.set(online: isOnline && !value)
    }
}

/// Thread-safe snapshot of whether cloud services should be tried, for actors and nonisolated code.
nonisolated enum CloudReachability {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var online = !UserDefaults.standard.bool(forKey: "preferOnDevice")

    static var shouldTryCloud: Bool {
        lock.withLock { online }
    }

    static func set(online value: Bool) {
        lock.withLock { online = value }
    }

    /// Errors that mean "no usable connection" rather than a problem with the request itself.
    static func isOffline(_ error: Error) -> Bool {
        guard let urlError = error as? URLError else { return false }
        return [.notConnectedToInternet, .networkConnectionLost, .timedOut, .cannotFindHost, .cannotConnectToHost,
                .dataNotAllowed, .internationalRoamingOff, .dnsLookupFailed, .secureConnectionFailed]
            .contains(urlError.code)
    }
}
