import CoreLocation
import XCTest
@testable import Afterimage

@MainActor
final class MatchingServiceTests: XCTestCase {

    // MARK: - Initial state

    func testInitialStateIsIdle() throws {
        let db = try makeTestDatabase()
        let service = MatchingService(
            database: db,
            thumbnailLoader: Self.offlineThumbnailLoader
        )
        guard case .idle = service.state else {
            XCTFail("Expected .idle, got \(service.state)")
            return
        }
    }

    // MARK: - Empty database → noResults

    func testEmptyDatabaseProducesNoResults() async throws {
        let db = try makeTestDatabase(photos: [])
        let service = MatchingService(
            database: db,
            thumbnailLoader: Self.offlineThumbnailLoader
        )

        await service.findMatches(
            for: makeTestImage(),
            at: CLLocation(latitude: 40.7580, longitude: -73.9855),
            heading: nil
        )

        guard case .noResults = service.state else {
            XCTFail("Expected .noResults for empty database, got \(service.state)")
            return
        }
    }

    // MARK: - No photos within 500m → noResults

    func testNoNearbyPhotosProducesNoResults() async throws {
        // Photo is far from Times Square — well outside both 100m and 500m radii
        let distantPhoto = makePhoto(id: "distant", lat: 40.8000, lon: -73.9000)
        let db = try makeTestDatabase(photos: [distantPhoto])
        let service = MatchingService(database: db)

        await service.findMatches(
            for: makeTestImage(),
            at: CLLocation(latitude: 40.7580, longitude: -73.9855),
            heading: nil
        )

        guard case .noResults = service.state else {
            XCTFail("Expected .noResults when no photos are within 500m, got \(service.state)")
            return
        }
    }

    // MARK: - Photos nearby — pipeline runs without crashing

    func testPipelineRunsToTerminalStateWithNearbyPhotos() async throws {
        // 3 photos within ~30m of Times Square
        let photos = [
            makePhoto(id: "ts1", lat: 40.7581, lon: -73.9855),
            makePhoto(id: "ts2", lat: 40.7579, lon: -73.9854),
            makePhoto(id: "ts3", lat: 40.7580, lon: -73.9856),
        ]
        let db = try makeTestDatabase(photos: photos)
        let service = MatchingService(
            database: db,
            thumbnailLoader: Self.offlineThumbnailLoader
        )

        await service.findMatches(
            for: makeTestImage(),
            at: CLLocation(latitude: 40.7580, longitude: -73.9855),
            heading: nil
        )

        guard case .found(let candidates) = service.state else {
            return XCTFail("Fixture-backed nearby photos should remain inspectable")
        }
        XCTAssertEqual(candidates.count, 3)
    }

    // MARK: - Heading filter is skipped for nil heading

    func testHeadingFilterSkippedWhenNoHeading() async throws {
        // Photos with explicit headings that would be filtered out if heading were applied
        let photos = [
            makePhoto(id: "h1", lat: 40.7581, lon: -73.9855, heading: 270),
            makePhoto(id: "h2", lat: 40.7579, lon: -73.9854, heading: 270),
        ]
        let db = try makeTestDatabase(photos: photos)
        let service = MatchingService(
            database: db,
            thumbnailLoader: Self.offlineThumbnailLoader
        )

        // Without a heading the evidence remains explicitly missing; the
        // candidates are preserved for inspection but cannot unlock an overlay.
        await service.findMatches(
            for: makeTestImage(),
            at: CLLocation(latitude: 40.7580, longitude: -73.9855),
            heading: nil  // no heading
        )

        // Pipeline must have completed (not stuck in searching)
        guard case .found(let candidates) = service.state else {
            return XCTFail("Expected fixture-backed candidates")
        }
        XCTAssertEqual(candidates.count, 2)
        XCTAssertTrue(candidates.allSatisfy { $0.evidence.heading.deltaDegrees == nil })
        XCTAssertTrue(candidates.allSatisfy { !$0.confidence.mayPresentOverlay })
    }

    // MARK: - 500m fallback

    func testFallbackTo500mWhenNo100mResults() async throws {
        // Place photos between 100m–500m from query point.
        // ~250m north: latDelta ≈ 250 / 111_320 ≈ 0.00225
        let photos = [
            makePhoto(id: "med1", lat: 40.7580 + 0.00225, lon: -73.9855),
            makePhoto(id: "med2", lat: 40.7580 + 0.00250, lon: -73.9855),
        ]
        let db = try makeTestDatabase(photos: photos)
        let service = MatchingService(
            database: db,
            thumbnailLoader: Self.offlineThumbnailLoader
        )

        await service.findMatches(
            for: makeTestImage(),
            at: CLLocation(latitude: 40.7580, longitude: -73.9855),
            heading: nil
        )

        guard case .found(let candidates) = service.state else {
            return XCTFail("Expected fallback candidates to remain inspectable")
        }
        XCTAssertEqual(candidates.count, 2)
        XCTAssertTrue(candidates.allSatisfy { $0.evidence.location.searchRadiusMeters == 500 })
        XCTAssertTrue(candidates.allSatisfy { !$0.confidence.mayPresentOverlay })
    }

    // MARK: - Result cap at 5

    func testResultsCappedAtFive() async throws {
        // The injected loader keeps this path deterministic and offline.
        let photos = (0..<8).map { index in
            makePhoto(
                id: "cap-\(index)",
                lat: 40.7580 + Double(index) * 0.00001,
                lon: -73.9855
            )
        }
        let db = try makeTestDatabase(photos: photos)
        let service = MatchingService(
            database: db,
            thumbnailLoader: Self.offlineThumbnailLoader
        )
        await service.findMatches(
            for: makeTestImage(),
            at: CLLocation(latitude: 40.7580, longitude: -73.9855),
            heading: nil
        )
        guard case .found(let results) = service.state else {
            return XCTFail("Expected fixture-backed results")
        }
        XCTAssertEqual(results.count, 5)
    }

    func testArchiveBrowsePreservesCandidatesWhenLoaderDropsImages() async throws {
        let photo = makePhoto(id: "archive-image-unavailable")
        let db = try makeTestDatabase(photos: [photo])
        let service = MatchingService(
            database: db,
            thumbnailLoader: { _ in [] }
        )

        await service.findMatches(
            for: makeTestImage(),
            at: CLLocation(latitude: 40.7580, longitude: -73.9855),
            heading: nil,
            mode: .archiveBrowse
        )

        guard case .found(let candidates) = service.state else {
            return XCTFail("An image-loader failure must not become no match")
        }
        let candidate = try XCTUnwrap(candidates.first)
        XCTAssertNil(candidate.thumbnail)
        XCTAssertTrue(candidate.confidence.missingEvidence.contains(.archiveImage))
        XCTAssertEqual(candidate.confidence.disposition, .insufficientEvidence)
    }

    // MARK: - Helpers

    private static let offlineThumbnailLoader: MatchingService.ThumbnailLoader = { candidates in
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 100, height: 100))
        let image = renderer.image { context in
            UIColor.gray.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 100, height: 100))
        }
        return candidates.map { candidate in
            var updated = candidate
            updated.recordThumbnail(image)
            return updated
        }
    }

    private func makeTestImage() -> UIImage {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 100, height: 100))
        return renderer.image { ctx in
            UIColor.gray.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: 100, height: 100))
        }
    }
}
