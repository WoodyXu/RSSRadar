import Foundation
import GRDB
import RSSRadarCore

public final class TopicRepository {
    private let access: DatabaseAccess

    init(access: DatabaseAccess) {
        self.access = access
    }

    public func save(_ topic: Topic) throws {
        try access.write { db in
            try db.execute(
                sql: """
                    INSERT INTO topics (
                        id, name, normalized_name, description, original_ai_name, original_ai_description,
                        entities_json, status, importance_score, created_at, updated_at
                    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                    ON CONFLICT(id) DO UPDATE SET
                        name = excluded.name,
                        normalized_name = excluded.normalized_name,
                        description = excluded.description,
                        original_ai_name = excluded.original_ai_name,
                        original_ai_description = excluded.original_ai_description,
                        entities_json = excluded.entities_json,
                        status = excluded.status,
                        importance_score = excluded.importance_score,
                        created_at = excluded.created_at,
                        updated_at = excluded.updated_at
                    """,
                arguments: try topic.databaseArguments()
            )
        }
    }

    public func fetch(id: String) throws -> Topic? {
        try access.read { db in
            try Row.fetchOne(db, sql: "SELECT * FROM topics WHERE id = ?", arguments: [id]).map(Topic.init(row:))
        }
    }

    public func fetchAll() throws -> [Topic] {
        try access.read { db in
            try Row.fetchAll(db, sql: "SELECT * FROM topics ORDER BY updated_at DESC").map(Topic.init(row:))
        }
    }

    public func fetch(status: TopicStatus) throws -> [Topic] {
        try access.read { db in
            try Row.fetchAll(
                db,
                sql: "SELECT * FROM topics WHERE status = ? ORDER BY updated_at DESC",
                arguments: [status.rawValue]
            ).map(Topic.init(row:))
        }
    }

    public func fetch(status: TopicStatus, normalizedName: String) throws -> Topic? {
        try access.read { db in
            try Row.fetchOne(
                db,
                sql: "SELECT * FROM topics WHERE status = ? AND normalized_name = ? LIMIT 1",
                arguments: [status.rawValue, Self.normalizeName(normalizedName)]
            ).map(Topic.init(row:))
        }
    }

    public func delete(id: String) throws {
        try access.write { db in
            try db.execute(sql: "DELETE FROM topics WHERE id = ?", arguments: [id])
        }
    }

    static func normalizeName(_ name: String) -> String {
        name
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")
    }
}

private extension Topic {
    func databaseArguments() throws -> StatementArguments {
        [
            id,
            name,
            TopicRepository.normalizeName(name),
            description,
            originalAIName,
            originalAIDescription,
            try DatabaseCoding.jsonString(from: entities),
            status.rawValue,
            importanceScore,
            DatabaseCoding.string(from: createdAt),
            DatabaseCoding.string(from: updatedAt)
        ]
    }

    init(row: Row) throws {
        self.init(
            id: try row.requiredString("id"),
            name: try row.requiredString("name"),
            description: try row.requiredString("description"),
            originalAIName: row["original_ai_name"],
            originalAIDescription: row["original_ai_description"],
            entities: try DatabaseCoding.value(fromJSONString: row.requiredString("entities_json")),
            status: TopicStatus(rawValue: try row.requiredString("status"))!,
            importanceScore: row["importance_score"],
            createdAt: try row.requiredDate("created_at"),
            updatedAt: try row.requiredDate("updated_at")
        )
    }
}
