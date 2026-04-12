import Foundation
import GRDB

final class DatabaseManager: Sendable {
    static let shared = DatabaseManager()

    let dbPool: DatabasePool

    init() {
        guard let path = Bundle.main.path(forResource: "photos", ofType: "db") else {
            fatalError("photos.db not found in app bundle")
        }
        var config = Configuration()
        config.readonly = true
        do {
            dbPool = try DatabasePool(path: path, configuration: config)
        } catch {
            fatalError("Failed to open photos.db: \(error)")
        }
    }

    /// For testing with an in-memory or custom database
    init(dbPool: DatabasePool) {
        self.dbPool = dbPool
    }

    var photoCount: Int {
        get async throws {
            try await dbPool.read { db in
                try HistoricalPhoto.fetchCount(db)
            }
        }
    }

    /// Schema SQL for creating the table in test databases
    static let schema = """
        CREATE TABLE IF NOT EXISTS historical_photos (
            id                  TEXT PRIMARY KEY,
            source              TEXT NOT NULL,
            title               TEXT NOT NULL,
            description         TEXT,
            date_text           TEXT,
            date_year           INTEGER,
            lat                 REAL NOT NULL,
            lon                 REAL NOT NULL,
            city                TEXT,
            heading             REAL,
            heading_confidence  TEXT NOT NULL DEFAULT 'low',
            thumbnail_url       TEXT NOT NULL,
            full_res_url        TEXT,
            attribution         TEXT NOT NULL,
            rights_uri          TEXT,
            created_at          DATETIME DEFAULT CURRENT_TIMESTAMP
        );
        """
}
