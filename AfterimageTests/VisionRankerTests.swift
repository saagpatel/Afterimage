import XCTest
@testable import Afterimage

final class VisionRankerTests: XCTestCase {

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
        // UIImage() has no CGImage backing — should return nil
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

    // MARK: - Feature print generation

    func testFeaturePrintFromValidImage() async throws {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 100, height: 100))
        let testImage = renderer.image { ctx in
            UIColor.gray.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: 100, height: 100))
        }
        // Convert to grayscale as required by the VisionRanker contract
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
            // Vision framework may also surface its own error — that is acceptable
        }
    }

    func testFeaturePrintDifferentImagesProduceDifferentVectors() async throws {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 100, height: 100))

        let blackImage = renderer.image { ctx in
            UIColor.black.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: 100, height: 100))
        }
        let whiteImage = renderer.image { ctx in
            UIColor.white.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: 100, height: 100))
        }

        guard let grayBlack = VisionRanker.grayscale(blackImage),
              let grayWhite = VisionRanker.grayscale(whiteImage) else {
            XCTFail("Grayscale conversion failed")
            return
        }

        let fpBlack = try await VisionRanker.featurePrint(from: grayBlack)
        let fpWhite = try await VisionRanker.featurePrint(from: grayWhite)

        var distance: Float = 0
        XCTAssertNoThrow(try fpBlack.computeDistance(&distance, to: fpWhite))
        // A solid black image and a solid white image should differ measurably
        XCTAssertGreaterThan(distance, 0, "Feature prints for different images should differ")
    }

    // MARK: - Ranking

    func testRankEmptyCandidates() async throws {
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
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 100, height: 100))
        let userPhoto = renderer.image { ctx in
            UIColor(white: 0.3, alpha: 1).setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: 100, height: 100))
        }

        // Two candidates with different geo distances — gives the ranker something to differentiate
        let photo1 = makePhoto(id: "near", lat: 40.7580, lon: -73.9855)
        let photo2 = makePhoto(id: "far",  lat: 40.7600, lon: -73.9900)

        var c1 = MatchCandidate(photo: photo1, distanceMeters: 10)
        var c2 = MatchCandidate(photo: photo2, distanceMeters: 200)

        // Provide thumbnails so Vision can score them
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

    func testRankAssignsVisionDistance() async throws {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 100, height: 100))
        let userPhoto = renderer.image { ctx in
            UIColor.gray.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: 100, height: 100))
        }
        let thumb = renderer.image { ctx in
            UIColor.gray.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: 100, height: 100))
        }

        let photo = makePhoto(id: "v1")
        var candidate = MatchCandidate(photo: photo, distanceMeters: 20)
        candidate.thumbnail = thumb

        let ranked = try await VisionRanker.rank(candidates: [candidate], userPhoto: userPhoto)
        XCTAssertEqual(ranked.count, 1)
        XCTAssertNotNil(ranked.first?.visionDistance, "visionDistance must be set after ranking")
    }

    func testRankCandidateWithoutThumbnailGetsWorstVisionScore() async throws {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 100, height: 100))
        let userPhoto = renderer.image { ctx in
            UIColor.gray.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: 100, height: 100))
        }
        let thumb = renderer.image { ctx in
            UIColor.gray.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: 100, height: 100))
        }

        // c1 has thumbnail, c2 does not — equal geo distance so vision score drives ranking
        let photo1 = makePhoto(id: "with-thumb")
        let photo2 = makePhoto(id: "no-thumb")
        var c1 = MatchCandidate(photo: photo1, distanceMeters: 50)
        let c2 = MatchCandidate(photo: photo2, distanceMeters: 50)
        c1.thumbnail = thumb

        let ranked = try await VisionRanker.rank(candidates: [c1, c2], userPhoto: userPhoto)
        XCTAssertEqual(ranked.count, 2)

        // Candidate without thumbnail should receive raw visionDistance of 1.0
        if let noThumbResult = ranked.first(where: { $0.photo.id == "no-thumb" }) {
            XCTAssertEqual(noThumbResult.visionDistance ?? 0, 1.0, accuracy: 0.001)
        } else {
            XCTFail("no-thumb candidate not found in results")
        }
    }

    func testRankSingleCandidateGetsStrongMatchLabel() async throws {
        // With a single candidate, normalisation collapses to 0 for both geo and vision.
        // compositeScore = 0 → strongMatch (< 0.25 threshold)
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

    func testRankCompositeScoresBoundedBetweenZeroAndOne() async throws {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 100, height: 100))
        let userPhoto = renderer.image { ctx in
            UIColor(white: 0.5, alpha: 1).setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: 100, height: 100))
        }

        let photos = (0..<3).map { i in
            makePhoto(id: "p\(i)", lat: 40.7580 + Double(i) * 0.001, lon: -73.9855)
        }
        let candidates = photos.enumerated().map { i, photo -> MatchCandidate in
            var c = MatchCandidate(photo: photo, distanceMeters: Double(i + 1) * 50)
            let thumb = renderer.image { ctx in
                UIColor(white: Double(i) / 3.0, alpha: 1).setFill()
                ctx.fill(CGRect(x: 0, y: 0, width: 100, height: 100))
            }
            c.thumbnail = thumb
            return c
        }

        let ranked = try await VisionRanker.rank(candidates: candidates, userPhoto: userPhoto)
        for candidate in ranked {
            XCTAssertGreaterThanOrEqual(candidate.compositeScore, 0.0,
                "compositeScore must be ≥ 0")
            XCTAssertLessThanOrEqual(candidate.compositeScore, 1.0,
                "compositeScore must be ≤ 1")
        }
    }
}
