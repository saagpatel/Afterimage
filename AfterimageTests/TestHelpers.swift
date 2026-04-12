import Foundation
import GRDB
@testable import Afterimage

func makeTestDatabase(photos: [HistoricalPhoto] = []) throws -> DatabaseQueue {
    let db = try DatabaseQueue()
    try db.write { db in
        try db.execute(sql: DatabaseManager.schema)
        for photo in photos { try photo.insert(db) }
    }
    return db
}

func makePhoto(
    id: String = UUID().uuidString,
    lat: Double = 40.7580,
    lon: Double = -73.9855,
    city: String? = "nyc",
    heading: Double? = nil,
    headingConfidence: HeadingConfidence = .low,
    source: PhotoSource = .oldnyc,
    title: String = "Test Photo"
) -> HistoricalPhoto {
    HistoricalPhoto(
        id: id,
        source: source,
        title: title,
        description: nil,
        dateText: nil,
        dateYear: nil,
        lat: lat,
        lon: lon,
        city: city,
        heading: heading,
        headingConfidence: headingConfidence,
        thumbnailURL: "https://example.com/\(id)/thumb.jpg",
        fullResURL: nil,
        attribution: "Test Attribution",
        rightsURI: nil
    )
}
