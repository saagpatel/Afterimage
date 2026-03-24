import CoreLocation
import GRDB

struct SpatialQuery {
    let database: any DatabaseReader

    /// Returns historical photos within `radiusMeters` of `coordinate`, sorted by ascending distance.
    func candidates(
        near coordinate: CLLocationCoordinate2D,
        radiusMeters: Double = 100,
        limit: Int = 20
    ) async throws -> [(photo: HistoricalPhoto, distance: Double)] {
        let lat = coordinate.latitude
        let lon = coordinate.longitude

        let latDelta = radiusMeters / 111_320.0
        let lonDelta = radiusMeters / (111_320.0 * cos(lat * .pi / 180))

        let minLat = lat - latDelta
        let maxLat = lat + latDelta
        let minLon = lon - lonDelta
        let maxLon = lon + lonDelta

        let photos = try await database.read { db in
            try HistoricalPhoto
                .filter(HistoricalPhoto.Columns.lat >= minLat)
                .filter(HistoricalPhoto.Columns.lat <= maxLat)
                .filter(HistoricalPhoto.Columns.lon >= minLon)
                .filter(HistoricalPhoto.Columns.lon <= maxLon)
                .fetchAll(db)
        }

        let withDistances = photos.map { photo in
            let d = SpatialQuery.haversineDistance(
                lat1: lat, lon1: lon,
                lat2: photo.lat, lon2: photo.lon
            )
            return (photo: photo, distance: d)
        }

        return withDistances
            .filter { $0.distance <= radiusMeters }
            .sorted { $0.distance < $1.distance }
            .prefix(limit)
            .map { $0 }
    }

    /// Haversine distance in metres between two WGS-84 coordinates.
    static func haversineDistance(
        lat1: Double, lon1: Double,
        lat2: Double, lon2: Double
    ) -> Double {
        let r = 6_371_000.0
        let phi1 = lat1 * .pi / 180
        let phi2 = lat2 * .pi / 180
        let dPhi = (lat2 - lat1) * .pi / 180
        let dLambda = (lon2 - lon1) * .pi / 180

        let a = sin(dPhi / 2) * sin(dPhi / 2)
            + cos(phi1) * cos(phi2) * sin(dLambda / 2) * sin(dLambda / 2)
        let c = 2 * atan2(sqrt(a), sqrt(1 - a))
        return r * c
    }
}
