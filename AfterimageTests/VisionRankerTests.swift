import XCTest
import Vision
@testable import Afterimage

final class VisionRankerTests: XCTestCase {

    // MARK: - Helpers

    /// Vision feature print requires Neural Engine / ANE — not available on all simulators.
    /// Returns true if Vision can generate a feature print on this device.
    private static var visionAvailable: Bool = {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 50, height: 50))
        let img = renderer.image { ctx in
            UIColor.gray.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: 50, height: 50))
        }
        guard let cg = img.cgImage else { return false }
        let request = VNGenerateImageFeaturePrintRequest()
        let handler = VNImageRequestHandler(cgImage: cg, options: [:])
        do {
            try handler.perform([request])
            return request.results?.first is VNFeaturePrintObservation
        } catch {
            return false
        }
    }()

    private func skipUnlessVisionAvailable() throws {
        try XCTSkipUnless(Self.visionAvailable, "Vision feature print unavailable on this simulator")
    }

    // MARK: - Grayscale conversion

    func testGrayscaleReturnsImageOfSameSize() {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 10, height: 10))
        let colorImage = renderer.image { ctx in
            UIColor.red.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: 10, height: 10))
        }
        let gray = VisionRanker.grayscale(colorImage)
        XCTAssertNotNil(gray)
        XCTAssertEqual(gray?.size.width, 10)
        XCTAssertEqual(gray?.size.height, 10)
    }

    func testGrayscalePreservesScale() {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 20, height: 30))
        let image = renderer.image { ctx in
            UIColor.green.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: 20, height: 30))
        }
        let gray = VisionRanker.grayscale(image)
        XCTAssertNotNil(gray)
        XCTAssertEqual(gray?.size.width, 20)
        XCTAssertEqual(gray?.size.height, 30)
        XCTAssertEqual(gray?.scale, image.scale)
    }

    func testGrayscaleReturnsNilForImageWithNoCGImage() {
        let emptyImage = UIImage()
        let result = VisionRanker.grayscale(emptyImage)
        XCTAssertNil(result)
    }

    func testGrayscaleOutputHasCGImage() {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 8, height: 8))
        let source = renderer.image { ctx in
            UIColor.blue.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: 8, height: 8))
        }
        let gray = VisionRanker.grayscale(source)
        XCTAssertNotNil(gray?.cgImage, "Grayscale result must have a CGImage for Vision processing")
    }

    // MARK: - Composite score weights

    func testWeightsSumToOne() {
        XCTAssertEqual(VisionRanker.geoWeight + VisionRanker.visionWeight, 1.0, accuracy: 0.001)
    }

    func testDefaultGeoWeight() {
        XCTAssertEqual(VisionRanker.geoWeight, 0.70, accuracy: 0.001)
    }

    func testDefaultVisionWeight() {
        XCTAssertEqual(VisionRanker.visionWeight, 0.30, accuracy: 0.001)
    }

    // MARK: - Feature print generation (requires Neural Engine)

    func testFeaturePrintFromValidImage() async throws {
        try skipUnlessVisionAvailable()
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 100, height: 100))
        let testImage = renderer.image { ctx in
            UIColor.gray.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: 100, height: 100))
        }
        guard let gray = VisionRanker.grayscale(testImage) else {
            XCTFail("Grayscale conversion failed in test setup")
            return
        }
        let distance = try await VisionRanker.featureDistance(between: gray, and: gray)
        XCTAssertEqual(distance, 0, accuracy: 0.0001)
    }

    func testFeaturePrintThrowsForImageWithNoCGImage() async {
        let emptyImage = UIImage()
        do {
            _ = try await VisionRanker.featureDistance(between: emptyImage, and: emptyImage)
            XCTFail("Expected VisionRankerError.invalidImage for empty UIImage")
        } catch VisionRankerError.invalidImage {
            // Expected
        } catch {
            // Vision framework error also acceptable
        }
    }

    func testFeaturePrintDistanceForDifferentImagesIsFiniteAndNonnegative() async throws {
        try skipUnlessVisionAvailable()
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 100, height: 100))

        let verticalBars = renderer.image { ctx in
            UIColor.white.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: 100, height: 100))
            UIColor.black.setFill()
            for x in stride(from: CGFloat(0), to: 100, by: 20) {
                ctx.fill(CGRect(x: x, y: 0, width: 10, height: 100))
            }
        }
        let concentricSquares = renderer.image { ctx in
            UIColor.white.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: 100, height: 100))
            UIColor.black.setStroke()
            ctx.cgContext.setLineWidth(6)
            for inset in stride(from: CGFloat(8), through: 38, by: 10) {
                ctx.cgContext.stroke(CGRect(x: inset, y: inset, width: 100 - inset * 2, height: 100 - inset * 2))
            }
        }

        guard let grayBars = VisionRanker.grayscale(verticalBars),
              let graySquares = VisionRanker.grayscale(concentricSquares) else {
            XCTFail("Grayscale conversion failed")
            return
        }

        let distance = try await VisionRanker.featureDistance(between: grayBars, and: graySquares)
        XCTAssertTrue(distance.isFinite)
        XCTAssertGreaterThanOrEqual(distance, 0)
    }

    // MARK: - Ranking

    func testRankEmptyCandidates() async throws {
        try skipUnlessVisionAvailable()
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 10, height: 10))
        let userPhoto = renderer.image { ctx in
            UIColor.gray.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: 10, height: 10))
        }
        let ranked = try await VisionRanker.rank(candidates: [], userPhoto: userPhoto)
        XCTAssertTrue(ranked.isEmpty)
    }

    func testRankThrowsForInvalidUserPhoto() async {
        let emptyImage = UIImage()
        let photo = makePhoto(id: "r1")
        let candidate = MatchCandidate(photo: photo, distanceMeters: 10)

        do {
            _ = try await VisionRanker.rank(candidates: [candidate], userPhoto: emptyImage)
            XCTFail("Expected VisionRankerError.grayscaleFailed for empty user photo")
        } catch VisionRankerError.grayscaleFailed {
            // Expected
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }
    }

    func testRankResultsSortedAscendingByCompositeScore() async throws {
        try skipUnlessVisionAvailable()
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 100, height: 100))
        let userPhoto = renderer.image { ctx in
            UIColor(white: 0.3, alpha: 1).setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: 100, height: 100))
        }

        let photo1 = makePhoto(id: "near", lat: 40.7580, lon: -73.9855)
        let photo2 = makePhoto(id: "far",  lat: 40.7600, lon: -73.9900)

        var c1 = MatchCandidate(photo: photo1, distanceMeters: 10)
        var c2 = MatchCandidate(photo: photo2, distanceMeters: 200)

        let thumb = renderer.image { ctx in
            UIColor(white: 0.3, alpha: 1).setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: 100, height: 100))
        }
        c1.thumbnail = thumb
        c2.thumbnail = thumb

        let ranked = try await VisionRanker.rank(candidates: [c2, c1], userPhoto: userPhoto)

        XCTAssertEqual(ranked.count, 2)
        guard ranked.count == 2 else { return }
        XCTAssertLessThanOrEqual(
            ranked[0].compositeScore,
            ranked[1].compositeScore,
            "Results must be sorted ascending by compositeScore"
        )
    }

    func testRankSingleCandidateGetsStrongMatchLabel() async throws {
        try skipUnlessVisionAvailable()
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 100, height: 100))
        let userPhoto = renderer.image { ctx in
            UIColor.gray.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: 100, height: 100))
        }
        let thumb = renderer.image { ctx in
            UIColor.gray.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: 100, height: 100))
        }

        let photo = makePhoto(id: "solo")
        var candidate = MatchCandidate(photo: photo, distanceMeters: 15)
        candidate.thumbnail = thumb

        let ranked = try await VisionRanker.rank(candidates: [candidate], userPhoto: userPhoto)
        XCTAssertEqual(ranked.count, 1)
        XCTAssertEqual(ranked.first?.confidenceLabel, .strongMatch,
            "A nearby visually identical candidate should receive .strongMatch")
    }

    func testConfidenceDoesNotDependOnOtherCandidates() async throws {
        try skipUnlessVisionAvailable()
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 100, height: 100))
        let image = renderer.image { context in
            UIColor.gray.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 100, height: 100))
        }

        let targetPhoto = makePhoto(id: "target")
        var target = MatchCandidate(photo: targetPhoto, distanceMeters: 20)
        target.thumbnail = image

        let alone = try await VisionRanker.rank(candidates: [target], userPhoto: image)

        let distractorPhoto = makePhoto(id: "distractor")
        var distractor = MatchCandidate(photo: distractorPhoto, distanceMeters: 95)
        distractor.thumbnail = image
        let withDistractor = try await VisionRanker.rank(
            candidates: [target, distractor],
            userPhoto: image
        )

        let targetWithDistractor = try XCTUnwrap(withDistractor.first { $0.photo.id == "target" })
        XCTAssertEqual(
            alone.first?.compositeScore ?? -1,
            targetWithDistractor.compositeScore,
            accuracy: 0.0001
        )
        XCTAssertEqual(alone.first?.confidenceLabel, targetWithDistractor.confidenceLabel)
    }
}
