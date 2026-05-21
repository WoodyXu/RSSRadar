import Foundation
import GRDB
import RSSRadarCore

public final class ArticleAnalysisRepository {
    private let access: DatabaseAccess

    init(access: DatabaseAccess) {
        self.access = access
    }

    public func save(_ analysis: ArticleAnalysis) throws {
        try access.write { db in
            try db.execute(
                sql: """
                    INSERT INTO article_analyses (
                        id, article_id, summary, key_points_json, entities_json, claims_json, events_json,
                        metrics_json, content_type, possible_topics_json, importance_score, model_name, generated_at
                    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                    ON CONFLICT(article_id) DO UPDATE SET
                        id = excluded.id,
                        summary = excluded.summary,
                        key_points_json = excluded.key_points_json,
                        entities_json = excluded.entities_json,
                        claims_json = excluded.claims_json,
                        events_json = excluded.events_json,
                        metrics_json = excluded.metrics_json,
                        content_type = excluded.content_type,
                        possible_topics_json = excluded.possible_topics_json,
                        importance_score = excluded.importance_score,
                        model_name = excluded.model_name,
                        generated_at = excluded.generated_at
                    """,
                arguments: try analysis.databaseArguments()
            )
        }
    }

    public func fetch(id: String) throws -> ArticleAnalysis? {
        try access.read { db in
            try Row.fetchOne(
                db,
                sql: "SELECT * FROM article_analyses WHERE id = ?",
                arguments: [id]
            ).map(ArticleAnalysis.init(row:))
        }
    }

    public func fetch(articleID: String) throws -> ArticleAnalysis? {
        try access.read { db in
            try Row.fetchOne(
                db,
                sql: "SELECT * FROM article_analyses WHERE article_id = ?",
                arguments: [articleID]
            ).map(ArticleAnalysis.init(row:))
        }
    }

    public func fetchAll() throws -> [ArticleAnalysis] {
        try access.read { db in
            try Row.fetchAll(
                db,
                sql: "SELECT * FROM article_analyses ORDER BY generated_at DESC"
            ).map(ArticleAnalysis.init(row:))
        }
    }

    public func delete(id: String) throws {
        try access.write { db in
            try db.execute(sql: "DELETE FROM article_analyses WHERE id = ?", arguments: [id])
        }
    }
}

private extension ArticleAnalysis {
    func databaseArguments() throws -> StatementArguments {
        [
            id,
            articleID,
            summary,
            try DatabaseCoding.jsonString(from: keyPoints),
            try DatabaseCoding.jsonString(from: entities),
            try DatabaseCoding.jsonString(from: claims),
            try DatabaseCoding.jsonString(from: events),
            try DatabaseCoding.jsonString(from: metrics),
            contentType.rawValue,
            try DatabaseCoding.jsonString(from: possibleTopics),
            importanceScore,
            modelName,
            DatabaseCoding.string(from: generatedAt)
        ]
    }

    init(row: Row) throws {
        self.init(
            id: try row.requiredString("id"),
            articleID: try row.requiredString("article_id"),
            summary: try row.requiredString("summary"),
            keyPoints: try DatabaseCoding.value(fromJSONString: row.requiredString("key_points_json")),
            entities: try DatabaseCoding.value(fromJSONString: row.requiredString("entities_json")),
            claims: try DatabaseCoding.value(fromJSONString: row.requiredString("claims_json")),
            events: try DatabaseCoding.value(fromJSONString: row.requiredString("events_json")),
            metrics: try DatabaseCoding.value(fromJSONString: row.requiredString("metrics_json")),
            contentType: ArticleContentType(rawValue: try row.requiredString("content_type"))!,
            possibleTopics: try DatabaseCoding.value(fromJSONString: row.requiredString("possible_topics_json")),
            importanceScore: try row.requiredDouble("importance_score"),
            modelName: try row.requiredString("model_name"),
            generatedAt: try row.requiredDate("generated_at")
        )
    }
}
