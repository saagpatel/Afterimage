import CoreLocation

@MainActor
final class LocationService: NSObject, CLLocationManagerDelegate {

    enum AuthStatus {
        case notDetermined, authorized, denied
    }

    private let locationManager = CLLocationManager()
    private(set) var authStatus: AuthStatus = .notDetermined
    private var permissionContinuation: CheckedContinuation<AuthStatus, Never>?
    private var headingContinuation: AsyncStream<CLHeading>.Continuation?

    override init() {
        super.init()
        locationManager.delegate = self
        updateAuthStatus()
    }

    // MARK: - Permission

    func requestPermission() async -> AuthStatus {
        switch authStatus {
        case .authorized, .denied:
            return authStatus
        case .notDetermined:
            return await withCheckedContinuation { continuation in
                self.permissionContinuation = continuation
                self.locationManager.requestWhenInUseAuthorization()
            }
        }
    }

    // MARK: - Location Updates

    func startLocationUpdates() -> AsyncStream<CLLocation> {
        AsyncStream { continuation in
            Task {
                do {
                    for try await update in CLLocationUpdate.liveUpdates(.default) {
                        guard let location = update.location else { continue }
                        let accuracy = location.horizontalAccuracy
                        guard accuracy >= 0, accuracy < 100 else { continue }
                        continuation.yield(location)
                    }
                } catch {
                    continuation.finish()
                }
            }
        }
    }

    // MARK: - Heading Updates

    func startHeadingUpdates() -> AsyncStream<CLHeading> {
        AsyncStream { continuation in
            self.headingContinuation = continuation
            self.locationManager.startUpdatingHeading()
            continuation.onTermination = { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.locationManager.stopUpdatingHeading()
                    self?.headingContinuation = nil
                }
            }
        }
    }

    // MARK: - Stop

    func stop() {
        locationManager.stopUpdatingLocation()
        locationManager.stopUpdatingHeading()
        headingContinuation?.finish()
        headingContinuation = nil
    }

    // MARK: - Private

    private func updateAuthStatus() {
        switch locationManager.authorizationStatus {
        case .notDetermined:
            authStatus = .notDetermined
        case .authorizedWhenInUse, .authorizedAlways:
            authStatus = .authorized
        case .denied, .restricted:
            authStatus = .denied
        @unknown default:
            authStatus = .denied
        }
    }

    // MARK: - CLLocationManagerDelegate

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            self.updateAuthStatus()
            if let continuation = self.permissionContinuation {
                self.permissionContinuation = nil
                continuation.resume(returning: self.authStatus)
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateHeading newHeading: CLHeading) {
        Task { @MainActor in
            self.headingContinuation?.yield(newHeading)
        }
    }
}
