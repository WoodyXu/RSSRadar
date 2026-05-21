import Foundation
import GRDB
import RSSRadarCore

public final class AppSettingsRepository {
    private static let defaultID = "default"

    private let access: DatabaseAccess

    init(access: DatabaseAccess) {
        self.access = access
    }

    public func fetch() throws -> AppSettings {
        try access.read { db in
            try Row.fetchOne(
                db,
                sql: "SELECT * FROM app_settings WHERE id = ?",
                arguments: [Self.defaultID]
            ).map(AppSettings.init(row:)) ?? AppSettings()
        }
    }

    public func save(_ settings: AppSettings, updatedAt: Date = Date()) throws {
        try access.write { db in
            try db.execute(
                sql: """
                    INSERT INTO app_settings (
                        id, ai_provider, base_url, model_name, database_path, keychain_account_identifier,
                        scan_mode, scan_interval_hours, max_articles_per_scan, max_articles_for_new_feed,
                        max_articles_per_topic_batch, ai_request_timeout_seconds, updated_at
                    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                    ON CONFLICT(id) DO UPDATE SET
                        ai_provider = excluded.ai_provider,
                        base_url = excluded.base_url,
                        model_name = excluded.model_name,
                        database_path = excluded.database_path,
                        keychain_account_identifier = excluded.keychain_account_identifier,
                        scan_mode = excluded.scan_mode,
                        scan_interval_hours = excluded.scan_interval_hours,
                        max_articles_per_scan = excluded.max_articles_per_scan,
                        max_articles_for_new_feed = excluded.max_articles_for_new_feed,
                        max_articles_per_topic_batch = excluded.max_articles_per_topic_batch,
                        ai_request_timeout_seconds = excluded.ai_request_timeout_seconds,
                        updated_at = excluded.updated_at
                    """,
                arguments: settings.databaseArguments(updatedAt: updatedAt)
            )
        }
    }
}

private extension AppSettings {
    func databaseArguments(updatedAt: Date) -> StatementArguments {
        [
            "default",
            aiProvider.rawValue,
            baseURL.absoluteString,
            modelName,
            databasePath,
            keychainAccountIdentifier,
            scanMode.rawValue,
            scanIntervalHours,
            maxArticlesPerScan,
            maxArticlesForNewFeed,
            maxArticlesPerTopicBatch,
            aiRequestTimeoutSeconds,
            DatabaseCoding.string(from: updatedAt)
        ]
    }

    init(row: Row) throws {
        self.init(
            aiProvider: AIProviderKind(rawValue: try row.requiredString("ai_provider"))!,
            baseURL: try row.requiredURL("base_url"),
            modelName: try row.requiredString("model_name"),
            databasePath: row["database_path"],
            keychainAccountIdentifier: row["keychain_account_identifier"],
            scanMode: ScanMode(rawValue: try row.requiredString("scan_mode"))!,
            scanIntervalHours: try row.requiredInt("scan_interval_hours"),
            maxArticlesPerScan: try row.requiredInt("max_articles_per_scan"),
            maxArticlesForNewFeed: try row.requiredInt("max_articles_for_new_feed"),
            maxArticlesPerTopicBatch: try row.requiredInt("max_articles_per_topic_batch"),
            aiRequestTimeoutSeconds: try row.requiredInt("ai_request_timeout_seconds")
        )
    }
}
