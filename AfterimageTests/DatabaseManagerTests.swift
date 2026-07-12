import XCTest
import GRDB
@testable import Afterimage

final class DatabaseManagerTests: XCTestCase {

    @MainActor
    func testDatabaseLoadFailureBecomesUserVisibleState() async {
        let state = AppState(database: .failure(DatabaseManager.BundledDatabaseError.missing))

        XCTAssertNil(state.matchingService)
        await state.reportDatabaseErrorIfNeeded()
        XCTAssertEqual(state.notice?.title, "Historical Photos Unavailable")
        XCTAssertTrue(state.notice?.message.contains("missing") == true)
    }

    // MARK: - Schema

    func testSchemaCreatesTable() throws {
        let db = try makeTestDatabase()
        let tableExists = try db.read { db in
            try db.tableExists("historical_photos")
        }
        XCTAssertTrue(tableExists)
    }

    func testSchemaCreatesExpectedColumns() throws {
        let db = try makeTestDatabase()
        let columns = try db.read { db in
            try db.columns(in: "historical_photos").map(\.name)
        }
        let required = [
            "id", "source", "title", "description",
            "date_text", "date_year", "lat", "lon", "city",
            "heading", "heading_confidence",
            "thumbnail_url", "full_res_url",
            "attribution", "rights_uri", "created_at",
        ]
        for col in required {
            XCTAssertTrue(columns.contains(col), "Expected column '\(col)' not found in schema")
        }
    }

    // MARK: - Insert and fetch

    func testInsertAndFetchPhoto() throws {
        let photo = makePhoto(id: "test:1", lat: 40.75, lon: -73.98)
        let db = try makeTestDatabase(photos: [photo])

        let fetched = try db.read { db in
            try HistoricalPhoto.fetchOne(db, key: "test:1")
        }
        let f = try XCTUnwrap(fetched)
        XCTAssertEqual(f.id, "test:1")
        XCTAssertEqual(f.lat, 40.75, accuracy: 0.0001)
        XCTAssertEqual(f.lon, -73.98, accuracy: 0.0001)
    }

    func testFetchCountReturnsCorrectCount() throws {
        let photos = (0..<5).map { makePhoto(id: "p\($0)") }
        let db = try makeTestDatabase(photos: photos)

        let count = try db.read { db in
            try HistoricalPhoto.fetchCount(db)
        }
        XCTAssertEqual(count, 5)
    }

    func testInsertPreservesAllFields() throws {
        let photo = HistoricalPhoto(
            id: "full-fields",
            source: .wikimedia,
            title: "Brooklyn Bridge 1890",
            description: "Looking north from Manhattan",
            dateText: "circa 1890",
            dateYear: 1890,
            lat: 40.7061,
            lon: -73.9969,
            city: "nyc",
            heading: 45.0,
            headingConfidence: .high,
            thumbnailURL: "https://upload.wikimedia.org/thumb.jpg",
            fullResURL: "https://upload.wikimedia.org/full.jpg",
            attribution: "Library of Congress",
            rightsURI: "https://creativecommons.org/publicdomain/zero/1.0/"
        )
        let db = try makeTestDatabase(photos: [photo])

        let fetched = try db.read { db in
            try HistoricalPhoto.fetchOne(db, key: "full-fields")
        }
        let f = try XCTUnwrap(fetched)
        XCTAssertEqual(f.source, .wikimedia)
        XCTAssertEqual(f.title, "Brooklyn Bridge 1890")
        XCTAssertEqual(f.description, "Looking north from Manhattan")
        XCTAssertEqual(f.dateText, "circa 1890")
        XCTAssertEqual(f.dateYear, 1890)
        XCTAssertEqual(f.heading ?? 0, 45.0, accuracy: 0.001)
        XCTAssertEqual(f.headingConfidence, .high)
        XCTAssertEqual(f.thumbnailURL, "https://upload.wikimedia.org/thumb.jpg")
        XCTAssertEqual(f.fullResURL, "https://upload.wikimedia.org/full.jpg")
        XCTAssertEqual(f.attribution, "Library of Congress")
    }

    func testInsertPreservesNilOptionalFields() throws {
        let photo = makePhoto(id: "nil-optionals", heading: nil)
        let db = try makeTestDatabase(photos: [photo])

        let fetched = try db.read { db in
            try HistoricalPhoto.fetchOne(db, key: "nil-optionals")
        }
        XCTAssertNotNil(fetched)
        XCTAssertNil(fetched?.heading)
        XCTAssertNil(fetched?.description)
        XCTAssertNil(fetched?.dateText)
        XCTAssertNil(fetched?.dateYear)
        XCTAssertNil(fetched?.fullResURL)
        XCTAssertNil(fetched?.rightsURI)
    }

