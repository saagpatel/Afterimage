import Foundation

enum LocalPairStoreError: Error {
    case applicationSupportUnavailable
}

/// Saves a rendered before/after plate only inside the app container. It never
/// writes to Photos, iCloud, an archive host, or an analytics service.
struct LocalPairStore {
    private let rootDirectory: URL?
    private let fileManager: FileManager

    init(rootDirectory: URL? = nil, fileManager: FileManager = .default) {
        self.rootDirectory = rootDirectory
        self.fileManager = fileManager
    }

    func save(pngData: Data, now: Date = Date()) throws -> URL {
        let root: URL
        if let rootDirectory {
            root = rootDirectory
        } else {
            guard let applicationSupport = fileManager.urls(
                for: .applicationSupportDirectory,
                in: .userDomainMask
            ).first else {
                throw LocalPairStoreError.applicationSupportUnavailable
            }
            root = applicationSupport.appendingPathComponent(
                "AfterimagePairs",
                isDirectory: true
            )
        }

        try fileManager.createDirectory(
            at: root,
            withIntermediateDirectories: true,
            attributes: [.protectionKey: FileProtectionType.complete]
        )

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        let timestamp = formatter.string(from: now)
            .replacingOccurrences(of: ":", with: "-")
        let destination = root.appendingPathComponent(
            "afterimage-\(timestamp)-\(UUID().uuidString.prefix(8)).png"
        )
        try pngData.write(to: destination, options: [.atomic])
        try fileManager.setAttributes(
            [.protectionKey: FileProtectionType.complete],
            ofItemAtPath: destination.path
        )
        return destination
    }
}
