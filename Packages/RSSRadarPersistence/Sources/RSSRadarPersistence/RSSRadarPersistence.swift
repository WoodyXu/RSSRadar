import Foundation
import GRDB

public enum RSSRadarPersistence {
    public static let moduleName = "RSSRadarPersistence"
}

public enum RSSRadarDatabaseError: Error, Equatable {
    case unableToCreateDatabaseDirectory(URL)
}

public final class RSSRadarDatabase {
    public static let defaultBusyTimeoutMilliseconds = 5_000

    let queue: DatabaseQueue

    public init(path: String) throws {
        let databaseURL = URL(fileURLWithPath: path)
        try Self.createParentDirectory(for: databaseURL)

        var configuration = Configuration()
        configuration.prepareDatabase { db in
            try db.execute(sql: "PRAGMA foreign_keys = ON")
            try db.execute(sql: "PRAGMA busy_timeout = \(Self.defaultBusyTimeoutMilliseconds)")
        }

        queue = try DatabaseQueue(path: path, configuration: configuration)
        try configureJournalMode()
    }

    public func migrate() throws {
        var migrator = DatabaseMigrator()
        migrator.registerMigration("v1_create_initial_schema") { db in
            try InitialSchemaMigration.apply(to: db)
        }
        try migrator.migrate(queue)
    }

    private func configureJournalMode() throws {
        try queue.inDatabase { db in
            _ = try String.fetchOne(db, sql: "PRAGMA journal_mode = WAL")
            try db.execute(sql: "PRAGMA foreign_keys = ON")
            try db.execute(sql: "PRAGMA busy_timeout = \(Self.defaultBusyTimeoutMilliseconds)")
        }
    }

    private static func createParentDirectory(for databaseURL: URL) throws {
        let directoryURL = databaseURL.deletingLastPathComponent()

        do {
            try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        } catch {
            throw RSSRadarDatabaseError.unableToCreateDatabaseDirectory(directoryURL)
        }
    }
}

enum InitialSchemaMigration {
    static let tableNames: [String] = [
        "feeds",
        "articles",
        "article_analyses",
        "topics",
        "topic_articles",
        "topic_briefs",
        "app_settings",
        "processing_jobs",
        "operation_logs"
    ]

    static func apply(to db: Database) throws {
        try db.execute(sql: feedTableSQL)
        try db.execute(sql: articleTableSQL)
        try db.execute(sql: articleAnalysisTableSQL)
        try db.execute(sql: topicTableSQL)
        try db.execute(sql: topicArticleTableSQL)
        try db.execute(sql: topicBriefTableSQL)
        try db.execute(sql: appSettingsTableSQL)
        try db.execute(sql: processingJobTableSQL)
        try db.execute(sql: operationLogTableSQL)
        try createIndexes(on: db)
    }

    private static func createIndexes(on db: Database) throws {
        try db.execute(sql: "CREATE INDEX idx_articles_feed_id ON articles(feed_id)")
        try db.execute(sql: "CREATE INDEX idx_articles_published_at ON articles(published_at)")
        try db.execute(sql: "CREATE INDEX idx_article_analyses_article_id ON article_analyses(article_id)")
        try db.execute(sql: "CREATE INDEX idx_topics_status ON topics(status)")
        try db.execute(sql: "CREATE INDEX idx_topic_articles_article_id ON topic_articles(article_id)")
        try db.execute(sql: "CREATE INDEX idx_topic_briefs_topic_id ON topic_briefs(topic_id)")
        try db.execute(sql: "CREATE INDEX idx_processing_jobs_status_schedule ON processing_jobs(status, scheduled_at)")
        try db.execute(sql: "CREATE INDEX idx_processing_jobs_entity ON processing_jobs(entity_type, entity_id)")
        try db.execute(sql: "CREATE INDEX idx_operation_logs_created_at ON operation_logs(created_at)")
    }

    private static let feedTableSQL = """
        CREATE TABLE feeds (
            id TEXT PRIMARY KEY,
            title TEXT NOT NULL,
            url TEXT NOT NULL,
            site_url TEXT,
            status TEXT NOT NULL CHECK (status IN ('active', 'error', 'paused', 'no_articles')),
            last_checked_at TEXT,
            last_success_at TEXT,
            last_processed_article_published_at TEXT,
            error_message TEXT,
            created_at TEXT NOT NULL,
            updated_at TEXT NOT NULL
        )
        """

    private static let articleTableSQL = """
        CREATE TABLE articles (
            id TEXT PRIMARY KEY,
            feed_id TEXT NOT NULL REFERENCES feeds(id) ON DELETE CASCADE,
            title TEXT NOT NULL,
            url TEXT NOT NULL,
            author TEXT,
            published_at TEXT,
            rss_summary TEXT,
            content TEXT,
            content_source TEXT CHECK (
                content_source IS NULL
                OR content_source IN ('rss_full_content', 'web_extracted', 'rss_summary')
            ),
            status TEXT NOT NULL CHECK (
                status IN ('fetched', 'parsed', 'analyzed', 'assigned', 'ignored', 'failed')
            ),
            importance_score REAL,
            error_message TEXT,
            created_at TEXT NOT NULL,
            updated_at TEXT NOT NULL
        )
        """