    func testEmptyDatabaseFetchCountIsZero() throws {
        let db = try makeTestDatabase(photos: [])
        let count = try db.read { db in try HistoricalPhoto.fetchCount(db) }
        XCTAssertEqual(count, 0)
    }

    // MARK: - PhotoSource enum

    func testPhotoSourceRawValues() {
        XCTAssertEqual(PhotoSource.oldnyc.rawValue, "oldnyc")
        XCTAssertEqual(PhotoSource.wikimedia.rawValue, "wikimedia")
        XCTAssertEqual(PhotoSource.flickrCommons.rawValue, "flickr_commons")
    }

    func testPhotoSourceRoundTripsInDatabase() throws {
        let sources: [PhotoSource] = [.oldnyc, .wikimedia, .flickrCommons]
        let photos = sources.enumerated().map { i, src in
            makePhoto(id: "src-\(i)", source: src)
        }
        let db = try makeTestDatabase(photos: photos)

        for (i, expectedSource) in sources.enumerated() {
            let fetched = try db.read { db in
                try HistoricalPhoto.fetchOne(db, key: "src-\(i)")
            }
            XCTAssertEqual(fetched?.source, expectedSource, "Source \(expectedSource) did not round-trip correctly")
        }
    }

    // MARK: - HeadingConfidence enum

    func testHeadingConfidenceRawValues() {
        XCTAssertEqual(HeadingConfidence.high.rawValue, "high")
        XCTAssertEqual(HeadingConfidence.medium.rawValue, "medium")
        XCTAssertEqual(HeadingConfidence.low.rawValue, "low")
    }

    func testHeadingConfidenceRoundTripsInDatabase() throws {
        let confidences: [HeadingConfidence] = [.high, .medium, .low]
        let photos = confidences.enumerated().map { i, conf in
            makePhoto(id: "conf-\(i)", headingConfidence: conf)
        }
        let db = try makeTestDatabase(photos: photos)

        for (i, expected) in confidences.enumerated() {
            let fetched = try db.read { db in
                try HistoricalPhoto.fetchOne(db, key: "conf-\(i)")
            }
            XCTAssertEqual(fetched?.headingConfidence, expected, "HeadingConfidence \(expected) did not round-trip correctly")
        }
    }

    // MARK: - MatchCandidate

    func testMatchCandidateDefaultValues() {
        let photo = makePhoto()
        let candidate = MatchCandidate(photo: photo, distanceMeters: 42.0)
        XCTAssertEqual(candidate.distanceMeters, 42.0, accuracy: 0.001)
        XCTAssertNil(candidate.headingDelta)
        XCTAssertNil(candidate.visionDistance)
        XCTAssertEqual(candidate.compositeScore, 1.0, accuracy: 0.001)
        XCTAssertEqual(candidate.confidenceLabel, .nearby)
        XCTAssertNil(candidate.thumbnail)
    }

    func testMatchCandidateHasUniqueIDs() {
        let photo = makePhoto()
        let c1 = MatchCandidate(photo: photo, distanceMeters: 10)
        let c2 = MatchCandidate(photo: photo, distanceMeters: 10)
        XCTAssertNotEqual(c1.id, c2.id, "Each MatchCandidate must have a unique UUID")
    }

    func testMatchCandidateConfidenceThresholds() {
        XCTAssertEqual(MatchCandidate.strongThreshold, 0.25, accuracy: 0.001)
        XCTAssertEqual(MatchCandidate.goodThreshold, 0.50, accuracy: 0.001)
        XCTAssertLessThan(MatchCandidate.strongThreshold, MatchCandidate.goodThreshold,
            "strongThreshold must be less than goodThreshold")
    }

    func testMatchCandidateHeadingDeltaInitialiser() {
        let photo = makePhoto(heading: 90)
        let candidate = MatchCandidate(photo: photo, distanceMeters: 25, headingDelta: 15.0)
        XCTAssertEqual(candidate.headingDelta ?? 0, 15.0, accuracy: 0.001)
    }

    // MARK: - HistoricalPhoto coordinate property

    func testCoordinateMatchesLatLon() {
        let photo = makePhoto(lat: 40.7484, lon: -73.9967)
        XCTAssertEqual(photo.coordinate.latitude, 40.7484, accuracy: 0.0001)
        XCTAssertEqual(photo.coordinate.longitude, -73.9967, accuracy: 0.0001)
    }

    func testShareCompositorProducesExpectedExportSize() {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 400, height: 300))
        let presentDay = renderer.image { context in
            UIColor.blue.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 400, height: 300))
        }
        let historical = renderer.image { context in
            UIColor.brown.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 400, height: 300))
        }

        let composite = ShareCompositor.render(
            presentDay: presentDay,
            historical: historical,
            caption: "Test attribution"
        )

        XCTAssertEqual(composite.size.width, 1_200)
        XCTAssertEqual(composite.size.height, 800)
    }
}
