import XCTest
@testable import Afterimage

final class MatchConfidenceTests: XCTestCase {
    private func loadFixtures() throws -> [MatchCalibrationFixture] {
        let bundle = Bundle(for: MatchConfidenceTests.self)
        let url = try XCTUnwrap(
            bundle.url(forResource: "match-confidence-v1", withExtension: "json")
        )
        return try JSONDecoder().decode(
            [MatchCalibrationFixture].self,
            from: Data(contentsOf: url)
        )
    }

    func testFrozenCorpusCoversRequiredNegativeCases() throws {
        let categories = Set(try loadFixtures().map(\.category))
        let required = Set([
            "true_match",
            "near_miss",
            "wrong_location",
            "wrong_heading",
            "degraded_image",
            "missing_metadata",
            "duplicate_archive_item",
            "conflicting_signals",
            "unavailable_location",
            "no_match",
            "insufficient_evidence",
        ])
        XCTAssertTrue(required.isSubset(of: categories))
    }

    func testFixtureDispositionsAreDeterministic() throws {
        for fixture in try loadFixtures() {
            let actual = MatchConfidenceEngine.evaluate(fixture.evidence)
            XCTAssertEqual(actual.disposition, fixture.expectedDisposition, fixture.id)
        }
    }

    func testEveryKnownNegativeRefusesOverlay() throws {
        for fixture in try loadFixtures() where !fixture.isTrueMatch {
            let confidence = MatchConfidenceEngine.evaluate(fixture.evidence)
            XCTAssertFalse(confidence.mayPresentOverlay, fixture.id)
        }
    }

    func testFixtureCalibrationCeilings() throws {
        let report = MatchCalibration.measure(fixtures: try loadFixtures())
        XCTAssertGreaterThanOrEqual(report.fixtureCount, 12)
        XCTAssertLessThanOrEqual(report.fixtureBrierScore, 0.18)
        XCTAssertLessThanOrEqual(report.fixtureExpectedCalibrationError, 0.18)
        XCTAssertEqual(report.refusalRecall, 1)
        XCTAssertEqual(report.dispositionAccuracy, 1)
    }

    func testConfidenceRequiresAtLeastTwoIndependentSignals() throws {
        let fixture = try XCTUnwrap(
            loadFixtures().first { $0.id == "location-only" }
        )
        let confidence = MatchConfidenceEngine.evaluate(fixture.evidence)
        XCTAssertEqual(confidence.disposition, .insufficientEvidence)
        XCTAssertEqual(confidence.missingEvidence.sorted { $0.rawValue < $1.rawValue }, [
            .heading,
            .visualSimilarity,
        ])
    }

    func testConflictingSignalsRetainBothSidesOfExplanation() throws {
        let fixture = try XCTUnwrap(
            loadFixtures().first { $0.id == "wrong-heading" }
        )
        let confidence = MatchConfidenceEngine.evaluate(fixture.evidence)
        XCTAssertEqual(confidence.disposition, .conflictingSignals)
        XCTAssertFalse(confidence.supportingEvidence.isEmpty)
        XCTAssertFalse(confidence.contradictoryEvidence.isEmpty)
    }

    func testInvalidNumericEvidenceIsMissingRatherThanSupport() {
        let evidence = MatchEvidence(
            candidateIsAvailable: true,
            location: LocationMatchEvidence(
                isAvailable: true,
                distanceMeters: .nan,
                horizontalAccuracyMeters: -.infinity,
                searchRadiusMeters: 100
            ),
            heading: HeadingMatchEvidence(
                deltaDegrees: -10,
                userAccuracyDegrees: .infinity,
                archiveConfidence: "high"
            ),
            archive: ArchiveMatchEvidence(
                source: "fixture",
                hasAttribution: true,
                hasRightsStatement: true,
                hasDisplayImage: true,
                captureYear: 1930,
                duplicateGroupSize: 1
            ),
            visual: VisualMatchEvidence(featurePrintDistance: -.infinity)
        )

        let confidence = MatchConfidenceEngine.evaluate(evidence)
        XCTAssertEqual(confidence.disposition, .insufficientEvidence)
        XCTAssertNil(confidence.fixtureEstimatedProbability)
        XCTAssertTrue(confidence.missingEvidence.contains(.location))
        XCTAssertTrue(confidence.supportingEvidence.isEmpty)
    }

