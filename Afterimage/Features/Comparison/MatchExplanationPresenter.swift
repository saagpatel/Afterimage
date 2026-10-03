import Foundation

struct ProvenancePresentationRow: Identifiable, Equatable {
    let label: String
    let value: String

    var id: String { label }
}

/// Converts evidence codes into user-facing language. The confidence engine
/// never depends on these strings.
struct MatchExplanationPresenter {
    let candidate: MatchCandidate

    var title: String {
        switch candidate.confidence.disposition {
        case .confident: "Evidence supports this match"
        case .uncertain: "Possible match — inspect the evidence"
        case .insufficientEvidence: "Not enough evidence for an overlay"
        case .conflictingSignals: "Signals disagree — overlay withheld"
        case .unavailableLocation: "Location unavailable"
        case .noMatch: "No historical match found"
        }
    }

    var shortLabel: String {
        switch candidate.confidence.disposition {
        case .confident: "Supported"
        case .uncertain: "Uncertain"
        case .insufficientEvidence: "Insufficient evidence"
        case .conflictingSignals: "Conflicting signals"
        case .unavailableLocation: "Location unavailable"
        case .noMatch: "No match"
        }
    }

    var calibrationNote: String {
        "On-device assessment; not a verified identification."
    }

    var candidateContext: String {
        [candidate.photo.city, candidate.photo.dateText, distanceText]
            .compactMap { value in
                guard let value, !value.isEmpty else { return nil }
                return value
            }
            .joined(separator: " · ")
    }

    var distanceText: String {
        let measurement = Measurement(
            value: candidate.distanceMeters,
            unit: UnitLength.meters
        )
        return measurement.formatted(.measurement(width: .abbreviated, usage: .road))
    }

    var archiveName: String {
        switch candidate.photo.source {
        case .oldnyc: "OldNYC / New York Public Library"
        case .wikimedia: "Wikimedia Commons"
        case .flickrCommons: "Flickr Commons"
        }
    }

    var provenanceRows: [ProvenancePresentationRow] {
        let provenance = candidate.photo.provenance
        return [
            ProvenancePresentationRow(
                label: "Local index ID",
                value: "\(provenance.indexRecordID) — not a source record ID"
            ),
            ProvenancePresentationRow(
                label: "Source record link",
                value: present(
                    provenance.sourceRecordURL,
                    notStored: "Not recorded in bundled index",
                    fieldMissing: "Missing for this record"
                ) { $0.absoluteString }
            ),
            ProvenancePresentationRow(
                label: "Ingestion version",
                value: present(
                    provenance.ingestionVersion,
                    notStored: "Not recorded in bundled index",
                    fieldMissing: "Missing for this record"
                ) { $0 }
            ),
            ProvenancePresentationRow(
                label: "Coordinate origin",
                value: present(
                    provenance.coordinateOrigin,
                    notStored: "Coordinates stored; origin not recorded",
                    fieldMissing: "Coordinates missing for this record"
                ) { origin in
                    switch origin {
                    case .archiveSupplied: "Archive supplied"
                    case .embeddedGPS: "Embedded GPS"
                    case .geocoded: "Geocoded"
                    }
                }
            ),
            confidenceRow(
                "Coordinate confidence",
                provenance.coordinateConfidence,
                notStored: "Coordinates stored; confidence not recorded"
            ),
            confidenceRow(
                "Date confidence",
                provenance.dateConfidence,
                notStored: candidate.photo.dateText == nil
                    ? "Date missing for this record"
                    : "Date stored; confidence not recorded"
            ),
            confidenceRow(
                "Rights verification",
                provenance.rightsConfidence,
                notStored: candidate.photo.rightsURI == nil
                    ? "Rights link missing for this record"
                    : "Rights link stored; verification not recorded"
            ),
            confidenceRow(
                "Archive heading metadata confidence",
                provenance.headingConfidence,
                notStored: "Confidence not recorded"
            ),
        ]
    }

    var unavailableProvenanceCount: Int {
        let provenance = candidate.photo.provenance
        return [
            provenance.sourceRecordURL.isUnavailable,
            provenance.ingestionVersion.isUnavailable,
            provenance.coordinateOrigin.isUnavailable,
            provenance.coordinateConfidence.isUnavailable,
            provenance.dateConfidence.isUnavailable,
            provenance.rightsConfidence.isUnavailable,
            provenance.headingConfidence.isUnavailable,
        ].filter { $0 }.count
    }

