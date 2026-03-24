import Foundation

struct HeadingFilter {
    /// Filters `candidates` to those whose heading is within `threshold` degrees of `userHeading`.
    ///
    /// - If `userHeadingAccuracy` is outside the range [0, 45], the filter is skipped entirely
    ///   and all candidates are returned unchanged.
    /// - Candidates with a `nil` photo heading always pass through; their `headingDelta` is set to `nil`.
    /// - Passing candidates have their `headingDelta` populated with the angular difference.
    static func filter(
        candidates: [MatchCandidate],
        userHeading: Double,
        userHeadingAccuracy: Double,
        threshold: Double = 45.0
    ) -> [MatchCandidate] {
        // Skip when accuracy is unavailable (negative) or too coarse to be useful
        guard userHeadingAccuracy >= 0, userHeadingAccuracy <= 45 else {
            return candidates
        }

        return candidates.compactMap { candidate in
            guard let photoHeading = candidate.photo.heading else {
                // No heading on photo — pass through with headingDelta cleared
                var updated = candidate
                updated.headingDelta = nil
                return updated
            }

            let delta = headingDelta(userHeading, photoHeading)
            guard delta <= threshold else { return nil }

            var updated = candidate
            updated.headingDelta = delta
            return updated
        }
    }

    /// Minimum angular difference between two compass headings, accounting for 360/0 wraparound.
    /// Result is in [0, 180].
    static func headingDelta(_ a: Double, _ b: Double) -> Double {
        let diff = abs(a - b).truncatingRemainder(dividingBy: 360)
        return diff > 180 ? 360 - diff : diff
    }
}