    func testInvalidOptionalSignalsRemainMissingWithValidLocation() {
        let evidence = MatchEvidence(
            candidateIsAvailable: true,
            location: LocationMatchEvidence(
                isAvailable: true,
                distanceMeters: 5,
                horizontalAccuracyMeters: -1,
                searchRadiusMeters: 100
            ),
            heading: HeadingMatchEvidence(
                deltaDegrees: 181,
                userAccuracyDegrees: 5,
                archiveConfidence: "high"
            ),
            archive: ArchiveMatchEvidence(
                source: "fixture",
                hasAttribution: true,
                hasRightsStatement: true,
                hasDisplayImage: true,
                captureYear: 1930,
                duplicateGroupSize: 1
            ),
            visual: VisualMatchEvidence(featurePrintDistance: -0.1)
        )

        let confidence = MatchConfidenceEngine.evaluate(evidence)
        XCTAssertEqual(confidence.disposition, .insufficientEvidence)
        XCTAssertTrue(confidence.missingEvidence.contains(.locationPrecision))
        XCTAssertTrue(confidence.missingEvidence.contains(.heading))
        XCTAssertTrue(confidence.missingEvidence.contains(.visualSimilarity))
        XCTAssertFalse(confidence.mayPresentOverlay)
    }

    func testHeadingAccuracyWidensTheConservativeViewpointDifference() {
        let evidence = MatchEvidence(
            candidateIsAvailable: true,
            location: LocationMatchEvidence(
                isAvailable: true,
                distanceMeters: 5,
                horizontalAccuracyMeters: 5,
                searchRadiusMeters: 100
            ),
            heading: HeadingMatchEvidence(
                deltaDegrees: 5,
                userAccuracyDegrees: 45,
                archiveConfidence: "medium"
            ),
            archive: ArchiveMatchEvidence(
                source: "fixture",
                hasAttribution: true,
                hasRightsStatement: true,
                hasDisplayImage: true,
                captureYear: 1930,
                duplicateGroupSize: 1
            ),
            visual: VisualMatchEvidence(featurePrintDistance: 0.2)
        )

        let confidence = MatchConfidenceEngine.evaluate(evidence)
        let headingFact = confidence.contradictoryEvidence.first { $0.kind == .heading }
        XCTAssertEqual(headingFact?.measuredValue, 50)
        XCTAssertEqual(headingFact?.unit, "degrees_upper_bound")
        XCTAssertEqual(confidence.disposition, .conflictingSignals)
        XCTAssertFalse(confidence.mayPresentOverlay)
    }

    func testLowConfidenceArchiveHeadingIsNotIndependentSupport() {
        let evidence = MatchEvidence(
            candidateIsAvailable: true,
            location: LocationMatchEvidence(
                isAvailable: true,
                distanceMeters: 5,
                horizontalAccuracyMeters: 5,
                searchRadiusMeters: 100
            ),
            heading: HeadingMatchEvidence(
                deltaDegrees: 1,
                userAccuracyDegrees: 1,
                archiveConfidence: "low"
            ),
            archive: ArchiveMatchEvidence(
                source: "fixture",
                hasAttribution: true,
                hasRightsStatement: true,
                hasDisplayImage: true,
                captureYear: 1930,
                duplicateGroupSize: 1
            ),
            visual: VisualMatchEvidence(featurePrintDistance: nil)
        )

        let confidence = MatchConfidenceEngine.evaluate(evidence)
        XCTAssertTrue(confidence.missingEvidence.contains(.heading))
        XCTAssertFalse(confidence.supportingEvidence.contains { $0.kind == .heading })
        XCTAssertEqual(confidence.disposition, .insufficientEvidence)
    }
}
