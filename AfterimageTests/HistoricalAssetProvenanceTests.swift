import Foundation
import XCTest
@testable import Afterimage

final class HistoricalAssetProvenanceTests: XCTestCase {
    func testCurrentIndexDoesNotInventLineageValues() {
        let provenance = HistoricalAssetProvenance.currentBundledIndex(
            indexRecordID: "wikimedia:123",
            headingIsPresent: false,
            headingConfidenceRawValue: "low"
        )

        XCTAssertEqual(provenance.indexRecordID, "wikimedia:123")
        XCTAssertEqual(
            provenance.sourceRecordURL,
            .unavailable(.notStoredInBundledIndex)
        )
        XCTAssertEqual(
            provenance.ingestionVersion,
            .unavailable(.notStoredInBundledIndex)
        )
        XCTAssertEqual(
            provenance.coordinateOrigin,
            .unavailable(.notStoredInBundledIndex)
        )
        XCTAssertEqual(
            provenance.coordinateConfidence,
            .unavailable(.notStoredInBundledIndex)
        )
        XCTAssertEqual(
            provenance.dateConfidence,
            .unavailable(.notStoredInBundledIndex)
        )
        XCTAssertEqual(
            provenance.rightsConfidence,
            .unavailable(.notStoredInBundledIndex)
        )
        XCTAssertEqual(
            provenance.headingConfidence,
            .unavailable(.fieldMissing)
        )
    }

    func testStoredHeadingConfidenceIsPreserved() {
        let provenance = HistoricalAssetProvenance.currentBundledIndex(
            indexRecordID: "oldnyc:456",
            headingIsPresent: true,
            headingConfidenceRawValue: "medium"
        )

        XCTAssertEqual(provenance.headingConfidence, .available(.medium))
    }

    func testUnsupportedHeadingConfidenceDoesNotBecomeKnown() {
        let provenance = HistoricalAssetProvenance.currentBundledIndex(
            indexRecordID: "fixture:unsupported",
            headingIsPresent: true,
            headingConfidenceRawValue: "very-certain"
        )

        XCTAssertEqual(
            provenance.headingConfidence,
            .unavailable(.unsupportedStoredValue)
        )
    }
}