    private static let articleAnalysisTableSQL = """
        CREATE TABLE article_analyses (
            id TEXT PRIMARY KEY,
            article_id TEXT NOT NULL UNIQUE REFERENCES articles(id) ON DELETE CASCADE,
            summary TEXT NOT NULL,
            key_points_json TEXT NOT NULL,
            entities_json TEXT NOT NULL,
            claims_json TEXT NOT NULL,
            events_json TEXT NOT NULL,
            metrics_json TEXT NOT NULL,
            content_type TEXT NOT NULL CHECK (
                content_type IN ('news', 'analysis', 'opinion', 'tutorial', 'announcement')
            ),
            possible_topics_json TEXT NOT NULL,
            importance_score REAL NOT NULL,
            model_name TEXT NOT NULL,
            generated_at TEXT NOT NULL
        )
        """

    private static let topicTableSQL = """
        CREATE TABLE topics (
            id TEXT PRIMARY KEY,
            name TEXT NOT NULL,
            normalized_name TEXT NOT NULL,
            description TEXT NOT NULL,
            original_ai_name TEXT,
            original_ai_description TEXT,
            entities_json TEXT NOT NULL,
            status TEXT NOT NULL CHECK (status IN ('candidate', 'active', 'ignored', 'archived')),
            importance_score REAL,
            created_at TEXT NOT NULL,
            updated_at TEXT NOT NULL
        )
        """

    private static let topicArticleTableSQL = """
        CREATE TABLE topic_articles (
            topic_id TEXT NOT NULL REFERENCES topics(id) ON DELETE CASCADE,
            article_id TEXT NOT NULL REFERENCES articles(id) ON DELETE CASCADE,
            confidence REAL NOT NULL,
            reason TEXT NOT NULL,
            contribution_type TEXT NOT NULL CHECK (
                contribution_type IN ('new_event', 'new_opinion', 'new_data', 'background')
            ),
            created_at TEXT NOT NULL,
            PRIMARY KEY (topic_id, article_id)
        )
        """

    private static let topicBriefTableSQL = """
        CREATE TABLE topic_briefs (
            id TEXT PRIMARY KEY,
            topic_id TEXT NOT NULL REFERENCES topics(id) ON DELETE CASCADE,
            brief_type TEXT NOT NULL CHECK (brief_type IN ('full', 'preview')),
            current_takeaway TEXT NOT NULL,
            latest_changes_json TEXT NOT NULL,
            timeline_json TEXT NOT NULL,
            viewpoints_json TEXT NOT NULL,
            evidence_json TEXT NOT NULL,
            questions_to_watch_json TEXT NOT NULL,
            related_article_ids_json TEXT NOT NULL,
            model_name TEXT NOT NULL,
            generated_at TEXT NOT NULL,
            UNIQUE (topic_id, brief_type)
        )
        """

    private static let appSettingsTableSQL = """
        CREATE TABLE app_settings (
            id TEXT PRIMARY KEY CHECK (id = 'default'),
            ai_provider TEXT NOT NULL CHECK (ai_provider IN ('openai_compatible', 'anthropic', 'custom')),
            base_url TEXT NOT NULL,
            model_name TEXT NOT NULL,
            database_path TEXT,
            keychain_account_identifier TEXT,
            scan_mode TEXT NOT NULL CHECK (scan_mode IN ('manual', 'on_launch', 'interval')),
            scan_interval_hours INTEGER NOT NULL,
            max_articles_per_scan INTEGER NOT NULL,
            max_articles_for_new_feed INTEGER NOT NULL,
            max_articles_per_topic_batch INTEGER NOT NULL,
            ai_request_timeout_seconds INTEGER NOT NULL,
            updated_at TEXT NOT NULL
        )
        """

    private static let processingJobTableSQL = """
        CREATE TABLE processing_jobs (
            id TEXT PRIMARY KEY,
            job_type TEXT NOT NULL CHECK (
                job_type IN (
                    'fetch_feed', 'parse_article', 'analyze_article',
                    'assign_topics', 'generate_topic_brief', 'retry_failed_job'
                )
            ),
            entity_type TEXT NOT NULL CHECK (entity_type IN ('feed', 'article', 'topic', 'topic_brief', 'job')),
            entity_id TEXT,
            payload_json TEXT NOT NULL,
            status TEXT NOT NULL CHECK (status IN ('pending', 'running', 'completed', 'failed')),
            priority INTEGER NOT NULL DEFAULT 0,
            attempt_count INTEGER NOT NULL DEFAULT 0,
            max_attempts INTEGER NOT NULL DEFAULT 3,
            last_error_message TEXT,
            scheduled_at TEXT NOT NULL,
            started_at TEXT,
            finished_at TEXT,
            created_at TEXT NOT NULL,
            updated_at TEXT NOT NULL
        )
        """

    private static let operationLogTableSQL = """
        CREATE TABLE operation_logs (
            id TEXT PRIMARY KEY,
            level TEXT NOT NULL CHECK (level IN ('info', 'warning', 'error')),
            message TEXT NOT NULL,
            context_json TEXT NOT NULL,
            created_at TEXT NOT NULL
        )
        """
}
