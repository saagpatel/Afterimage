import XCTest
@testable import Afterimage

final class LocalPairStoreTests: XCTestCase {
    func testSaveWritesOnlyInsideInjectedLocalDirectory() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let payload = Data([0x89, 0x50, 0x4E, 0x47])
        let destination = try LocalPairStore(rootDirectory: root).save(
            pngData: payload,
            now: Date(timeIntervalSince1970: 0)
        )

        XCTAssertEqual(destination.deletingLastPathComponent(), root)
        XCTAssertEqual(try Data(contentsOf: destination), payload)
        XCTAssertEqual(destination.pathExtension, "png")
    }

    func testSeparateSavesNeverOverwrite() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = LocalPairStore(rootDirectory: root)

        let first = try store.save(pngData: Data([1]), now: .distantPast)
        let second = try store.save(pngData: Data([2]), now: .distantPast)

        XCTAssertNotEqual(first, second)
        XCTAssertEqual(try Data(contentsOf: first), Data([1]))
        XCTAssertEqual(try Data(contentsOf: second), Data([2]))
    }
}
