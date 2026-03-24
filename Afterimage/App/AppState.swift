import CoreLocation
import GRDB
import SwiftUI

@MainActor @Observable
final class AppState {
    enum Screen {
        case camera
        case matching(UIImage)
        case comparison(UIImage, MatchCandidate)
    }

    var currentScreen: Screen = .camera

    let matchingService: MatchingService
    let locationService = LocationService()

    init() {
        self.matchingService = MatchingService(database: DatabaseManager.shared.dbPool)
    }

    func onPhotoCaptured(_ photo: UIImage) {
        currentScreen = .matching(photo)

        Task {
            // Get current location
            let authStatus = await locationService.requestPermission()
            guard authStatus == .authorized else {
                currentScreen = .camera
                return
            }

            // Get a single location fix
            var location: CLLocation?
            for await loc in locationService.startLocationUpdates() {
                location = loc
                break
            }

            guard let location else {
                currentScreen = .camera
                return
            }

            // Try to get heading (non-blocking — take first available or nil after 1s)
            var heading: CLHeading?
            let headingStream = locationService.startHeadingUpdates()
            let headingTask = Task<CLHeading?, Never> {
                for await h in headingStream {
                    return h
                }
                return nil
            }
            try? await Task.sleep(for: .seconds(1))
            heading = await headingTask.value
            headingTask.cancel()

            // Run matching
            await matchingService.findMatches(for: photo, at: location, heading: heading)

            // Transition based on result
            switch matchingService.state {
            case .found(let candidates):
                if let best = candidates.first {
                    currentScreen = .comparison(photo, best)
                } else {
                    currentScreen = .camera
                }
            default:
                // Stay on matching screen to show error/no-results
                break
            }
        }
    }
}
