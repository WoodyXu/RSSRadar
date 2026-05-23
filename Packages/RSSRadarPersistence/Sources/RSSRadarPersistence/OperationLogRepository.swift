import Foundation
import GRDB
import RSSRadarCore

public final class OperationLogRepository {
    private let access: DatabaseAccess

    init(access: DatabaseAccess) {
        self.access = access
    }

    public func save(_ log: OperationLog) throws {
        try SensitiveLogContentValidator.validate(log)

        try access.write { db in
            try db.execute(
                sql: """
                    INSERT INTO operation_logs (
                        id, level, message, context_json, created_at
                    ) VALUES (?, ?, ?, ?, ?)
                    ON CONFLICT(id) DO UPDATE SET
                        level = excluded.level,
                        message = excluded.message,
                        context_json = excluded.context_json,
                        created_at = excluded.created_at
                    """,
                arguments: try log.databaseArguments
            )
        }
    }

    public func fetch(id: String) throws -> OperationLog? {
        try access.read { db in
            try Row.fetchOne(db, sql: "SELECT * FROM operation_logs WHERE id = ?", arguments: [id])
                .map(OperationLog.init(row:))
        }
    }

    public func fetchAll() throws -> [OperationLog] {
        try access.read { db in
            try Row.fetchAll(
                db,
                sql: "SELECT * FROM operation_logs ORDER BY created_at DESC"
            ).map(OperationLog.init(row:))
        }
    }

    public func fetchRecent(limit: Int) throws -> [OperationLog] {
        try access.read { db in
            try Row.fetchAll(
                db,
                sql: "SELECT * FROM operation_logs ORDER BY created_at DESC LIMIT ?",
                arguments: [limit]
            ).map(OperationLog.init(row:))
        }
    }

    public func delete(id: String) throws {
        try access.write { db in
            try db.execute(sql: "DELETE FROM operation_logs WHERE id = ?", arguments: [id])
        }
    }
}

private enum SensitiveLogContentValidator {
    static func validate(_ log: OperationLog) throws {
        var values = [log.message]
        for (key, value) in log.context {
            values.append(key)
            values.append(value)
        }

        try SensitiveContentValidator.validate(values)
    }
}

private extension OperationLog {
    var databaseArguments: StatementArguments {
        get throws {
            [
                id,
                level.rawValue,
                message,
                try DatabaseCoding.jsonString(from: context),
                DatabaseCoding.string(from: createdAt)
            ]
        }
    }

    init(row: Row) throws {
        self.init(
            id: try row.requiredString("id"),
            level: OperationLogLevel(rawValue: try row.requiredString("level"))!,
            message: try row.requiredString("message"),
            context: try DatabaseCoding.value(fromJSONString: try row.requiredString("context_json")),
            createdAt: try row.requiredDate("created_at")
        )
    }
}
