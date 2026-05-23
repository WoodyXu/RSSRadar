import Foundation
import GRDB
import RSSRadarCore

public final class ArticleRepository {
    private let access: DatabaseAccess

    init(access: DatabaseAccess) {
        self.access = access
    }

    public func save(_ article: Article) throws {
        try access.write { db in
            try db.execute(
                sql: """
                    INSERT INTO articles (
                        id, feed_id, title, url, author, published_at, rss_summary, content,
                        content_source, status, importance_score, error_message, created_at, updated_at
                    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                    ON CONFLICT(id) DO UPDATE SET
                        feed_id = excluded.feed_id,
                        title = excluded.title,
                        url = excluded.url,
                        author = excluded.author,
                        published_at = excluded.published_at,
                        rss_summary = excluded.rss_summary,
                        content = excluded.content,
                        content_source = excluded.content_source,
                        status = excluded.status,
                        importance_score = excluded.importance_score,
                        error_message = excluded.error_message,
                        created_at = excluded.created_at,
                        updated_at = excluded.updated_at
                    """,
                arguments: article.databaseArguments
            )
        }
    }

    public func fetch(id: String) throws -> Article? {
        try access.read { db in
            try Row.fetchOne(db, sql: "SELECT * FROM articles WHERE id = ?", arguments: [id]).map(Article.init(row:))
        }
    }

    public func fetchAll() throws -> [Article] {
        try access.read { db in
            try Row.fetchAll(db, sql: "SELECT * FROM articles ORDER BY created_at DESC").map(Article.init(row:))
        }
    }

    public func fetch(ids: [String]) throws -> [Article] {
        guard !ids.isEmpty else {
            return []
        }

        let placeholders = Array(repeating: "?", count: ids.count).joined(separator: ", ")
        return try access.read { db in
            try Row.fetchAll(
                db,
                sql: "SELECT * FROM articles WHERE id IN (\(placeholders))",
                arguments: StatementArguments(ids)
            ).map(Article.init(row:))
        }
    }

    public func fetch(feedID: String) throws -> [Article] {
        try access.read { db in
            try Row.fetchAll(
                db,
                sql: "SELECT * FROM articles WHERE feed_id = ? ORDER BY published_at DESC, created_at DESC",
                arguments: [feedID]
            ).map(Article.init(row:))
        }
    }

    public func fetchGroupedByFeedID() throws -> [String: [Article]] {
        let articles = try fetchAll()
        return Dictionary(grouping: articles, by: \.feedID)
    }

    public func fetch(status: ArticleStatus) throws -> [Article] {
        try access.read { db in
            try Row.fetchAll(
                db,
                sql: "SELECT * FROM articles WHERE status = ? ORDER BY created_at DESC",
                arguments: [status.rawValue]
            ).map(Article.init(row:))
        }
    }

    public func countUpdated(since: Date, statuses: [ArticleStatus]) throws -> Int {
        guard !statuses.isEmpty else {
            return 0
        }

        let placeholders = Array(repeating: "?", count: statuses.count).joined(separator: ", ")
        var arguments = StatementArguments(statuses.map(\.rawValue))
        arguments += [DatabaseCoding.string(from: since)]
        return try access.read { db in
            try Int.fetchOne(
                db,
                sql: """
                    SELECT COUNT(*)
                    FROM articles
                    WHERE status IN (\(placeholders)) AND updated_at >= ?
                    """,
                arguments: arguments
            ) ?? 0
        }
    }

    public func count(status: ArticleStatus) throws -> Int {
        try access.read { db in
            try Int.fetchOne(
                db,
                sql: "SELECT COUNT(*) FROM articles WHERE status = ?",
                arguments: [status.rawValue]
            ) ?? 0
        }
    }

    public func delete(id: String) throws {
        try access.write { db in
            try db.execute(sql: "DELETE FROM articles WHERE id = ?", arguments: [id])
        }
    }
}

private extension Article {
    var databaseArguments: StatementArguments {
        [
            id,
            feedID,
            title,
            url.absoluteString,
            author,
            publishedAt.map(DatabaseCoding.string(from:)),
            rssSummary,
            content,
            contentSource?.rawValue,
            status.rawValue,
            importanceScore,
            errorMessage,
            DatabaseCoding.string(from: createdAt),
            DatabaseCoding.string(from: updatedAt)
        ]
    }

    init(row: Row) throws {
        let contentSourceValue: String? = row["content_source"]

        self.init(
            id: try row.requiredString("id"),
            feedID: try row.requiredString("feed_id"),
            title: try row.requiredString("title"),
            url: try row.requiredURL("url"),
            author: row["author"],
            publishedAt: try row.optionalDate("published_at"),
            rssSummary: row["rss_summary"],
            content: row["content"],
            contentSource: contentSourceValue.flatMap(ArticleContentSource.init(rawValue:)),
            status: ArticleStatus(rawValue: try row.requiredString("status"))!,
            importanceScore: row["importance_score"],
            errorMessage: row["error_message"],
            createdAt: try row.requiredDate("created_at"),
            updatedAt: try row.requiredDate("updated_at")
        )
    }
}
