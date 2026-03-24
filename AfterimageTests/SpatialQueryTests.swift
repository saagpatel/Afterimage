import CoreLocation
import XCTest
@testable import Afterimage

final class SpatialQueryTests: XCTestCase {

    // MARK: - Haversine Unit Tests

    func testHaversineTimesSquareToEmpireState() {
        // Times Square: 40.7580, -73.9855
        // Empire State Building: 40.7484, -73.9967
        let distance = SpatialQuery.haversineDistance(
            lat1: 40.7580, lon1: -73.9855,
            lat2: 40.7484, lon2: -73.9967
        )
        XCTAssertEqual(distance, 1425, accuracy: 15,
            "Times Square → Empire State should be ~1425m ±15m, got \(distance)m")
    }

    func testHaversineSamePoint() {
        let distance = SpatialQuery.haversineDistance(
            lat1: 40.7580, lon1: -73.9855,
            lat2: 40.7580, lon2: -73.9855
        )
        XCTAssertEqual(distance, 0, accuracy: 0.001,
            "Same point should produce 0 distance")
    }

    func testHaversineAntipodal() {
        // Antipodal points are ~20,015 km apart (half the great-circle circumference)
        let distance = SpatialQuery.haversineDistance(
            lat1: 0, lon1: 0,
            lat2: 0, lon2: 180
        )
        let expectedKm = 20_015.0
        XCTAssertEqual(distance / 1000, expectedKm, accuracy: 10,
            "Antipodal points should be ~20,015 km apart, got \(distance / 1000) km")
    }

    // MARK: - Bounding Box Query Tests

    func testBoundingBoxReturnsNearby() async throws {
        // Centre: Times Square
        let centre = CLLocationCoordinate2D(latitude: 40.7580, longitude: -73.9855)

        // 5 photos within 100 m (offset ~50 m north/south along ~0.00045 deg)
        var photos: [HistoricalPhoto] = []
        for i in 0..<5 {
            photos.append(makePhoto(
                id: "near-\(i)",
                lat: 40.7580 + Double(i) * 0.0002,   // ~22 m per step
                lon: -73.9855
            ))
        }
        // 5 photos outside 100 m (offset ~200 m)
        for i in 0..<5 {
            photos.append(makePhoto(
                id: "far-\(i)",
                lat: 40.7580 + 0.003 + Double(i) * 0.001,
                lon: -73.9855
            ))
        }

        let db = try makeTestDatabase(photos: photos)
        let query = SpatialQuery(database: db)
        let results = try await query.candidates(near: centre, radiusMeters: 100, limit: 20)

        XCTAssertEqual(results.count, 5, "Should return only the 5 nearby photos")
    }

    func testBoundingBoxSorted() async throws {
        let centre = CLLocationCoordinate2D(latitude: 40.7580, longitude: -73.9855)

        // 3 photos at increasing distances from centre
        let photos = [
            makePhoto(id: "a", lat: 40.7582, lon: -73.9855),  // closest
            makePhoto(id: "b", lat: 40.7584, lon: -73.9855),
            makePhoto(id: "c", lat: 40.7586, lon: -73.9855),  // farthest (but still <100m)
        ]

        let db = try makeTestDatabase(photos: photos)
        let query = SpatialQuery(database: db)
        let results = try await query.candidates(near: centre, radiusMeters: 100, limit: 20)

        XCTAssertEqual(results.count, 3)
        for i in 0..<(results.count - 1) {
            XCTAssertLessThanOrEqual(results[i].distance, results[i + 1].distance,
                "Results should be sorted by ascending distance")
        }
        XCTAssertEqual(results.first?.photo.id, "a", "Closest photo should come first")
    }

    func testBoundingBoxLimit() async throws {
        let centre = CLLocationCoordinate2D(latitude: 40.7580, longitude: -73.9855)

        // 30 photos all within a few metres of centre
        let photos = (0..<30).map { i in
            makePhoto(
                id: "p-\(i)",
                lat: 40.7580 + Double(i) * 0.00001,  // ~1.1 m steps
                lon: -73.9855
            )
        }

        let db = try makeTestDatabase(photos: photos)
        let query = SpatialQuery(database: db)
        let results = try await query.candidates(near: centre, radiusMeters: 100, limit: 20)

        XCTAssertEqual(results.count, 20, "Should respect limit of 20")
    }

    func testBoundingBoxEmpty() async throws {
        let db = try makeTestDatabase(photos: [])
        let query = SpatialQuery(database: db)
        let results = try await query.candidates(
            near: CLLocationCoordinate2D(latitude: 40.7580, longitude: -73.9855),
            radiusMeters: 100,
            limit: 20
        )
        XCTAssertTrue(results.isEmpty, "Empty database should return no results")
    }

    func testBoundingBoxEdge() async throws {
        // A photo placed exactly at the boundary (100 m north)
        let centre = CLLocationCoordinate2D(latitude: 40.7580, longitude: -73.9855)
        let latDelta = 100.0 / 111_320.0   // exactly 100 m in degrees
        let boundaryLat = 40.7580 + latDelta

        let photo = makePhoto(id: "boundary", lat: boundaryLat, lon: -73.9855)
        let db = try makeTestDatabase(photos: [photo])
        let query = SpatialQuery(database: db)

        let results = try await query.candidates(near: centre, radiusMeters: 100, limit: 20)

        // The bounding-box filter uses <=, so the photo must pass the box check.
        // The Haversine distance will be very close to 100 m; the post-filter uses <=.
        // We only assert that we got exactly one result and its distance is ≤ 100 m.
        XCTAssertEqual(results.count, 1, "Photo exactly at boundary should be included")
        if let result = results.first {
            XCTAssertLessThanOrEqual(result.distance, 100,
                "Distance should be ≤ 100 m for boundary photo")
        }
    }
}
