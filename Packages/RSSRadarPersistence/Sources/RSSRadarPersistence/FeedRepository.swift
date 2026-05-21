import Foundation
import GRDB
import RSSRadarCore

public final class FeedRepository {
    private let access: DatabaseAccess

    init(access: DatabaseAccess) {
        self.access = access
    }

    public func save(_ feed: Feed) throws {
        try access.write { db in
            try db.execute(
                sql: """
                    INSERT INTO feeds (
                        id, title, url, site_url, status, last_checked_at, last_success_at,
                        last_processed_article_published_at, error_message, created_at, updated_at
                    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                    ON CONFLICT(id) DO UPDATE SET
                        title = excluded.title,
                        url = excluded.url,
                        site_url = excluded.site_url,
                        status = excluded.status,
                        last_checked_at = excluded.last_checked_at,
                        last_success_at = excluded.last_success_at,
                        last_processed_article_published_at = excluded.last_processed_article_published_at,
                        error_message = excluded.error_message,
                        created_at = excluded.created_at,
                        updated_at = excluded.updated_at
                    """,
                arguments: feed.databaseArguments
            )
        }
    }

    public func fetch(id: String) throws -> Feed? {
        try access.read { db in
            try Row.fetchOne(db, sql: "SELECT * FROM feeds WHERE id = ?", arguments: [id]).map(Feed.init(row:))
        }
    }

    public func fetchAll() throws -> [Feed] {
        try access.read { db in
            try Row.fetchAll(db, sql: "SELECT * FROM feeds ORDER BY title ASC").map(Feed.init(row:))
        }
    }

    public func fetch(status: FeedStatus) throws -> [Feed] {
        try access.read { db in
            try Row.fetchAll(
                db,
                sql: "SELECT * FROM feeds WHERE status = ? ORDER BY title ASC",
                arguments: [status.rawValue]
            ).map(Feed.init(row:))
        }
    }

    public func delete(id: String) throws {
        try access.write { db in
            try db.execute(sql: "DELETE FROM feeds WHERE id = ?", arguments: [id])
        }
    }
}

private extension Feed {
    var databaseArguments: StatementArguments {
        [
            id,
            title,
            url.absoluteString,
            siteURL?.absoluteString,
            status.rawValue,
            lastCheckedAt.map(DatabaseCoding.string(from:)),
            lastSuccessAt.map(DatabaseCoding.string(from:)),
            lastProcessedArticlePublishedAt.map(DatabaseCoding.string(from:)),
            errorMessage,
            DatabaseCoding.string(from: createdAt),
            DatabaseCoding.string(from: updatedAt)
        ]
    }

    init(row: Row) throws {
        self.init(
            id: try row.requiredString("id"),
            title: try row.requiredString("title"),
            url: try row.requiredURL("url"),
            siteURL: try row.optionalURL("site_url"),
            status: FeedStatus(rawValue: try row.requiredString("status"))!,
            lastCheckedAt: try row.optionalDate("last_checked_at"),
            lastSuccessAt: try row.optionalDate("last_success_at"),
            lastProcessedArticlePublishedAt: try row.optionalDate("last_processed_article_published_at"),
            errorMessage: row["error_message"],
            createdAt: try row.requiredDate("created_at"),
            updatedAt: try row.requiredDate("updated_at")
        )
    }
}
