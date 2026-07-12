import Foundation
import GRDB

final class DatabaseManager: Sendable {
    enum BundledDatabaseError: LocalizedError {
        case missing
        case unreadable(underlying: Error)

        var errorDescription: String? {
            switch self {
            case .missing:
                return "The historical photo database is missing from this build."
            case .unreadable:
                return "The historical photo database could not be opened."
            }
        }
    }

    static let shared: Result<DatabaseManager, Error> = Result {
        try DatabaseManager()
    }

    let dbPool: any DatabaseReader

    init() throws {
        guard let path = Bundle.main.path(forResource: "photos", ofType: "db") else {
            throw BundledDatabaseError.missing
        }
        var config = Configuration()
        config.readonly = true
        do {
            dbPool = try DatabasePool(path: path, configuration: config)
        } catch {
            throw BundledDatabaseError.unreadable(underlying: error)
        }
    }

    /// For testing with an in-memory or custom database
    init(dbPool: any DatabaseReader) {
        self.dbPool = dbPool
    }

    var photoCount: Int {
        get async throws {
            try await dbPool.read { db in
                try HistoricalPhoto.fetchCount(db)
            }
        }
    }

    func photos(in cityID: String, limit: Int = 200) async throws -> [HistoricalPhoto] {
        try await dbPool.read { db in
            try HistoricalPhoto
                .filter(HistoricalPhoto.Columns.city == cityID)
                .order(HistoricalPhoto.Columns.dateYear.ascNullsLast)
                .limit(limit)
                .fetchAll(db)
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
