import CoreImage
import UIKit
import Vision

enum VisionRankerError: Error {
    case invalidImage
    case noFeaturePrint
    case grayscaleFailed
}

struct VisionRanker {
    static var geoWeight: Double = 0.70
    static var visionWeight: Double = 0.30

    private static let processor = VisionProcessor()

    // MARK: - Grayscale Preprocessing

    /// Converts `image` to grayscale via CIColorControls with saturation = 0.
    static func grayscale(_ image: UIImage) -> UIImage? {
        guard let cgImage = image.cgImage else { return nil }

        guard let rendered = grayscaleCGImage(cgImage) else { return nil }
        return UIImage(cgImage: rendered, scale: image.scale, orientation: image.imageOrientation)
    }

    // MARK: - Feature Print

    /// Computes feature-print distance without sending Vision observations across
    /// concurrency domains. Vision's reference types are intentionally actor-confined.
    static func featureDistance(between first: UIImage, and second: UIImage) async throws -> Float {
        guard let firstImage = first.cgImage, let secondImage = second.cgImage else {
            throw VisionRankerError.invalidImage
        }
        return try await processor.distance(between: firstImage, and: secondImage)
    }

    // MARK: - Ranking

    /// Ranks `candidates` by composite score (geo weight + vision weight).
    ///
    /// Vision distances are computed in parallel via a task group.
    /// Candidates whose thumbnails produce no feature print are ranked by geo score only,
    /// with a vision distance of 1.0 (worst possible normalised value).
    static func rank(
        candidates: [MatchCandidate],
        userPhoto: UIImage
    ) async throws -> [MatchCandidate] {
        guard let grayUser = grayscale(userPhoto) else {
            throw VisionRankerError.grayscaleFailed
        }

        var visionDistances: [UUID: Float] = [:]
        for candidate in candidates {
            guard
                let thumbnail = candidate.thumbnail,
                let grayThumb = grayscale(thumbnail)
            else { continue }
            visionDistances[candidate.id] = (try? await featureDistance(
                between: grayUser,
                and: grayThumb
            )) ?? 1.0
        }

        var ranked = candidates.map { candidate -> MatchCandidate in
            var updated = candidate
            let rawVision = visionDistances[candidate.id] ?? 1.0
            updated.visionDistance = rawVision

            // Use absolute inputs so confidence does not change merely because another
            // candidate enters or leaves the result set. The 100 m denominator matches
            // the primary search radius; Vision distances at or above 1 are treated as
            // maximally dissimilar.
            let geoScore = min(max(candidate.distanceMeters / 100, 0), 1)
            let visionScore = min(max(Double(rawVision), 0), 1)
            let composite = geoWeight * geoScore + visionWeight * visionScore

            updated.compositeScore = composite
            updated.confidenceLabel = {
                switch composite {
                case ..<MatchCandidate.strongThreshold: return .strongMatch
                case ..<MatchCandidate.goodThreshold:   return .goodMatch
                default:                                return .nearby
                }
            }()

            return updated
        }

        ranked.sort { $0.compositeScore < $1.compositeScore }
        return ranked
    }

    // MARK: - Benchmark

    /// Logs vision distances for all candidates against `userPhoto` (for development diagnostics).
    static func runBenchmark(userPhoto: UIImage, candidates: [MatchCandidate]) async {
        guard let grayUser = grayscale(userPhoto) else {
            print("[VisionRanker] Benchmark: grayscale conversion failed for user photo")
            return
        }

        for candidate in candidates {
            guard let thumbnail = candidate.thumbnail else {
                print("[VisionRanker] Benchmark: \(candidate.photo.id) — no thumbnail")
                continue
            }

            guard
                let grayThumb = grayscale(thumbnail),
                let distance = try? await featureDistance(between: grayUser, and: grayThumb)
            else {
                print("[VisionRanker] Benchmark: \(candidate.photo.id) — feature print failed")
                continue
            }

            print("[VisionRanker] Benchmark: \(candidate.photo.id) distance=\(distance)")
        }
    }

    private static func grayscaleCGImage(_ image: CGImage) -> CGImage? {
        let ciImage = CIImage(cgImage: image)
        guard let filter = CIFilter(name: "CIColorControls") else { return nil }
        filter.setValue(ciImage, forKey: kCIInputImageKey)
        filter.setValue(0.0, forKey: kCIInputSaturationKey)
        guard let output = filter.outputImage else { return nil }
        return CIContext(options: [.useSoftwareRenderer: false])
            .createCGImage(output, from: output.extent)
    }
}

private actor VisionProcessor {
    func distance(between first: CGImage, and second: CGImage) throws -> Float {
        let firstPrint = try featurePrint(from: first)
        let secondPrint = try featurePrint(from: second)
        var distance: Float = 0
        try firstPrint.computeDistance(&distance, to: secondPrint)
        return distance
    }

    private func featurePrint(from image: CGImage) throws -> VNFeaturePrintObservation {
        let request = VNGenerateImageFeaturePrintRequest()
        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        try handler.perform([request])
        guard let observation = request.results?.first as? VNFeaturePrintObservation else {
            throw VisionRankerError.noFeaturePrint
        }
        return observation
    }
}
