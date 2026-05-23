import Foundation
import GRDB
import RSSRadarCore

public final class UserCorrectionRepository {
    private let access: DatabaseAccess

    init(access: DatabaseAccess) {
        self.access = access
    }

    public func save(_ correction: UserCorrection) throws {
        try access.write { db in
            try db.execute(
                sql: """
                    INSERT INTO user_corrections (
                        id, correction_type, topic_id, article_id, old_value, new_value, created_at
                    ) VALUES (?, ?, ?, ?, ?, ?, ?)
                    ON CONFLICT(id) DO UPDATE SET
                        correction_type = excluded.correction_type,
                        topic_id = excluded.topic_id,
                        article_id = excluded.article_id,
                        old_value = excluded.old_value,
                        new_value = excluded.new_value,
                        created_at = excluded.created_at
                    """,
                arguments: correction.databaseArguments
            )
        }
    }

    public func fetch(id: String) throws -> UserCorrection? {
        try access.read { db in
            try Row.fetchOne(
                db,
                sql: "SELECT * FROM user_corrections WHERE id = ?",
                arguments: [id]
            ).map(UserCorrection.init(row:))
        }
    }

    public func fetchAll() throws -> [UserCorrection] {
        try access.read { db in
            try Row.fetchAll(
                db,
                sql: "SELECT * FROM user_corrections ORDER BY created_at DESC"
            ).map(UserCorrection.init(row:))
        }
    }

    public func fetchForTopic(id topicID: String) throws -> [UserCorrection] {
        try access.read { db in
            try Row.fetchAll(
                db,
                sql: "SELECT * FROM user_corrections WHERE topic_id = ? ORDER BY created_at DESC",
                arguments: [topicID]
            ).map(UserCorrection.init(row:))
        }
    }

    public func fetchForArticle(id articleID: String) throws -> [UserCorrection] {
        try access.read { db in
            try Row.fetchAll(
                db,
                sql: "SELECT * FROM user_corrections WHERE article_id = ? ORDER BY created_at DESC",
                arguments: [articleID]
            ).map(UserCorrection.init(row:))
        }
    }

    public func delete(id: String) throws {
        try access.write { db in
            try db.execute(sql: "DELETE FROM user_corrections WHERE id = ?", arguments: [id])
        }
    }
}

private extension UserCorrection {
    var databaseArguments: StatementArguments {
        [
            id,
            correctionType.rawValue,
            topicID,
            articleID,
            oldValue,
            newValue,
            DatabaseCoding.string(from: createdAt)
        ]
    }

    init(row: Row) throws {
        self.init(
            id: try row.requiredString("id"),
            correctionType: UserCorrectionType(rawValue: try row.requiredString("correction_type"))!,
            topicID: row["topic_id"],
            articleID: row["article_id"],
            oldValue: row["old_value"],
            newValue: row["new_value"],
            createdAt: try row.requiredDate("created_at")
        )
    }
}
