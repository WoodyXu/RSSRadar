import GRDB
import XCTest
@testable import RSSRadarPersistence

final class DatabaseMigrationTests: XCTestCase {
    func testMigrationCreatesInitialTables() throws {
        let database = try makeTemporaryDatabase()
        try database.migrate()

        let tableNames = try database.queue.read { db in
            try String.fetchAll(
                db,
                sql: """
                    SELECT name
                    FROM sqlite_master
                    WHERE type = 'table'
                    ORDER BY name
                    """
            )
        }

        for expectedTable in InitialSchemaMigration.tableNames {
            XCTAssertTrue(tableNames.contains(expectedTable), "Missing table \(expectedTable)")
        }
    }

    func testSQLitePragmasAreConfigured() throws {
        let database = try makeTemporaryDatabase()
        try database.migrate()

        try database.queue.read { db in
            XCTAssertEqual(try Int.fetchOne(db, sql: "PRAGMA foreign_keys"), 1)
            XCTAssertEqual(try Int.fetchOne(db, sql: "PRAGMA busy_timeout"), 5_000)
            XCTAssertEqual(try String.fetchOne(db, sql: "PRAGMA journal_mode")?.lowercased(), "wal")
        }
    }

    func testForeignKeysCascadeFeedDeletesToArticlesAndAnalysis() throws {
        let database = try makeTemporaryDatabase()
        try database.migrate()

        try database.queue.write { db in
            try insertFeed(id: "feed-1", db: db)
            try insertArticle(id: "article-1", feedID: "feed-1", db: db)
            try insertArticleAnalysis(id: "analysis-1", articleID: "article-1", db: db)

            try db.execute(sql: "DELETE FROM feeds WHERE id = 'feed-1'")

            XCTAssertEqual(try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM articles"), 0)
            XCTAssertEqual(try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM article_analyses"), 0)
        }
    }

    func testForeignKeyConstraintRejectsOrphanArticle() throws {
        let database = try makeTemporaryDatabase()
        try database.migrate()

        XCTAssertThrowsError(
            try database.queue.write { db in
                try insertArticle(id: "orphan", feedID: "missing-feed", db: db)
            }
        ) { error in
            guard let databaseError = error as? DatabaseError else {
                return XCTFail("Expected DatabaseError, got \(error)")
            }

            XCTAssertEqual(databaseError.resultCode, .SQLITE_CONSTRAINT)
        }
    }

    func testMigrationCanRunRepeatedlyWithoutDestroyingData() throws {
        let database = try makeTemporaryDatabase()
        try database.migrate()

        try database.queue.write { db in
            try insertFeed(id: "feed-1", title: "Persisted Feed", db: db)
        }

        try database.migrate()

        try database.queue.read { db in
            XCTAssertEqual(try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM feeds"), 1)
            let title = try String.fetchOne(db, sql: "SELECT title FROM feeds WHERE id = 'feed-1'")
            XCTAssertEqual(title, "Persisted Feed")
        }
    }

    func testInvalidEnumValuesAreRejectedByChecks() throws {
        let database = try makeTemporaryDatabase()
        try database.migrate()

        XCTAssertThrowsError(
            try database.queue.write { db in
                try db.execute(
                    sql: """
                        INSERT INTO feeds (
                            id, title, url, status, created_at, updated_at
                        ) VALUES (
                            'feed-1', 'Feed', 'https://example.com/rss.xml', 'unknown', '2026-05-20T00:00:00Z',
                            '2026-05-20T00:00:00Z'
                        )
                        """
                )
            }
        )
    }

    func testProcessingJobEnumChecksRejectInvalidValues() throws {
        let database = try makeTemporaryDatabase()
        try database.migrate()

        XCTAssertThrowsError(
            try database.queue.write { db in
                try db.execute(
                    sql: """
                        INSERT INTO processing_jobs (
                            id, job_type, entity_type, payload_json, status, scheduled_at, created_at, updated_at
                        ) VALUES (
                            'job-1', 'unknown', 'feed', '{}', 'pending', '2026-05-20T00:00:00Z',
                            '2026-05-20T00:00:00Z', '2026-05-20T00:00:00Z'
                        )
                        """
                )
            }
        )
    }

    func testOperationLogLevelCheckRejectsInvalidValues() throws {
        let database = try makeTemporaryDatabase()
        try database.migrate()

        XCTAssertThrowsError(
            try database.queue.write { db in
                try db.execute(
                    sql: """
                        INSERT INTO operation_logs (
                            id, level, message, context_json, created_at
                        ) VALUES (
                            'log-1', 'debug', 'message', '{}', '2026-05-20T00:00:00Z'
                        )
                        """
                )
            }
        )
    }
}

private extension DatabaseMigrationTests {
    func makeTemporaryDatabase() throws -> RSSRadarDatabase {
        let directoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("RSSRadarPersistenceTests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let databaseURL = directoryURL.appendingPathComponent("rssradar.sqlite")

        return try RSSRadarDatabase(path: databaseURL.path)
    }

    func insertFeed(id: String, title: String = "Feed", db: Database) throws {
        try db.execute(
            sql: """
                INSERT INTO feeds (
                    id, title, url, status, created_at, updated_at
                ) VALUES (?, ?, ?, ?, ?, ?)
                """,
            arguments: [
                id,
                title,
                "https://example.com/\(id).xml",
                "active",
                "2026-05-20T00:00:00Z",
                "2026-05-20T00:00:00Z"
            ]
        )
    }

    func insertArticle(id: String, feedID: String, db: Database) throws {
        try db.execute(
            sql: """
                INSERT INTO articles (
                    id, feed_id, title, url, status, created_at, updated_at
                ) VALUES (?, ?, ?, ?, ?, ?, ?)
                """,
            arguments: [
                id,
                feedID,
                "Article \(id)",
                "https://example.com/articles/\(id)",
                "fetched",
                "2026-05-20T00:00:00Z",
                "2026-05-20T00:00:00Z"
            ]
        )
    }

    func insertArticleAnalysis(id: String, articleID: String, db: Database) throws {
        try db.execute(
            sql: """
                INSERT INTO article_analyses (
                    id, article_id, summary, key_points_json, entities_json, claims_json, events_json,
                    metrics_json, content_type, possible_topics_json, importance_score, model_name, generated_at
                ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                """,
            arguments: [
                id,
                articleID,
                "Summary",
                "[]",
                "[]",
                "[]",
                "[]",
                "[]",
                "analysis",
                "[]",
                0.7,
                "test-model",
                "2026-05-20T00:00:00Z"
            ]
        )
    }
}
