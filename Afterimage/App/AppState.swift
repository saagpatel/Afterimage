import CoreLocation
import GRDB
import SwiftUI

@MainActor @Observable
final class AppState {
    enum Screen {
        case camera
        case citySelector
        case galleryLocationPicker(UIImage)
        case matching(UIImage)
        case comparison(UIImage, MatchCandidate)
    }

    var currentScreen: Screen = .camera

    let matchingService: MatchingService
    let locationService = LocationService()

    // Stored for nearest-city calculation on no-match
    private(set) var lastMatchLocation: CLLocation?

    #if DEBUG
    private var appliedDebugLaunchArguments = false
    #endif

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

    // MARK: - City browse flow

    /// Called when the user picks a city from CitySelectorView.
    /// Runs matching centred on the city with a placeholder image (browse/explore mode).
    func onCitySelected(_ city: CityInfo) {
        let location = CLLocation(latitude: city.coordinate.latitude, longitude: city.coordinate.longitude)
        let placeholderImage = UIImage.placeholderWhite
        currentScreen = .matching(placeholderImage)
        Task {
            await runMatching(photo: placeholderImage, location: location, heading: nil)
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

    // MARK: - Nearest city (no-match description)

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

#if DEBUG
extension AppState {
    func applyDebugLaunchArgumentsIfNeeded() {
        guard !appliedDebugLaunchArguments else { return }
        appliedDebugLaunchArguments = true

        guard ProcessInfo.processInfo.arguments.contains("--afterimage-demo-comparison") else {
            return
        }

        var candidate = MatchCandidate(
            photo: HistoricalPhoto(
                id: "debug-demo-nyc-001",
                source: .oldnyc,
                title: "Debug Demo: Times Square, looking north",
                description: "Synthetic simulator proof fixture.",
                dateText: "c. 1935",
                dateYear: 1935,
                lat: 40.7580,
                lon: -73.9855,
                city: "New York City",
                heading: nil,
                headingConfidence: .low,
                thumbnailURL: "debug://afterimage/demo-historical",
                fullResURL: nil,
                attribution: "Afterimage debug proof fixture",
                rightsURI: nil
            ),
            distanceMeters: 24
        )
        candidate.thumbnail = UIImage.debugProofHistorical
        candidate.compositeScore = 0.12
        candidate.confidenceLabel = .strongMatch

        currentScreen = .comparison(.debugProofUser, candidate)
    }
}
#endif

// MARK: - UIImage helpers

extension UIImage {
    /// 1×1 white image used as a placeholder when entering city browse mode (no user photo).
    static let placeholderWhite: UIImage = {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 1, height: 1))
        return renderer.image { ctx in
            UIColor.white.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: 1, height: 1))
        }
    }()

    #if DEBUG
    static let debugProofUser = debugProofImage(
        topColor: UIColor(red: 0.11, green: 0.16, blue: 0.22, alpha: 1),
        bottomColor: UIColor(red: 0.70, green: 0.82, blue: 0.95, alpha: 1),
        lineColor: .white
    )

    static let debugProofHistorical = debugProofImage(
        topColor: UIColor(red: 0.40, green: 0.32, blue: 0.22, alpha: 1),
        bottomColor: UIColor(red: 0.78, green: 0.68, blue: 0.50, alpha: 1),
        lineColor: UIColor(red: 0.20, green: 0.16, blue: 0.11, alpha: 1)
    )

    private static func debugProofImage(
        topColor: UIColor,
        bottomColor: UIColor,
        lineColor: UIColor
    ) -> UIImage {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 900, height: 675))
        return renderer.image { context in
            let cgContext = context.cgContext
            topColor.setFill()
            cgContext.fill(CGRect(x: 0, y: 0, width: 900, height: 340))
            bottomColor.setFill()
            cgContext.fill(CGRect(x: 0, y: 340, width: 900, height: 335))

            lineColor.setStroke()
            cgContext.setLineWidth(18)
            for index in 0..<7 {
                let x = CGFloat(90 + index * 120)
                cgContext.move(to: CGPoint(x: x, y: 175))
                cgContext.addLine(to: CGPoint(x: x + 60, y: 500))
                cgContext.strokePath()
            }
        }
    }
    #endif
}
