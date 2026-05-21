import Foundation
import GRDB
import RSSRadarCore

public final class TopicBriefRepository {
    private let access: DatabaseAccess

    init(access: DatabaseAccess) {
        self.access = access
    }

    public func save(_ brief: TopicBrief) throws {
        try access.write { db in
            try db.execute(
                sql: """
                    INSERT INTO topic_briefs (
                        id, topic_id, brief_type, current_takeaway, latest_changes_json, timeline_json,
                        viewpoints_json, evidence_json, questions_to_watch_json, related_article_ids_json,
                        model_name, generated_at
                    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                    ON CONFLICT(topic_id, brief_type) DO UPDATE SET
                        id = excluded.id,
                        current_takeaway = excluded.current_takeaway,
                        latest_changes_json = excluded.latest_changes_json,
                        timeline_json = excluded.timeline_json,
                        viewpoints_json = excluded.viewpoints_json,
                        evidence_json = excluded.evidence_json,
                        questions_to_watch_json = excluded.questions_to_watch_json,
                        related_article_ids_json = excluded.related_article_ids_json,
                        model_name = excluded.model_name,
                        generated_at = excluded.generated_at
                    """,
                arguments: try brief.databaseArguments()
            )
        }
    }

    public func fetch(id: String) throws -> TopicBrief? {
        try access.read { db in
            try Row.fetchOne(
                db,
                sql: "SELECT * FROM topic_briefs WHERE id = ?",
                arguments: [id]
            ).map(TopicBrief.init(row:))
        }
    }

    public func fetch(topicID: String, briefType: TopicBriefType) throws -> TopicBrief? {
        try access.read { db in
            try Row.fetchOne(
                db,
                sql: "SELECT * FROM topic_briefs WHERE topic_id = ? AND brief_type = ?",
                arguments: [topicID, briefType.rawValue]
            ).map(TopicBrief.init(row:))
        }
    }

    public func fetchForTopic(id: String) throws -> [TopicBrief] {
        try access.read { db in
            try Row.fetchAll(
                db,
                sql: "SELECT * FROM topic_briefs WHERE topic_id = ? ORDER BY generated_at DESC",
                arguments: [id]
            ).map(TopicBrief.init(row:))
        }
    }

    public func delete(id: String) throws {
        try access.write { db in
            try db.execute(sql: "DELETE FROM topic_briefs WHERE id = ?", arguments: [id])
        }
    }
}

private extension TopicBrief {
    func databaseArguments() throws -> StatementArguments {
        [
            id,
            topicID,
            briefType.rawValue,
            currentTakeaway,
            try DatabaseCoding.jsonString(from: latestChanges),
            try DatabaseCoding.jsonString(from: timeline),
            try DatabaseCoding.jsonString(from: viewpoints),
            try DatabaseCoding.jsonString(from: evidence),
            try DatabaseCoding.jsonString(from: questionsToWatch),
            try DatabaseCoding.jsonString(from: relatedArticleIDs),
            modelName,
            DatabaseCoding.string(from: generatedAt)
        ]
    }

    init(row: Row) throws {
        self.init(
            id: try row.requiredString("id"),
            topicID: try row.requiredString("topic_id"),
            briefType: TopicBriefType(rawValue: try row.requiredString("brief_type"))!,
            currentTakeaway: try row.requiredString("current_takeaway"),
            latestChanges: try DatabaseCoding.value(fromJSONString: row.requiredString("latest_changes_json")),
            timeline: try DatabaseCoding.value(fromJSONString: row.requiredString("timeline_json")),
            viewpoints: try DatabaseCoding.value(fromJSONString: row.requiredString("viewpoints_json")),
            evidence: try DatabaseCoding.value(fromJSONString: row.requiredString("evidence_json")),
            questionsToWatch: try DatabaseCoding.value(fromJSONString: row.requiredString("questions_to_watch_json")),
            relatedArticleIDs: try DatabaseCoding.value(fromJSONString: row.requiredString("related_article_ids_json")),
            modelName: try row.requiredString("model_name"),
            generatedAt: try row.requiredDate("generated_at")
        )
    }
}
