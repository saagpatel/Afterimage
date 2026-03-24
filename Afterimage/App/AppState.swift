import CoreLocation
import GRDB
import SwiftUI

@MainActor @Observable
final class AppState {
    enum Screen {
        case camera
        case galleryLocationPicker(UIImage)
        case matching(UIImage)
        case comparison(UIImage, MatchCandidate)
    }

    var currentScreen: Screen = .camera

    let matchingService: MatchingService
    let locationService = LocationService()

    // Stored for nearest-city calculation on no-match
    private(set) var lastMatchLocation: CLLocation?

    // City centres for all 6 target cities
    static let cityCenters: [(name: String, lat: Double, lon: Double)] = [
        ("New York City",    40.7128,  -74.0060),
        ("San Francisco",   37.7749, -122.4194),
        ("Chicago",         41.8781,  -87.6298),
        ("Washington, D.C.", 38.9072, -77.0369),
        ("New Orleans",     29.9511,  -90.0715),
        ("Boston",          42.3601,  -71.0589),
    ]

    init() {
        self.matchingService = MatchingService(database: DatabaseManager.shared.dbPool)
    }

    // MARK: - Camera flow

    func onPhotoCaptured(_ photo: UIImage) {
        currentScreen = .matching(photo)

        Task {
            let authStatus = await locationService.requestPermission()
            guard authStatus == .authorized else {
                currentScreen = .camera
                return
            }

            var location: CLLocation?
            for await loc in locationService.startLocationUpdates() {
                location = loc
                break
            }

            guard let location else {
                currentScreen = .camera
                return
            }

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

            await runMatching(photo: photo, location: location, heading: heading)
        }
    }

    // MARK: - Gallery flow

    /// Called after gallery picker successfully extracted GPS from the photo asset.
    func onGalleryPhotoWithLocation(_ photo: UIImage, location: CLLocation) {
        currentScreen = .matching(photo)
        Task {
            await runMatching(photo: photo, location: location, heading: nil)
        }
    }

    /// Called after gallery picker found no GPS — transitions to the map location picker.
    func onGalleryPhotoNeedsLocation(_ photo: UIImage) {
        currentScreen = .galleryLocationPicker(photo)
    }

    /// Called when the user has pinned a location on the map for a GPS-less gallery photo.
    func onGalleryLocationConfirmed(_ photo: UIImage, location: CLLocation) {
        currentScreen = .matching(photo)
        Task {
            // Heading filter is skipped (nil heading) for gallery photos with no EXIF orientation
            await runMatching(photo: photo, location: location, heading: nil)
        }
    }

    // MARK: - Shared matching

    private func runMatching(photo: UIImage, location: CLLocation, heading: CLHeading?) async {
        lastMatchLocation = location
        await matchingService.findMatches(for: photo, at: location, heading: heading)

        switch matchingService.state {
        case .found(let candidates):
            if let best = candidates.first {
                currentScreen = .comparison(photo, best)
            } else {
                currentScreen = .camera
            }
        default:
            break
        }
    }

    // MARK: - Nearest city

    /// Returns a human-readable description of the nearest covered city and its distance,
    /// e.g. "New York City (230 km away)". Used in the no-match state.
    func nearestCityDescription() -> String? {
        guard let location = lastMatchLocation else { return nil }
        let userLocation = location

        let nearest = Self.cityCenters.min { a, b in
            let da = CLLocation(latitude: a.lat, longitude: a.lon)
                .distance(from: userLocation)
            let db = CLLocation(latitude: b.lat, longitude: b.lon)
                .distance(from: userLocation)
            return da < db
        }

        guard let nearest else { return nil }
        let distance = CLLocation(latitude: nearest.lat, longitude: nearest.lon)
            .distance(from: userLocation)

        let km = distance / 1000
        if km < 1 {
            return nearest.name
        } else if km < 10 {
            return "\(nearest.name) (\(String(format: "%.1f", km)) km away)"
        } else {
            return "\(nearest.name) (\(Int(km)) km away)"
        }
    }
}
