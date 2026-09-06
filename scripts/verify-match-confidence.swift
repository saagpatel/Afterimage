import Darwin
import Foundation

@main
struct VerifyMatchConfidence {
    static func main() throws {
        guard CommandLine.arguments.count == 2 else {
            FileHandle.standardError.write(Data("usage: verify-match-confidence <fixture-json>\n".utf8))
            exit(2)
        }

        let fixtureURL = URL(fileURLWithPath: CommandLine.arguments[1])
        let fixtures = try JSONDecoder().decode(
            [MatchCalibrationFixture].self,
            from: Data(contentsOf: fixtureURL)
        )
        let report = MatchCalibration.measure(fixtures: fixtures)
        var failures = fixtures.compactMap { fixture -> String? in
            let actual = MatchConfidenceEngine.evaluate(fixture.evidence).disposition
            guard actual != fixture.expectedDisposition else { return nil }
            return "\(fixture.id): expected \(fixture.expectedDisposition.rawValue), got \(actual.rawValue)"
        }
        failures.append(contentsOf: adversarialNumericFailures())

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let payload = try encoder.encode(report)
        FileHandle.standardOutput.write(payload)
        FileHandle.standardOutput.write(Data("\n".utf8))

        if !failures.isEmpty {
            for failure in failures {
                FileHandle.standardError.write(Data("verification failure: \(failure)\n".utf8))
            }
            exit(1)
        }
        guard report.fixtureCount >= 12 else {
            FileHandle.standardError.write(Data("fixture corpus is too small\n".utf8))
            exit(1)
        }
        guard report.fixtureBrierScore <= 0.18 else {
            FileHandle.standardError.write(Data("fixture Brier score exceeds ceiling\n".utf8))
            exit(1)
        }
        guard report.fixtureExpectedCalibrationError <= 0.18 else {
            FileHandle.standardError.write(Data("fixture calibration error exceeds ceiling\n".utf8))
            exit(1)
        }
        guard report.refusalRecall == 1 else {
            FileHandle.standardError.write(Data("negative-case refusal recall must be 1.0\n".utf8))
            exit(1)
        }
        guard report.dispositionAccuracy == 1 else {
            FileHandle.standardError.write(Data("fixture disposition accuracy must be 1.0\n".utf8))
            exit(1)
        }
    }

    private static func adversarialNumericFailures() -> [String] {
        let archive = ArchiveMatchEvidence(
            source: "adversarial-fixture",
            hasAttribution: true,
            hasRightsStatement: true,
            hasDisplayImage: true,
            captureYear: 1930,
            duplicateGroupSize: 1
        )
        let invalidLocation = MatchConfidenceEngine.evaluate(MatchEvidence(
            candidateIsAvailable: true,
            location: LocationMatchEvidence(
                isAvailable: true,
                distanceMeters: .nan,
                horizontalAccuracyMeters: -.infinity,
                searchRadiusMeters: 100
            ),
            heading: HeadingMatchEvidence(
                deltaDegrees: -10,
                userAccuracyDegrees: .infinity,
                archiveConfidence: "high"
            ),
            archive: archive,
            visual: VisualMatchEvidence(featurePrintDistance: -.infinity)
        ))

        let invalidOptionalSignals = MatchConfidenceEngine.evaluate(MatchEvidence(
            candidateIsAvailable: true,
            location: LocationMatchEvidence(
                isAvailable: true,
                distanceMeters: 5,
                horizontalAccuracyMeters: -1,
                searchRadiusMeters: 100
            ),
            heading: HeadingMatchEvidence(
                deltaDegrees: 181,
                userAccuracyDegrees: 5,
                archiveConfidence: "high"
            ),
            archive: archive,
            visual: VisualMatchEvidence(featurePrintDistance: -0.1)
        ))

        let impreciseHeading = MatchConfidenceEngine.evaluate(MatchEvidence(
            candidateIsAvailable: true,
            location: LocationMatchEvidence(
                isAvailable: true,
                distanceMeters: 5,
                horizontalAccuracyMeters: 5,
                searchRadiusMeters: 100
            ),
            heading: HeadingMatchEvidence(
                deltaDegrees: 5,
                userAccuracyDegrees: 45,
                archiveConfidence: "medium"
            ),
            archive: archive,
            visual: VisualMatchEvidence(featurePrintDistance: 0.2)
        ))

        let lowConfidenceArchiveHeading = MatchConfidenceEngine.evaluate(MatchEvidence(
            candidateIsAvailable: true,
            location: LocationMatchEvidence(
                isAvailable: true,
                distanceMeters: 5,
                horizontalAccuracyMeters: 5,
                searchRadiusMeters: 100
            ),
            heading: HeadingMatchEvidence(
                deltaDegrees: 1,
                userAccuracyDegrees: 1,
                archiveConfidence: "low"
            ),
            archive: archive,
            visual: VisualMatchEvidence(featurePrintDistance: nil)
        ))

        var failures: [String] = []
        if invalidLocation.disposition != .insufficientEvidence
            || invalidLocation.fixtureEstimatedProbability != nil
            || !invalidLocation.missingEvidence.contains(.location) {
            failures.append("non-finite location evidence did not fail closed")
        }
        let requiredMissing: Set<MatchSignalKind> = [
            .locationPrecision,
            .heading,
            .visualSimilarity,
        ]
        if invalidOptionalSignals.disposition != .insufficientEvidence
            || !requiredMissing.isSubset(of: Set(invalidOptionalSignals.missingEvidence)) {
            failures.append("invalid optional signals did not remain missing")
        }
        let conservativeHeading = impreciseHeading.contradictoryEvidence
            .first { $0.kind == .heading }
        if impreciseHeading.disposition != .conflictingSignals
            || conservativeHeading?.measuredValue != 50
            || conservativeHeading?.unit != "degrees_upper_bound" {
            failures.append("imprecise heading was not scored at its conservative upper bound")
        }
        if lowConfidenceArchiveHeading.disposition != .insufficientEvidence
            || !lowConfidenceArchiveHeading.missingEvidence.contains(.heading)
            || lowConfidenceArchiveHeading.supportingEvidence.contains(where: { $0.kind == .heading }) {
            failures.append("low-confidence archive heading became independent support")
        }
        return failures
    }
}
