import Foundation

// MARK: - Evidence domain

/// Signals Afterimage can genuinely observe today. Presentation text is kept
/// out of this model so matching policy can be tested without rendering UI.
enum MatchSignalKind: String, CaseIterable, Codable, Hashable, Sendable {
    case location
    case locationPrecision
    case heading
    case archiveDate
    case archiveProvenance
    case archiveImage
    case visualSimilarity
    case duplicateRecord
}

enum MatchEvidenceEffect: String, Codable, Sendable {
    case supports
    case contradicts
    case neutral
}

struct MatchEvidenceFact: Codable, Equatable, Identifiable, Sendable {
    let kind: MatchSignalKind
    let effect: MatchEvidenceEffect
    let strength: Double
    let measuredValue: Double?
    let unit: String?
    let code: String

    var id: String { "\(kind.rawValue):\(code)" }
}

struct LocationMatchEvidence: Codable, Equatable, Sendable {
    let isAvailable: Bool
    let distanceMeters: Double?
    let horizontalAccuracyMeters: Double?
    let searchRadiusMeters: Double
}

struct HeadingMatchEvidence: Codable, Equatable, Sendable {
    let deltaDegrees: Double?
    let userAccuracyDegrees: Double?
    let archiveConfidence: String?
}

struct ArchiveMatchEvidence: Codable, Equatable, Sendable {
    let source: String
    let hasAttribution: Bool
    let hasRightsStatement: Bool
    let hasDisplayImage: Bool
    let captureYear: Int?
    let duplicateGroupSize: Int
}

struct VisualMatchEvidence: Codable, Equatable, Sendable {
    /// Raw Vision feature-print distance. Lower is more similar. It is never
    /// min/max-normalized against the current candidate set.
    let featurePrintDistance: Double?
}

struct MatchEvidence: Codable, Equatable, Sendable {
    let candidateIsAvailable: Bool
    let location: LocationMatchEvidence
    let heading: HeadingMatchEvidence
    let archive: ArchiveMatchEvidence
    let visual: VisualMatchEvidence
}

// MARK: - Confidence and refusal policy

enum MatchDisposition: String, Codable, Sendable {
    case confident
    case uncertain
    case insufficientEvidence
    case conflictingSignals
    case unavailableLocation
    case noMatch

    var mayPresentOverlay: Bool { self == .confident }
}

enum MatchConfidenceBand: String, Codable, Sendable {
    case high
    case medium
    case low
    case unavailable
}

struct MatchConfidence: Codable, Equatable, Sendable {
    /// A conservative heuristic probability calibrated only against the
    /// repository's frozen fixture corpus. It is not a real-world efficacy claim.
    let fixtureEstimatedProbability: Double?
    let band: MatchConfidenceBand
    let disposition: MatchDisposition
    let supportingEvidence: [MatchEvidenceFact]
    let contradictoryEvidence: [MatchEvidenceFact]
    let missingEvidence: [MatchSignalKind]

    var mayPresentOverlay: Bool { disposition.mayPresentOverlay }

    static func unavailableLocation() -> MatchConfidence {
        MatchConfidence(
            fixtureEstimatedProbability: nil,
            band: .unavailable,
            disposition: .unavailableLocation,
            supportingEvidence: [],
            contradictoryEvidence: [],
            missingEvidence: [.location, .locationPrecision]
        )
    }

    static func noMatch() -> MatchConfidence {
        MatchConfidence(
            fixtureEstimatedProbability: 0,
            band: .low,
            disposition: .noMatch,
            supportingEvidence: [],
            contradictoryEvidence: [],
            missingEvidence: []
        )
    }
}