    var provenanceSummary: String {
        let count = unavailableProvenanceCount
        return count == 1
            ? "1 lineage field is incomplete"
            : "\(count) lineage fields are incomplete"
    }

    var supporting: [String] {
        candidate.confidence.supportingEvidence.map(present)
    }

    var contradictory: [String] {
        candidate.confidence.contradictoryEvidence.map(present)
    }

    var missing: [String] {
        candidate.confidence.missingEvidence.map { kind in
            switch kind {
            case .location: "No usable location was available."
            case .locationPrecision: "Location precision was not available."
            case .heading: "Viewpoint direction could not be compared."
            case .archiveDate: "The archive record has no reliable capture date."
            case .archiveProvenance: "Archive rights or attribution metadata is incomplete."
            case .archiveImage: "The historical image is not cached or available."
            case .visualSimilarity: "Visual similarity could not be measured."
            case .duplicateRecord: "Duplicate-record status is unavailable."
            }
        }
    }

    var accessibilitySummary: String {
        let identity = [candidate.photo.title, candidate.photo.city, candidate.eraLabel]
            .compactMap { $0 }
            .joined(separator: ", ")
        let refusal = candidate.confidence.mayPresentOverlay
            ? ". Overlay available"
            : ". Overlay withheld"
        return "\(identity). \(title)\(refusal). "
            + "\(supporting.count) supporting, \(contradictory.count) contradictory, "
            + "\(missing.count) missing evidence items."
    }

    var primaryRefusalReason: String? {
        if let contradiction = contradictory.first { return contradiction }
        if let unavailable = missing.first { return unavailable }

        switch candidate.confidence.disposition {
        case .uncertain:
            return "The available signals do not agree strongly enough to support an overlay."
        case .insufficientEvidence:
            return "Too few independent signals are available to support an overlay."
        case .conflictingSignals:
            return "Supporting and contradictory signals are both present."
        case .unavailableLocation:
            return "A usable location is required before candidates can be assessed."
        case .noMatch:
            return "No archive candidate was found within the supported search path."
        case .confident:
            return nil
        }
    }

    private func present(_ fact: MatchEvidenceFact) -> String {
        switch fact.code {
        case "location_close":
            return measurement(fact, prefix: "The location is compatible within")
        case "location_far":
            return measurement(fact, prefix: "The candidate may be as far as")
        case "heading_compatible":
            return measurement(fact, prefix: "The viewpoint difference is at most")
        case "heading_conflicts":
            return measurement(fact, prefix: "The viewpoint difference may reach")
        case "visual_compatible":
            return measurement(fact, prefix: "On-device visual distance is")
        case "visual_conflicts":
            return measurement(fact, prefix: "On-device visual distance is weak at")
        case "archive_attributed":
            return "The archive record names its source and attribution."
        case "duplicate_archive_records":
            return measurement(fact, prefix: "The archive index contains a correlated group of")
        default:
            return fact.kind.rawValue.replacingOccurrences(of: "_", with: " ")
        }
    }

    private func confidenceRow(
        _ label: String,
        _ value: ProvenanceValue<ProvenanceConfidence>,
        notStored: String
    ) -> ProvenancePresentationRow {
        ProvenancePresentationRow(
            label: label,
            value: present(
                value,
                notStored: notStored,
                fieldMissing: "Unavailable for this record"
            ) { confidence in
                confidence.rawValue.capitalized
            }
        )
    }

    private func present<Value>(
        _ value: ProvenanceValue<Value>,
        notStored: String,
        fieldMissing: String,
        transform: (Value) -> String
    ) -> String where Value: Codable & Equatable & Sendable {
        switch value {
        case .available(let available):
            return transform(available)
        case .unavailable(.notStoredInBundledIndex):
            return notStored
        case .unavailable(.fieldMissing):
            return fieldMissing
        case .unavailable(.unsupportedStoredValue):
            return "Stored value is not understood"
        }
    }

    private func measurement(_ fact: MatchEvidenceFact, prefix: String) -> String {
        guard let value = fact.measuredValue else { return prefix + "." }
        switch fact.unit {
        case "m_upper_bound":
            return "\(prefix) \(Int(value.rounded())) metres after location uncertainty."
        case "degrees_upper_bound":
            return "\(prefix) \(Int(value.rounded())) degrees after compass uncertainty."
        case "feature_distance":
            return "\(prefix) \(String(format: "%.2f", value))."
        case "records":
            return "\(prefix) \(Int(value.rounded())) records; they do not count as independent support."
        default:
            return "\(prefix) \(String(format: "%.2f", value))."
        }
    }
}
