import CoreLocation
import XCTest
@testable import Afterimage

@MainActor
final class AppStateLifecycleTests: XCTestCase {
    private final class FakeLocationService: LocationProviding {
        let authorization: LocationService.AuthStatus
        let locations: [CLLocation]
        private(set) var stopCallCount = 0

        init(
            authorization: LocationService.AuthStatus,
            locations: [CLLocation] = []
        ) {
            self.authorization = authorization
            self.locations = locations
        }

        func refreshAuthorization() {}

        func requestPermission() async -> LocationService.AuthStatus {
            authorization
        }

        func startLocationUpdates() -> AsyncStream<CLLocation> {
            AsyncStream { continuation in
                for location in locations {
                    continuation.yield(location)
                }
                continuation.finish()
            }
        }

        func startHeadingUpdates() -> AsyncStream<CLHeading> {
            AsyncStream { _ in }
        }

        func stop() {
            stopCallCount += 1
        }
    }

    func testDeniedLocationPreservesARecoveryPath() async {
        let service = FakeLocationService(authorization: .denied)
        let state = AppState(locationService: service)

        let context = await state.acquireCaptureContext()

        guard case .recovery(let message) = context else {
            return XCTFail("denied location must produce recovery")
        }
        XCTAssertTrue(message.contains("manually"))
    }

    func testMissingHeadingFinishesWithinTheConfiguredDeadline() async {
        let service = FakeLocationService(
            authorization: .authorized,
            locations: [CLLocation(latitude: 40.758, longitude: -73.9855)]
        )
        let state = AppState(
            locationService: service,
            locationTimeout: .milliseconds(50),
            headingTimeout: .milliseconds(20)
        )

        let context = await state.acquireCaptureContext()

        guard case .ready(_, let heading) = context else {
            return XCTFail("location should allow matching without a heading")
        }
        XCTAssertNil(heading)
        XCTAssertEqual(service.stopCallCount, 1)
    }
}