/// Absolute, inspectable thresholds. The values intentionally favor refusal:
/// a polished overlay appears only when at least two independent match signals
/// agree and archive display/provenance basics are present.
struct MatchConfidenceEngine {
    static func evaluate(_ evidence: MatchEvidence) -> MatchConfidence {
        guard evidence.candidateIsAvailable else {
            return .noMatch()
        }

        guard evidence.location.isAvailable else {
            return .unavailableLocation()
        }

        guard let distance = evidence.location.distanceMeters,
              distance.isFinite,
              distance >= 0 else {
            return MatchConfidence(
                fixtureEstimatedProbability: nil,
                band: .unavailable,
                disposition: .insufficientEvidence,
                supportingEvidence: [],
                contradictoryEvidence: [],
                missingEvidence: [.location]
            )
        }

        var supporting: [MatchEvidenceFact] = []
        var contradictory: [MatchEvidenceFact] = []
        var missing: [MatchSignalKind] = []

        let accuracy = evidence.location.horizontalAccuracyMeters.flatMap { value in
            value.isFinite && value >= 0 ? value : nil
        }
        if accuracy == nil {
            missing.append(.locationPrecision)
        }
        let upperDistance = distance + max(accuracy ?? 100, 0)
        let locationScore = scoreForLocation(upperDistance)
        appendFact(
            kind: .location,
            score: locationScore,
            measuredValue: upperDistance,
            unit: "m_upper_bound",
            supportCode: "location_close",
            contradictionCode: "location_far",
            supporting: &supporting,
            contradictory: &contradictory
        )

        var independentSignalCount = 1
        var headingScore: Double?
        let archiveHeadingIsUsable = ["high", "medium"]
            .contains(evidence.heading.archiveConfidence?.lowercased())
        if archiveHeadingIsUsable,
           let delta = evidence.heading.deltaDegrees,
           delta.isFinite,
           (0...180).contains(delta),
           let userAccuracy = evidence.heading.userAccuracyDegrees,
           userAccuracy.isFinite,
           userAccuracy >= 0,
           userAccuracy <= 45 {
            independentSignalCount += 1
            // Treat the reported heading accuracy as an uncertainty radius.
            // A seemingly close raw bearing must not become strong support
            // when the current compass reading is imprecise.
            let conservativeDelta = min(delta + userAccuracy, 180)
            let score = scoreForHeading(conservativeDelta)
            headingScore = score
            appendFact(
                kind: .heading,
                score: score,
                measuredValue: conservativeDelta,
                unit: "degrees_upper_bound",
                supportCode: "heading_compatible",
                contradictionCode: "heading_conflicts",
                supporting: &supporting,
                contradictory: &contradictory
            )
        } else {
            missing.append(.heading)
        }

        var visualScore: Double?
        if let distance = evidence.visual.featurePrintDistance,
           distance.isFinite,
           distance >= 0 {
            independentSignalCount += 1
            let score = scoreForVisualDistance(distance)
            visualScore = score
            appendFact(
                kind: .visualSimilarity,
                score: score,
                measuredValue: distance,
                unit: "feature_distance",
                supportCode: "visual_compatible",
                contradictionCode: "visual_conflicts",
                supporting: &supporting,
                contradictory: &contradictory
            )
        } else {
            missing.append(.visualSimilarity)
        }

        if evidence.archive.hasAttribution {
            supporting.append(MatchEvidenceFact(
                kind: .archiveProvenance,
                effect: .supports,
                strength: 0.55,
                measuredValue: nil,
                unit: nil,
                code: "archive_attributed"
            ))
        } else {
            missing.append(.archiveProvenance)
        }

        if evidence.archive.captureYear == nil {
            missing.append(.archiveDate)
        }
        if !evidence.archive.hasRightsStatement {
            missing.append(.archiveProvenance)
        }
        if !evidence.archive.hasDisplayImage {
            missing.append(.archiveImage)
        }
        if evidence.archive.duplicateGroupSize > 1 {
            contradictory.append(MatchEvidenceFact(
                kind: .duplicateRecord,
                effect: .contradicts,
                strength: 0.45,
                measuredValue: Double(evidence.archive.duplicateGroupSize),
                unit: "records",
                code: "duplicate_archive_records"
            ))
        }

        // Missing optional signals receive a cautious prior rather than being
        // silently reweighted away. This prevents a single candidate from
        // normalizing itself into a strong match.
        let probability = clamp(
            0.50 * locationScore
                + 0.25 * (headingScore ?? 0.35)
                + 0.25 * (visualScore ?? 0.35)
        )

        let archiveCap: Double = {
            guard evidence.archive.hasAttribution, evidence.archive.hasDisplayImage else {
                return 0.49
            }
            if evidence.archive.duplicateGroupSize > 1 { return 0.69 }
            if !evidence.archive.hasRightsStatement || evidence.archive.captureYear == nil {
                return 0.74
            }
            return 1
        }()
        let cappedProbability = min(probability, archiveCap)

        let hasStrongSupport = supporting.contains { $0.strength >= 0.65 }
        let hasStrongContradiction = contradictory.contains { $0.strength >= 0.65 }
        let disposition: MatchDisposition
        if hasStrongSupport && hasStrongContradiction {
            disposition = .conflictingSignals
        } else if independentSignalCount < 2
                    || !evidence.archive.hasAttribution
                    || !evidence.archive.hasDisplayImage {
            disposition = .insufficientEvidence
        } else if cappedProbability >= 0.78 && !hasStrongContradiction {
            disposition = .confident
        } else {
            disposition = .uncertain
        }

        let reportedProbability: Double
        switch disposition {
        case .confident:
            reportedProbability = cappedProbability
        case .uncertain:
            reportedProbability = cappedProbability >= 0.62
                ? 0.77
                : min(cappedProbability, 0.61)
        case .insufficientEvidence:
            reportedProbability = min(cappedProbability, 0.10)
        case .conflictingSignals:
            reportedProbability = min(cappedProbability, 0.10)
        case .unavailableLocation, .noMatch:
            reportedProbability = 0
        }

        let band: MatchConfidenceBand
        switch disposition {
        case .confident:
            band = .high
        case .uncertain:
            band = reportedProbability >= 0.62 ? .medium : .low
        case .insufficientEvidence, .conflictingSignals, .noMatch:
            band = .low
        case .unavailableLocation:
            band = .unavailable
        }

        return MatchConfidence(
            fixtureEstimatedProbability: reportedProbability,
            band: band,
            disposition: disposition,
            supportingEvidence: supporting,
            contradictoryEvidence: contradictory,
            missingEvidence: Array(Set(missing)).sorted { $0.rawValue < $1.rawValue }
        )
    }

