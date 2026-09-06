import UIKit
import XCTest
@testable import Afterimage

final class MatchExplanationPresenterTests: XCTestCase {
    func testCompleteSignalsWithViewpointConflictExplainWhyOverlayIsWithheld() throws {
        let candidate = MatchCandidate(
            photo: HistoricalPhoto(
                id: "moderate-complete",
                source: .oldnyc,
                title: "Moderate candidate",
                description: nil,
                dateText: "c. 1930",
                dateYear: 1930,
                lat: 40.758,
                lon: -73.9855,
                city: "New York City",
                heading: 0,
                headingConfidence: .medium,
                thumbnailURL: "fixture://moderate",
                fullResURL: nil,
                attribution: "Fixture archive",
                rightsURI: "https://example.com/rights"
            ),
            distanceMeters: 50,
            locationAccuracyMeters: 10,
            headingDelta: 40,
            headingAccuracyDegrees: 8,
            thumbnail: .debugProofHistorical,
            visualDistance: 0.60
        )

        XCTAssertEqual(candidate.confidence.disposition, .conflictingSignals)
        XCTAssertTrue(candidate.confidence.contradictoryEvidence.contains { $0.kind == .heading })
        XCTAssertTrue(candidate.confidence.missingEvidence.isEmpty)
        let presenter = MatchExplanationPresenter(candidate: candidate)
        XCTAssertEqual(
            presenter.primaryRefusalReason,
            "The viewpoint difference may reach 48 degrees after compass uncertainty."
        )
        let context = presenter.candidateContext
        XCTAssertTrue(context.contains("New York City"))
        XCTAssertTrue(context.contains("c. 1930"))
        XCTAssertTrue(context.contains(presenter.distanceText))

        let provenance = Dictionary(uniqueKeysWithValues:
            presenter.provenanceRows.map {
                ($0.label, $0.value)
            }
        )
        XCTAssertEqual(
            provenance["Local index ID"],
            "moderate-complete — not a source record ID"
        )
        XCTAssertEqual(provenance["Source record link"], "Not recorded in bundled index")
        XCTAssertEqual(
            provenance["Coordinate origin"],
            "Coordinates stored; origin not recorded"
        )
        XCTAssertEqual(provenance["Archive heading metadata confidence"], "Medium")
        XCTAssertEqual(
            presenter.provenanceSummary,
            "6 lineage fields are incomplete"
        )
    }

    func testConfidentCandidateHasNoRefusalReason() {
        let candidate = MatchCandidate(
            photo: HistoricalPhoto(
                id: "supported",
                source: .oldnyc,
                title: "Supported candidate",
                description: nil,
                dateText: "1935",
                dateYear: 1935,
                lat: 40.758,
                lon: -73.9855,
                city: "New York City",
                heading: 0,
                headingConfidence: .high,
                thumbnailURL: "fixture://supported",
                fullResURL: nil,
                attribution: "Fixture archive",
                rightsURI: "https://example.com/rights"
            ),
            distanceMeters: 8,
            locationAccuracyMeters: 4,
            headingDelta: 5,
            headingAccuracyDegrees: 4,
            thumbnail: .debugProofHistorical,
            visualDistance: 0.20
        )

        XCTAssertEqual(candidate.confidence.disposition, .confident)
        XCTAssertNil(MatchExplanationPresenter(candidate: candidate).primaryRefusalReason)
    }
}
