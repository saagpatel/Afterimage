import CoreLocation
import GRDB
import os
import UIKit

@MainActor @Observable
final class MatchingService {
    typealias ThumbnailLoader = ([MatchCandidate]) async -> [MatchCandidate]

    enum Mode: Sendable, Equatable {
        case fieldMatch
        case archiveBrowse
    }

    enum State: Sendable {
        case idle
        case searching(stage: String)
        case found([MatchCandidate])
        case noResults
        case error(String)
    }

    private(set) var state: State = .idle
    private let spatialQuery: SpatialQuery
    private let thumbnailLoader: ThumbnailLoader
    private let logger = Logger(subsystem: "com.afterimage", category: "Matching")

    init(
        database: any DatabaseReader,
        thumbnailLoader: @escaping ThumbnailLoader = { candidates in
            await ThumbnailFetcher.fetchThumbnails(for: candidates)
        }
    ) {
        self.spatialQuery = SpatialQuery(database: database)
        self.thumbnailLoader = thumbnailLoader
    }

    func findMatches(
        for photo: UIImage,
        at location: CLLocation,
        heading: CLHeading?,
        mode: Mode = .fieldMatch
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
                MatchCandidate(
                    photo: $0.photo,
                    distanceMeters: $0.distance,
                    locationAccuracyMeters: location.horizontalAccuracy,
                    searchRadiusMeters: usedFallback ? 500 : 100
                )
            }
            candidates = recordDuplicateGroups(in: candidates)

            // Stage 2: Heading compatibility. Preserve contradictions so the
            // confidence engine can refuse rather than silently falling back.
            if let heading, heading.headingAccuracy >= 0 {
                state = .searching(stage: "Checking viewpoint evidence...")
                stageStart = CFAbsoluteTimeGetCurrent()
                candidates = HeadingFilter.annotate(
                    candidates: candidates,
                    userHeading: heading.trueHeading,
                    userHeadingAccuracy: heading.headingAccuracy
                )
                logger.info("Stage 2 (heading evidence): annotated \(candidates.count) in \(String(format: "%.0f", (CFAbsoluteTimeGetCurrent() - stageStart) * 1000))ms")
            } else {
                logger.info("Stage 2 (heading): skipped — no reliable heading")
            }

            // Stage 3: Fetch thumbnails
            state = .searching(stage: "Loading historical photos...")
            stageStart = CFAbsoluteTimeGetCurrent()
            let candidatesBeforeLoading = candidates
            let loadedCandidates = await thumbnailLoader(candidates)
            let loadedByID = loadedCandidates.reduce(into: [String: MatchCandidate]()) {
                partialResult, candidate in
                partialResult[candidate.id] = candidate
            }
            candidates = candidatesBeforeLoading.map { candidate in
                loadedByID[candidate.id] ?? candidate
            }
            logger.info("Stage 3 (thumbnails): \(candidates.count) fetched in \(String(format: "%.0f", (CFAbsoluteTimeGetCurrent() - stageStart) * 1000))ms")

            if mode == .archiveBrowse {
                let results = candidates.sorted { $0.distanceMeters < $1.distanceMeters }
                state = .found(Array(results.prefix(5)))
                return
            }

            // Stage 4: Vision ranking
            state = .searching(stage: "Comparing images...")
            stageStart = CFAbsoluteTimeGetCurrent()
            candidates = await VisionRanker.rank(
                candidates: candidates,
                userPhoto: photo
            )
            logger.info("Stage 4 (vision): ranked \(candidates.count) in \(String(format: "%.0f", (CFAbsoluteTimeGetCurrent() - stageStart) * 1000))ms")

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

    private func recordDuplicateGroups(in candidates: [MatchCandidate]) -> [MatchCandidate] {
        let grouped = Dictionary(grouping: candidates) { candidate in
            let lat = Int((candidate.photo.lat * 10_000).rounded())
            let lon = Int((candidate.photo.lon * 10_000).rounded())
            let decade = candidate.photo.dateYear.map { $0 / 10 } ?? -1
            return "\(lat):\(lon):\(decade)"
        }
        let counts = grouped.mapValues(\.count)

        return candidates.map { candidate in
            let lat = Int((candidate.photo.lat * 10_000).rounded())
            let lon = Int((candidate.photo.lon * 10_000).rounded())
            let decade = candidate.photo.dateYear.map { $0 / 10 } ?? -1
            let key = "\(lat):\(lon):\(decade)"
            var updated = candidate
            updated.recordDuplicateGroupSize(counts[key] ?? 1)
            return updated
        }
    }
}
