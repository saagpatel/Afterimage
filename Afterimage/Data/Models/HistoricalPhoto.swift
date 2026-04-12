import GRDB
import CoreLocation
import UIKit

// MARK: - Database Enums

enum PhotoSource: String, Codable, DatabaseValueConvertible {
    case oldnyc
    case wikimedia
    case flickrCommons = "flickr_commons"
}

enum HeadingConfidence: String, Codable, DatabaseValueConvertible {
    case high, medium, low
}

// MARK: - HistoricalPhoto (GRDB Record)

struct HistoricalPhoto: Codable, FetchableRecord, PersistableRecord, Identifiable {
    static let databaseTableName = "historical_photos"

    let id: String
    let source: PhotoSource
    let title: String
    let description: String?
    let dateText: String?
    let dateYear: Int?
    let lat: Double
    let lon: Double
    let city: String?
    let heading: Double?
    let headingConfidence: HeadingConfidence
    let thumbnailURL: String
    let fullResURL: String?
    let attribution: String
    let rightsURI: String?

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: lat, longitude: lon)
    }

    enum CodingKeys: String, CodingKey, ColumnExpression {
        case id, source, title, description
        case dateText = "date_text"
        case dateYear = "date_year"
        case lat, lon, city, heading
        case headingConfidence = "heading_confidence"
        case thumbnailURL = "thumbnail_url"
        case fullResURL = "full_res_url"
        case attribution
        case rightsURI = "rights_uri"
    }
}

extension HistoricalPhoto {
    enum Columns {
        static let lat = Column(CodingKeys.lat)
        static let lon = Column(CodingKeys.lon)
        static let city = Column(CodingKeys.city)
        static let heading = Column(CodingKeys.heading)
    }
}

// MARK: - Match Types

enum ConfidenceLabel: String {
    case strongMatch = "Strong Match"
    case goodMatch = "Good Match"
    case nearby = "Nearby"
}

struct MatchCandidate: Identifiable {
    let id: UUID
    let photo: HistoricalPhoto
    let distanceMeters: Double
    var headingDelta: Double?
    var visionDistance: Float?
    var compositeScore: Double
    var confidenceLabel: ConfidenceLabel
    var thumbnail: UIImage?

    static let strongThreshold: Double = 0.25
    static let goodThreshold: Double = 0.50

    init(
        photo: HistoricalPhoto,
        distanceMeters: Double,
        headingDelta: Double? = nil
    ) {
        self.id = UUID()
        self.photo = photo
        self.distanceMeters = distanceMeters
        self.headingDelta = headingDelta
        self.visionDistance = nil
        self.compositeScore = 1.0
        self.confidenceLabel = .nearby
        self.thumbnail = nil
    }
}
