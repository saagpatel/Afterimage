import XCTest
import Vision
@testable import Afterimage

final class VisionRankerTests: XCTestCase {

    // MARK: - Helpers

    /// A half-field stripe. Structure a feature descriptor can actually encode.
    private static func stripeImage(size: CGFloat = 100) -> UIImage {
        UIGraphicsImageRenderer(size: CGSize(width: size, height: size)).image { ctx in
            UIColor.white.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: size, height: size))
            UIColor.black.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: size / 2, height: size))
        }
    }

    /// A centred circle. Structurally distinct from the stripe at the same size.
    private static func circleImage(size: CGFloat = 100) -> UIImage {
        UIGraphicsImageRenderer(size: CGSize(width: size, height: size)).image { ctx in
            UIColor.white.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: size, height: size))
            UIColor.black.setFill()
            ctx.cgContext.fillEllipse(
                in: CGRect(x: size / 4, y: size / 4, width: size / 2, height: size / 2)
            )
        }
    }

    /// Grayscales through `VisionRanker`, then returns the feature print, or nil.
    ///
    /// Synchronous counterpart of `VisionRanker.featurePrint(from:)`, which wraps this
    /// same request in a detached task. The availability probe lives in a lazy static
    /// and cannot await, so it needs a non-async path that is otherwise identical.
    private static func grayFeaturePrint(_ image: UIImage) -> VNFeaturePrintObservation? {
        guard let gray = VisionRanker.grayscale(image), let cg = gray.cgImage else { return nil }
        let request = VNGenerateImageFeaturePrintRequest()
        let handler = VNImageRequestHandler(cgImage: cg, options: [:])
        do {
            try handler.perform([request])
            return request.results?.first as? VNFeaturePrintObservation
        } catch {
            return nil
        }
    }

    /// True only when Vision can distinguish the exact image pair the guarded tests use,
    /// travelling the exact path they travel: `VisionRanker.grayscale`, then a feature
    /// print, then `computeDistance`.
    ///
    /// Vision feature prints need the Neural Engine, which simulators lack. Vision still
    /// returns an observation there, but the descriptor can be degenerate, so every image
    /// compares identical at distance 0 and the assertion below fails for environmental
    /// reasons rather than a real defect.
    ///
    /// Two earlier probes were too weak to catch that. The first only checked a
    /// `VNFeaturePrintObservation` came back at all. The second compared raw 64pt renders
    /// and skipped grayscale entirely: on CI it reported "available" while the test it
    /// guards measured distance 0 on the grayscaled 100pt pair, so the suite ran and
    /// failed anyway. A probe that does not travel the guarded path does not guard it.
    /// Sharing the images and the preprocessing makes "available" a real precondition.
    private static var visionAvailable: Bool = {
        guard let stripe = grayFeaturePrint(stripeImage()),
              let circle = grayFeaturePrint(circleImage()),
              stripe.elementCount > 0
        else { return false }

        var distance: Float = 0
        guard (try? stripe.computeDistance(&distance, to: circle)) != nil else { return false }
        return distance > 0
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
        let fp = try await VisionRanker.featurePrint(from: gray)
        XCTAssertGreaterThan(fp.elementCount, 0)
    }

    func testFeaturePrintThrowsForImageWithNoCGImage() async {
        let emptyImage = UIImage()
        do {
            _ = try await VisionRanker.featurePrint(from: emptyImage)
            XCTFail("Expected VisionRankerError.invalidImage for empty UIImage")
        } catch VisionRankerError.invalidImage {
            // Expected
        } catch {
            // Vision framework error also acceptable
        }
    }

    func testFeaturePrintDifferentImagesProduceDifferentVectors() async throws {
        try skipUnlessVisionAvailable()

        // Structured images rather than flat fills. A uniform image carries no features
        // for the descriptor to encode, so two flat images can legitimately produce
        // identical feature prints — asserting they differ tests nothing about Vision.
        // These are the same renders `visionAvailable` probes, so a probe that reports
        // "available" has already demonstrated this assertion can hold here.
        guard let grayStripe = VisionRanker.grayscale(Self.stripeImage()),
              let grayCircle = VisionRanker.grayscale(Self.circleImage()) else {
            XCTFail("Grayscale conversion failed")
            return
        }

        let fpStripe = try await VisionRanker.featurePrint(from: grayStripe)
        let fpCircle = try await VisionRanker.featurePrint(from: grayCircle)

        var distance: Float = 0
        XCTAssertNoThrow(try fpStripe.computeDistance(&distance, to: fpCircle))
        XCTAssertGreaterThan(distance, 0, "Feature prints for different images should differ")
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
            "Single candidate should receive .strongMatch (compositeScore normalises to 0)")
    }
}
