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

        return try await withCheckedThrowingContinuation { continuation in
            let request = VNGenerateImageFeaturePrintRequest { request, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                guard let observation = request.results?.first as? VNFeaturePrintObservation else {
                    continuation.resume(throwing: VisionRankerError.noFeaturePrint)
                    return
                }
                continuation.resume(returning: observation)
            }

            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            do {
                try handler.perform([request])
            } catch {
                continuation.resume(throwing: error)
            }
        }
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

        let userPrint = try await featurePrint(from: grayUser)

        // Compute vision distances in parallel
        var visionDistances: [UUID: Float] = [:]

        await withTaskGroup(of: (UUID, Float).self) { group in
            for candidate in candidates {
                guard let thumbnail = candidate.thumbnail else { continue }

                group.addTask {
                    guard
                        let grayThumb = grayscale(thumbnail),
                        let thumbPrint = try? await featurePrint(from: grayThumb)
                    else {
                        return (candidate.id, 1.0)
                    }

                    var distance: Float = 0
                    // computeDistance(to:) is a throwing function
                    guard (try? thumbPrint.computeDistance(&distance, to: userPrint)) != nil else {
                        return (candidate.id, 1.0)
                    }
                    return (candidate.id, distance)
                }
            }

            for await (id, dist) in group {
                visionDistances[id] = dist
            }
        }

        // Normalise vision distances to [0, 1]
        let allDistances = visionDistances.values
        let maxDist = allDistances.max() ?? 1.0
        let minDist = allDistances.min() ?? 0.0
        let distRange = maxDist - minDist

        // Normalise geo distances to [0, 1]
        let maxGeo = candidates.map(\.distanceMeters).max() ?? 1.0
        let minGeo = candidates.map(\.distanceMeters).min() ?? 0.0
        let geoRange = maxGeo - minGeo

        func normaliseGeo(_ d: Double) -> Double {
            geoRange > 0 ? (d - minGeo) / geoRange : 0
        }

        func normaliseVision(_ d: Float) -> Double {
            distRange > 0 ? Double((d - minDist) / distRange) : 0
        }

        var ranked = candidates.map { candidate -> MatchCandidate in
            var updated = candidate
            let rawVision = visionDistances[candidate.id] ?? 1.0
            updated.visionDistance = rawVision

            let geoScore = normaliseGeo(candidate.distanceMeters)
            let visionScore = normaliseVision(rawVision)
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
