import Foundation
import GRDB
import RSSRadarCore

public final class TopicArticleRepository {
    private let access: DatabaseAccess

    init(access: DatabaseAccess) {
        self.access = access
    }

    public func save(_ topicArticle: TopicArticle) throws {
        try access.write { db in
            try db.execute(
                sql: """
                    INSERT INTO topic_articles (
                        topic_id, article_id, confidence, reason, contribution_type, created_at
                    ) VALUES (?, ?, ?, ?, ?, ?)
                    ON CONFLICT(topic_id, article_id) DO UPDATE SET
                        confidence = excluded.confidence,
                        reason = excluded.reason,
                        contribution_type = excluded.contribution_type,
                        created_at = excluded.created_at
                    """,
                arguments: topicArticle.databaseArguments
            )
        }
    }

    public func fetch(topicID: String, articleID: String) throws -> TopicArticle? {
        try access.read { db in
            try Row.fetchOne(
                db,
                sql: "SELECT * FROM topic_articles WHERE topic_id = ? AND article_id = ?",
                arguments: [topicID, articleID]
            ).map(TopicArticle.init(row:))
        }
    }

    public func fetchAll() throws -> [TopicArticle] {
        try access.read { db in
            try Row.fetchAll(
                db,
                sql: "SELECT * FROM topic_articles ORDER BY created_at DESC"
            ).map(TopicArticle.init(row:))
        }
    }

    public func fetchForTopic(id: String) throws -> [TopicArticle] {
        try access.read { db in
            try Row.fetchAll(
                db,
                sql: "SELECT * FROM topic_articles WHERE topic_id = ? ORDER BY created_at DESC",
                arguments: [id]
            ).map(TopicArticle.init(row:))
        }
    }

    public func fetchForArticle(id: String) throws -> [TopicArticle] {
        try access.read { db in
            try Row.fetchAll(
                db,
                sql: "SELECT * FROM topic_articles WHERE article_id = ? ORDER BY created_at DESC",
                arguments: [id]
            ).map(TopicArticle.init(row:))
        }
    }

    public func delete(topicID: String, articleID: String) throws {
        try access.write { db in
            try db.execute(
                sql: "DELETE FROM topic_articles WHERE topic_id = ? AND article_id = ?",
                arguments: [topicID, articleID]
            )
        }
    }
}

private extension TopicArticle {
    var databaseArguments: StatementArguments {
        [
            topicID,
            articleID,
            confidence,
            reason,
            contributionType.rawValue,
            DatabaseCoding.string(from: createdAt)
        ]
    }

    init(row: Row) throws {
        self.init(
            topicID: try row.requiredString("topic_id"),
            articleID: try row.requiredString("article_id"),
            confidence: try row.requiredDouble("confidence"),
            reason: try row.requiredString("reason"),
            contributionType: TopicContributionType(rawValue: try row.requiredString("contribution_type"))!,
            createdAt: try row.requiredDate("created_at")
        )
    }
}
