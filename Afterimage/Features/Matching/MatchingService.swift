import CoreLocation
import GRDB
import os
import UIKit

@MainActor @Observable
final class MatchingService {
    enum State: Sendable {
        case idle
        case searching(stage: String)
        case found([MatchCandidate])
        case noResults
        case error(String)
    }

    private(set) var state: State = .idle
    private let spatialQuery: SpatialQuery
    private let logger = Logger(subsystem: "com.afterimage", category: "Matching")

    init(database: any DatabaseReader) {
        self.spatialQuery = SpatialQuery(database: database)
    }

    func findMatches(
        for photo: UIImage,
        at location: CLLocation,
        heading: CLHeading?
    ) async {
        state = .searching(stage: "Finding nearby photos...")
        let startTime = CFAbsoluteTimeGetCurrent()

        do {
            // Stage 1: Spatial query (100m)
            var stageStart = CFAbsoluteTimeGetCurrent()
            var results = try await spatialQuery.candidates(
                near: location.coordinate,
                radiusMeters: 100
            )
            logger.info("Stage 1 (spatial 100m): \(results.count) candidates in \(String(format: "%.0f", (CFAbsoluteTimeGetCurrent() - stageStart) * 1000))ms")

            if results.isEmpty {
                // Fallback to 500m
                state = .searching(stage: "Widening search to 500m...")
                stageStart = CFAbsoluteTimeGetCurrent()
                results = try await spatialQuery.candidates(
                    near: location.coordinate,
                    radiusMeters: 500
                )
                logger.info("Stage 1 (spatial 500m fallback): \(results.count) candidates in \(String(format: "%.0f", (CFAbsoluteTimeGetCurrent() - stageStart) * 1000))ms")
            }

            guard !results.isEmpty else {
                state = .noResults
                return
            }

            let usedFallback = results.first.map { $0.distance > 100 } ?? false

            // Convert to MatchCandidates
            var candidates = results.map {
                MatchCandidate(photo: $0.photo, distanceMeters: $0.distance)
            }

            // Stage 2: Heading filter
            if let heading, heading.headingAccuracy >= 0 {
                state = .searching(stage: "Filtering by direction...")
                stageStart = CFAbsoluteTimeGetCurrent()
                let filtered = HeadingFilter.filter(
                    candidates: candidates,
                    userHeading: heading.trueHeading,
                    userHeadingAccuracy: heading.headingAccuracy
                )
                logger.info("Stage 2 (heading): \(candidates.count) → \(filtered.count) in \(String(format: "%.0f", (CFAbsoluteTimeGetCurrent() - stageStart) * 1000))ms")

                if !filtered.isEmpty {
                    candidates = filtered
                } else {
                    logger.info("Stage 2: heading filter emptied candidates, falling back to unfiltered")
                }
            } else {
                logger.info("Stage 2 (heading): skipped — no reliable heading")
            }

            // Stage 3: Fetch thumbnails
            state = .searching(stage: "Loading historical photos...")
            stageStart = CFAbsoluteTimeGetCurrent()
            candidates = await ThumbnailFetcher.fetchThumbnails(for: candidates)
            logger.info("Stage 3 (thumbnails): \(candidates.count) fetched in \(String(format: "%.0f", (CFAbsoluteTimeGetCurrent() - stageStart) * 1000))ms")

            guard !candidates.isEmpty else {
                state = .noResults
                return
            }

            // Stage 4: Vision ranking
            state = .searching(stage: "Comparing images...")
            stageStart = CFAbsoluteTimeGetCurrent()
            candidates = try await VisionRanker.rank(
                candidates: candidates,
                userPhoto: photo
            )
            logger.info("Stage 4 (vision): ranked \(candidates.count) in \(String(format: "%.0f", (CFAbsoluteTimeGetCurrent() - stageStart) * 1000))ms")

            // Mark 500m-radius results as .nearby
            if usedFallback {
                candidates = candidates.map {
                    var c = $0
                    c.confidenceLabel = .nearby
                    return c
                }
            }

            // Cap at 5 results
            let topResults = Array(candidates.prefix(5))
            let totalTime = (CFAbsoluteTimeGetCurrent() - startTime) * 1000
            logger.info("Matching complete: \(topResults.count) results in \(String(format: "%.0f", totalTime))ms total")

            state = .found(topResults)

        } catch {
            logger.error("Matching failed: \(error.localizedDescription)")
            state = .error("Matching failed: \(error.localizedDescription)")
        }
    }
}
