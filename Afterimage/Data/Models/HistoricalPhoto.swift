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

extension HistoricalPhoto {
    /// Provenance values that can be stated without changing or rebuilding the
    /// currently bundled database. Unknown lineage is never synthesized.
    var provenance: HistoricalAssetProvenance {
        .currentBundledIndex(
            indexRecordID: id,
            headingIsPresent: heading != nil,
            headingConfidenceRawValue: headingConfidence.rawValue
        )
    }
}

// MARK: - Match Types

/// A candidate is the archive record plus observed evidence and an evaluated
/// confidence decision. UI strings live in MatchExplanationPresenter.
struct MatchCandidate: Identifiable {
    var id: String { photo.id }
    let photo: HistoricalPhoto
    var thumbnail: UIImage?
    private(set) var evidence: MatchEvidence
    private(set) var confidence: MatchConfidence

    var distanceMeters: Double { evidence.location.distanceMeters ?? .infinity }
    var headingDelta: Double? { evidence.heading.deltaDegrees }
    var visionDistance: Float? {
        evidence.visual.featurePrintDistance.map(Float.init)
    }

    init(
        photo: HistoricalPhoto,
        distanceMeters: Double,
        locationAccuracyMeters: Double? = nil,
        searchRadiusMeters: Double = 100,
        headingDelta: Double? = nil,
        headingAccuracyDegrees: Double? = nil,
        duplicateGroupSize: Int = 1,
        thumbnail: UIImage? = nil,
        visualDistance: Double? = nil
    ) {
        self.photo = photo
        self.thumbnail = thumbnail
        self.evidence = MatchEvidence(
            candidateIsAvailable: true,
            location: LocationMatchEvidence(
                isAvailable: true,
                distanceMeters: distanceMeters,
                horizontalAccuracyMeters: locationAccuracyMeters.flatMap { value in
                    value.isFinite && value >= 0 ? value : nil
                },
                searchRadiusMeters: searchRadiusMeters
            ),
            heading: HeadingMatchEvidence(
                deltaDegrees: headingDelta,
                userAccuracyDegrees: headingAccuracyDegrees,
                archiveConfidence: photo.headingConfidence.rawValue
            ),
            archive: ArchiveMatchEvidence(
                source: photo.source.rawValue,
                hasAttribution: !photo.attribution.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                hasRightsStatement: !(photo.rightsURI ?? "")
                    .trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                hasDisplayImage: thumbnail != nil,
                captureYear: photo.dateYear,
                duplicateGroupSize: max(duplicateGroupSize, 1)
            ),
            visual: VisualMatchEvidence(featurePrintDistance: visualDistance)
        )
        self.confidence = MatchConfidenceEngine.evaluate(evidence)
    }

    mutating func recordHeading(deltaDegrees: Double?, userAccuracyDegrees: Double?) {
        evidence = MatchEvidence(
            candidateIsAvailable: evidence.candidateIsAvailable,
            location: evidence.location,
            heading: HeadingMatchEvidence(
                deltaDegrees: deltaDegrees,
                userAccuracyDegrees: userAccuracyDegrees,
                archiveConfidence: evidence.heading.archiveConfidence
            ),
            archive: evidence.archive,
            visual: evidence.visual
        )
        refreshConfidence()
    }

    mutating func recordVisualDistance(_ distance: Float?) {
        evidence = MatchEvidence(
            candidateIsAvailable: evidence.candidateIsAvailable,
            location: evidence.location,
            heading: evidence.heading,
            archive: evidence.archive,
            visual: VisualMatchEvidence(featurePrintDistance: distance.map(Double.init))
        )
        refreshConfidence()
    }

    mutating func recordThumbnail(_ image: UIImage?) {
        thumbnail = image
        evidence = MatchEvidence(
            candidateIsAvailable: evidence.candidateIsAvailable,
            location: evidence.location,
            heading: evidence.heading,
            archive: ArchiveMatchEvidence(
                source: evidence.archive.source,
                hasAttribution: evidence.archive.hasAttribution,
                hasRightsStatement: evidence.archive.hasRightsStatement,
                hasDisplayImage: image != nil,
                captureYear: evidence.archive.captureYear,
                duplicateGroupSize: evidence.archive.duplicateGroupSize
            ),
            visual: evidence.visual
        )
        refreshConfidence()
    }

    mutating func recordDuplicateGroupSize(_ count: Int) {
        evidence = MatchEvidence(
            candidateIsAvailable: evidence.candidateIsAvailable,
            location: evidence.location,
            heading: evidence.heading,
            archive: ArchiveMatchEvidence(
                source: evidence.archive.source,
                hasAttribution: evidence.archive.hasAttribution,
                hasRightsStatement: evidence.archive.hasRightsStatement,
                hasDisplayImage: evidence.archive.hasDisplayImage,
                captureYear: evidence.archive.captureYear,
                duplicateGroupSize: max(count, 1)
            ),
            visual: evidence.visual
        )
        refreshConfidence()
    }

    private mutating func refreshConfidence() {
        confidence = MatchConfidenceEngine.evaluate(evidence)
    }
}
