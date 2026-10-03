import CoreImage
import UIKit
import Vision

enum VisionRankerError: Error {
    case invalidImage
    case noFeaturePrint
    case grayscaleFailed
}

struct VisionRanker {
    // Shared CIContext — reused across calls to avoid repeated GPU context allocation
    private static let ciContext = CIContext(options: [.useSoftwareRenderer: false])

    // MARK: - Grayscale Preprocessing

    /// Converts `image` to grayscale via CIColorControls with saturation = 0.
    static func grayscale(_ image: UIImage) -> UIImage? {
        guard let cgImage = image.cgImage else { return nil }

        let ciImage = CIImage(cgImage: cgImage)

        guard let filter = CIFilter(name: "CIColorControls") else { return nil }
        filter.setValue(ciImage, forKey: kCIInputImageKey)
        filter.setValue(0.0, forKey: kCIInputSaturationKey)

        guard let output = filter.outputImage else { return nil }

        guard let rendered = ciContext.createCGImage(output, from: output.extent) else {
            return nil
        }

        return UIImage(cgImage: rendered, scale: image.scale, orientation: image.imageOrientation)
    }

    // MARK: - Feature Print

    /// Generates a `VNFeaturePrintObservation` for `image`.
    /// The caller is responsible for passing a grayscale image.
    static func featurePrint(from image: UIImage) async throws -> VNFeaturePrintObservation {
        guard let cgImage = image.cgImage else {
            throw VisionRankerError.invalidImage
        }

        return try await Task.detached {
            let request = VNGenerateImageFeaturePrintRequest()
            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            try handler.perform([request])

            guard let observation = request.results?.first as? VNFeaturePrintObservation else {
                throw VisionRankerError.noFeaturePrint
            }
            return observation
        }.value
    }

    // MARK: - Ranking

    /// Adds raw visual evidence, re-evaluates absolute confidence, and sorts by
    /// confidence. A missing/unsupported Vision descriptor remains missing
    /// evidence; it is never converted into a worst score or normalized against
    /// the current candidate set.
    static func rank(
        candidates: [MatchCandidate],
        userPhoto: UIImage
    ) async -> [MatchCandidate] {
        guard !candidates.isEmpty else { return [] }
        guard let grayUser = grayscale(userPhoto),
              let userPrint = try? await featurePrint(from: grayUser) else {
            return sortByConfidence(candidates.map { candidate in
                var updated = candidate
                updated.recordVisualDistance(nil)
                return updated
            })
        }

        // Compute vision distances in parallel
        var visionDistances: [String: Float] = [:]

        await withTaskGroup(of: (String, Float?).self) { group in
            for candidate in candidates {
                group.addTask {
                    guard let thumbnail = candidate.thumbnail else {
                        return (candidate.id, nil)
                    }
                    guard
                        let grayThumb = grayscale(thumbnail),
                        let thumbPrint = try? await featurePrint(from: grayThumb)
                    else {
                        return (candidate.id, nil)
                    }

                    var distance: Float = 0
                    guard (try? thumbPrint.computeDistance(&distance, to: userPrint)) != nil else {
                        return (candidate.id, nil)
                    }
                    return (candidate.id, distance)
                }
            }

            for await (id, distance) in group {
                if let distance {
                    visionDistances[id] = distance
                }
            }
        }

        let evaluated = candidates.map { candidate -> MatchCandidate in
            var updated = candidate
            updated.recordVisualDistance(visionDistances[candidate.id])
            return updated
        }
        return sortByConfidence(evaluated)
    }

    private static func sortByConfidence(_ candidates: [MatchCandidate]) -> [MatchCandidate] {
        candidates.sorted { left, right in
            let leftProbability = left.confidence.fixtureEstimatedProbability ?? 0
            let rightProbability = right.confidence.fixtureEstimatedProbability ?? 0
            if leftProbability == rightProbability {
                return left.distanceMeters < right.distanceMeters
            }
            return leftProbability > rightProbability
        }
    }

    // MARK: - Benchmark

    /// Logs vision distances for all candidates against `userPhoto` (for development diagnostics).
    static func runBenchmark(userPhoto: UIImage, candidates: [MatchCandidate]) async {
        guard let grayUser = grayscale(userPhoto) else {
            print("[VisionRanker] Benchmark: grayscale conversion failed for user photo")
            return
        }

        guard let userPrint = try? await featurePrint(from: grayUser) else {
            print("[VisionRanker] Benchmark: feature print failed for user photo")
            return
        }

        for candidate in candidates {
            guard let thumbnail = candidate.thumbnail else {
                print("[VisionRanker] Benchmark: \(candidate.photo.id) — no thumbnail")
                continue
            }

            guard
                let grayThumb = grayscale(thumbnail),
                let thumbPrint = try? await featurePrint(from: grayThumb)
            else {
                print("[VisionRanker] Benchmark: \(candidate.photo.id) — feature print failed")
                continue
            }

            var distance: Float = 0
            if (try? thumbPrint.computeDistance(&distance, to: userPrint)) != nil {
                print("[VisionRanker] Benchmark: \(candidate.photo.id) distance=\(distance)")
            } else {
                print("[VisionRanker] Benchmark: \(candidate.photo.id) — computeDistance failed")
            }
        }
    }
}
