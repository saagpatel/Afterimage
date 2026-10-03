import Darwin
import Foundation

private struct ProvenanceVerificationReport: Codable {
    let indexRecordPreserved: Bool
    let missingLineageRemainsUnavailable: Bool
    let storedHeadingConfidencePreserved: Bool
    let unsupportedHeadingConfidenceRefused: Bool
}

@main
enum VerifyProvenanceContract {
    static func main() throws {
        let missing = HistoricalAssetProvenance.currentBundledIndex(
            indexRecordID: "wikimedia:123",
            headingIsPresent: false,
            headingConfidenceRawValue: "low"
        )
        let recorded = HistoricalAssetProvenance.currentBundledIndex(
            indexRecordID: "oldnyc:456",
            headingIsPresent: true,
            headingConfidenceRawValue: "medium"
        )
        let unsupported = HistoricalAssetProvenance.currentBundledIndex(
            indexRecordID: "fixture:unsupported",
            headingIsPresent: true,
            headingConfidenceRawValue: "very-certain"
        )

        let unavailableValuesArePreserved =
            missing.sourceRecordURL == .unavailable(.notStoredInBundledIndex)
            && missing.ingestionVersion == .unavailable(.notStoredInBundledIndex)
            && missing.coordinateOrigin == .unavailable(.notStoredInBundledIndex)
            && missing.coordinateConfidence == .unavailable(.notStoredInBundledIndex)
            && missing.dateConfidence == .unavailable(.notStoredInBundledIndex)
            && missing.rightsConfidence == .unavailable(.notStoredInBundledIndex)
            && missing.headingConfidence == .unavailable(.fieldMissing)

        let report = ProvenanceVerificationReport(
            indexRecordPreserved: missing.indexRecordID == "wikimedia:123",
            missingLineageRemainsUnavailable: unavailableValuesArePreserved,
            storedHeadingConfidencePreserved: recorded.headingConfidence == .available(.medium),
            unsupportedHeadingConfidenceRefused:
                unsupported.headingConfidence == .unavailable(.unsupportedStoredValue)
        )

        let checks = [
            report.indexRecordPreserved,
            report.missingLineageRemainsUnavailable,
            report.storedHeadingConfidencePreserved,
            report.unsupportedHeadingConfidenceRefused,
        ]
        guard checks.allSatisfy({ $0 }) else {
            FileHandle.standardError.write(Data("provenance contract verification failed\n".utf8))
            exit(1)
        }

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        FileHandle.standardOutput.write(try encoder.encode(report))
        FileHandle.standardOutput.write(Data("\n".utf8))
    }
}
