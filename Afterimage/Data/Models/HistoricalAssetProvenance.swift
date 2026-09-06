import Foundation

/// Why a provenance value cannot be asserted from the currently bundled index.
/// Missing values remain typed and visible instead of being inferred from IDs,
/// URLs, or field presence.
enum ProvenanceUnavailableReason: String, Codable, Equatable, Sendable {
    case notStoredInBundledIndex
    case fieldMissing
    case unsupportedStoredValue
}

enum ProvenanceValue<Value: Codable & Equatable & Sendable>: Codable, Equatable, Sendable {
    case available(Value)
    case unavailable(ProvenanceUnavailableReason)

    var isUnavailable: Bool {
        if case .unavailable = self { return true }
        return false
    }
}

enum CoordinateOrigin: String, Codable, Equatable, Sendable {
    case archiveSupplied
    case embeddedGPS
    case geocoded
}

enum ProvenanceConfidence: String, Codable, Equatable, Sendable {
    case high
    case medium
    case low
}

/// A compatibility layer for provenance that the current unversioned database
/// can actually prove. Future versioned indexes may populate additional values;
/// this layer deliberately keeps them unavailable today.
struct HistoricalAssetProvenance: Codable, Equatable, Sendable {
    let indexRecordID: String
    let sourceRecordURL: ProvenanceValue<URL>
    let ingestionVersion: ProvenanceValue<String>
    let coordinateOrigin: ProvenanceValue<CoordinateOrigin>
    let coordinateConfidence: ProvenanceValue<ProvenanceConfidence>
    let dateConfidence: ProvenanceValue<ProvenanceConfidence>
    let rightsConfidence: ProvenanceValue<ProvenanceConfidence>
    let headingConfidence: ProvenanceValue<ProvenanceConfidence>

    static func currentBundledIndex(
        indexRecordID: String,
        headingIsPresent: Bool,
        headingConfidenceRawValue: String
    ) -> HistoricalAssetProvenance {
        let headingConfidence: ProvenanceValue<ProvenanceConfidence>
        if !headingIsPresent {
            headingConfidence = .unavailable(.fieldMissing)
        } else if let value = ProvenanceConfidence(rawValue: headingConfidenceRawValue) {
            headingConfidence = .available(value)
        } else {
            headingConfidence = .unavailable(.unsupportedStoredValue)
        }

        return HistoricalAssetProvenance(
            indexRecordID: indexRecordID,
            sourceRecordURL: .unavailable(.notStoredInBundledIndex),
            ingestionVersion: .unavailable(.notStoredInBundledIndex),
            coordinateOrigin: .unavailable(.notStoredInBundledIndex),
            coordinateConfidence: .unavailable(.notStoredInBundledIndex),
            dateConfidence: .unavailable(.notStoredInBundledIndex),
            rightsConfidence: .unavailable(.notStoredInBundledIndex),
            headingConfidence: headingConfidence
        )
    }
}