    private static func scoreForLocation(_ upperDistance: Double) -> Double {
        switch upperDistance {
        case ...20: return 0.94
        case ...50: return 0.82
        case ...100: return 0.66
        case ...200: return 0.38
        default: return 0.12
        }
    }

    private static func scoreForHeading(_ delta: Double) -> Double {
        switch delta {
        case ...15: return 0.92
        case ...30: return 0.78
        case ...45: return 0.62
        case ...90: return 0.28
        default: return 0.06
        }
    }

    private static func scoreForVisualDistance(_ distance: Double) -> Double {
        switch distance {
        case ...0.25: return 0.92
        case ...0.45: return 0.78
        case ...0.70: return 0.58
        case ...1.00: return 0.32
        default: return 0.10
        }
    }

    private static func appendFact(
        kind: MatchSignalKind,
        score: Double,
        measuredValue: Double,
        unit: String,
        supportCode: String,
        contradictionCode: String,
        supporting: inout [MatchEvidenceFact],
        contradictory: inout [MatchEvidenceFact]
    ) {
        if score >= 0.58 {
            supporting.append(MatchEvidenceFact(
                kind: kind,
                effect: .supports,
                strength: score,
                measuredValue: measuredValue,
                unit: unit,
                code: supportCode
            ))
        } else if score <= 0.38 {
            contradictory.append(MatchEvidenceFact(
                kind: kind,
                effect: .contradicts,
                strength: 1 - score,
                measuredValue: measuredValue,
                unit: unit,
                code: contradictionCode
            ))
        }
    }

    private static func clamp(_ value: Double) -> Double {
        min(max(value, 0), 1)
    }
}

// MARK: - Fixture calibration

struct MatchCalibrationFixture: Codable, Sendable {
    let id: String
    let category: String
    let evidence: MatchEvidence
    let isTrueMatch: Bool
    let expectedDisposition: MatchDisposition
}

struct MatchCalibrationReport: Codable, Equatable, Sendable {
    let fixtureCount: Int
    let fixtureBrierScore: Double
    let fixtureExpectedCalibrationError: Double
    let refusalRecall: Double
    let dispositionAccuracy: Double
}

struct MatchCalibration {
    static func measure(fixtures: [MatchCalibrationFixture]) -> MatchCalibrationReport {
        guard !fixtures.isEmpty else {
            return MatchCalibrationReport(
                fixtureCount: 0,
                fixtureBrierScore: 0,
                fixtureExpectedCalibrationError: 0,
                refusalRecall: 0,
                dispositionAccuracy: 0
            )
        }

        let outcomes = fixtures.map { fixture in
            let confidence = MatchConfidenceEngine.evaluate(fixture.evidence)
            return (fixture, confidence)
        }

        let brier = outcomes.reduce(0.0) { total, item in
            let predicted = item.1.fixtureEstimatedProbability ?? 0
            let observed = item.0.isTrueMatch ? 1.0 : 0.0
            return total + pow(predicted - observed, 2)
        } / Double(outcomes.count)

        let bins = 5
        var calibrationError = 0.0
        for bin in 0..<bins {
            let lower = Double(bin) / Double(bins)
            let upper = Double(bin + 1) / Double(bins)
            let members = outcomes.filter { item in
                let probability = item.1.fixtureEstimatedProbability ?? 0
                return probability >= lower && (bin == bins - 1 ? probability <= upper : probability < upper)
            }
            guard !members.isEmpty else { continue }
            let predicted = members.reduce(0.0) {
                $0 + ($1.1.fixtureEstimatedProbability ?? 0)
            }
                / Double(members.count)
            let observed = members.reduce(0.0) { $0 + ($1.0.isTrueMatch ? 1 : 0) }
                / Double(members.count)
            calibrationError += abs(predicted - observed)
                * Double(members.count) / Double(outcomes.count)
        }

        let negatives = outcomes.filter { !$0.0.isTrueMatch }
        let refusedNegatives = negatives.filter { !$0.1.mayPresentOverlay }
        let refusalRecall = negatives.isEmpty
            ? 1
            : Double(refusedNegatives.count) / Double(negatives.count)
        let correctDispositions = outcomes.filter {
            $0.1.disposition == $0.0.expectedDisposition
        }.count

        return MatchCalibrationReport(
            fixtureCount: outcomes.count,
            fixtureBrierScore: brier,
            fixtureExpectedCalibrationError: calibrationError,
            refusalRecall: refusalRecall,
            dispositionAccuracy: Double(correctDispositions) / Double(outcomes.count)
        )
    }
}
