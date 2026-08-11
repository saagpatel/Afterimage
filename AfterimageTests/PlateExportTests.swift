import UIKit
import XCTest
@testable import Afterimage

@MainActor
final class PlateExportTests: XCTestCase {
    private func makeExport(revealFraction: CGFloat = 0.5) -> PlateExport {
        var candidate = MatchCandidate(
            photo: HistoricalPhoto(
                id: "test-plate-001",
                source: .oldnyc,
                title: "Times Square, looking north",
                description: nil,
                dateText: "c. 1935",
                dateYear: 1935,
                lat: 40.7580,
                lon: -73.9855,
                city: "New York City",
                heading: nil,
                headingConfidence: .low,
                thumbnailURL: "test://thumbnail",
                fullResURL: nil,
                attribution: "Test attribution",
                rightsURI: nil
            ),
            distanceMeters: 24
        )
        candidate.confidenceLabel = .strongMatch

        return PlateExport(
            userPhoto: .debugProofUser,
            historicalPhoto: .debugProofHistorical,
            match: candidate,
            revealFraction: revealFraction
        )
    }

    func testRenderProducesDecodablePNGAtExportWidth() throws {
        let data = try makeExport().renderPNG()

        let image = try XCTUnwrap(UIImage(data: data), "export should decode as an image")
        // Rendered at scale 2 from a 540pt-wide canvas.
        XCTAssertEqual(image.size.width * image.scale, SharePlateView.canvasWidth * 2)
        XCTAssertGreaterThan(image.size.height, 0)

        // Opt-in snapshot for visual review:
        // TEST_RUNNER_PLATE_EXPORT_SNAPSHOT_PATH=/path/out.png xcodebuild test ...
        if let path = ProcessInfo.processInfo.environment["PLATE_EXPORT_SNAPSHOT_PATH"] {
            try data.write(to: URL(fileURLWithPath: path))
        }
    }

    func testEraLabelPrefersDateTextThenFallsBackToYear() {
        XCTAssertEqual(makeExport().match.eraLabel, "c. 1935")

        let noDateText = MatchCandidate(
            photo: HistoricalPhoto(
                id: "test-plate-002",
                source: .oldnyc,
                title: "Untitled",
                description: nil,
                dateText: nil,
                dateYear: 1902,
                lat: 0,
                lon: 0,
                city: nil,
                heading: nil,
                headingConfidence: .low,
                thumbnailURL: "test://thumbnail",
                fullResURL: nil,
                attribution: "Test",
                rightsURI: nil
            ),
            distanceMeters: 1
        )
        XCTAssertEqual(noDateText.eraLabel, "1902")
    }

    func testRenderClampsOutOfRangeRevealFraction() throws {
        // Fractions outside 0...1 must still render, clamped.
        let data = try makeExport(revealFraction: 1.7).renderPNG()
        XCTAssertNotNil(UIImage(data: data))
    }
}
