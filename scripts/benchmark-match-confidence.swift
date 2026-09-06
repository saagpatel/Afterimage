import Foundation

struct BenchmarkOutput: Codable {
    let evaluations: Int
    let elapsedMilliseconds: Double
    let evaluationsPerSecond: Double
    let checksum: Double
}

@main
enum MatchConfidenceBenchmark {
    static func main() throws {
        guard CommandLine.arguments.count == 2 else {
            FileHandle.standardError.write(
                Data("usage: benchmark-match-confidence <fixtures.json>\n".utf8)
            )
            exit(64)
        }

        let fixtureURL = URL(fileURLWithPath: CommandLine.arguments[1])
        let fixtures = try JSONDecoder().decode(
            [MatchCalibrationFixture].self,
            from: Data(contentsOf: fixtureURL)
        )
        guard !fixtures.isEmpty else { exit(65) }

        let iterationCount = 250_000
        var checksum = 0.0
        let started = Date.timeIntervalSinceReferenceDate
        for index in 0..<iterationCount {
            let confidence = MatchConfidenceEngine.evaluate(
                fixtures[index % fixtures.count].evidence
            )
            checksum += confidence.fixtureEstimatedProbability ?? 0
        }
        let elapsed = Date.timeIntervalSinceReferenceDate - started

        let output = BenchmarkOutput(
            evaluations: iterationCount,
            elapsedMilliseconds: elapsed * 1_000,
            evaluationsPerSecond: Double(iterationCount) / elapsed,
            checksum: checksum
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        print(String(decoding: try encoder.encode(output), as: UTF8.self))
    }
}
