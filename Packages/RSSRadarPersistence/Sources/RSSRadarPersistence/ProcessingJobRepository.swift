import Foundation
import GRDB
import RSSRadarCore

public final class ProcessingJobRepository {
    private let access: DatabaseAccess

    init(access: DatabaseAccess) {
        self.access = access
    }

    public func save(_ job: ProcessingJob) throws {
        try SensitiveProcessingJobContentValidator.validate(job)

        try access.write { db in
            try db.execute(
                sql: """
                    INSERT INTO processing_jobs (
                        id, job_type, entity_type, entity_id, payload_json, status, priority, attempt_count,
                        max_attempts, last_error_message, scheduled_at, started_at, finished_at,
                        created_at, updated_at
                    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                    ON CONFLICT(id) DO UPDATE SET
                        job_type = excluded.job_type,
                        entity_type = excluded.entity_type,
                        entity_id = excluded.entity_id,
                        payload_json = excluded.payload_json,
                        status = excluded.status,
                        priority = excluded.priority,
                        attempt_count = excluded.attempt_count,
                        max_attempts = excluded.max_attempts,
                        last_error_message = excluded.last_error_message,
                        scheduled_at = excluded.scheduled_at,
                        started_at = excluded.started_at,
                        finished_at = excluded.finished_at,
                        created_at = excluded.created_at,
                        updated_at = excluded.updated_at
                    """,
                arguments: try job.databaseArguments
            )
        }
    }

    public func fetch(id: String) throws -> ProcessingJob? {
        try access.read { db in
            try Row.fetchOne(db, sql: "SELECT * FROM processing_jobs WHERE id = ?", arguments: [id])
                .map(ProcessingJob.init(row:))
        }
    }

    public func fetchAll() throws -> [ProcessingJob] {
        try access.read { db in
            try Row.fetchAll(
                db,
                sql: "SELECT * FROM processing_jobs ORDER BY created_at DESC"
            ).map(ProcessingJob.init(row:))
        }
    }

    public func fetch(status: ProcessingJobStatus) throws -> [ProcessingJob] {
        try access.read { db in
            try Row.fetchAll(
                db,
                sql: "SELECT * FROM processing_jobs WHERE status = ? ORDER BY priority DESC, scheduled_at ASC",
                arguments: [status.rawValue]
            ).map(ProcessingJob.init(row:))
        }
    }

    public func fetchReady(now: Date, limit: Int) throws -> [ProcessingJob] {
        try access.read { db in
            try Row.fetchAll(
                db,
                sql: """
                    SELECT *
                    FROM processing_jobs
                    WHERE status = ? AND scheduled_at <= ?
                    ORDER BY priority DESC, scheduled_at ASC, created_at ASC
                    LIMIT ?
                    """,
                arguments: [ProcessingJobStatus.pending.rawValue, DatabaseCoding.string(from: now), limit]
            ).map(ProcessingJob.init(row:))
        }
    }

    public func updateStatus(
        id: String,
        status: ProcessingJobStatus,
        lastErrorMessage: String? = nil,
        startedAt: Date? = nil,
        finishedAt: Date? = nil,
        updatedAt: Date = Date()
    ) throws {
        try SensitiveProcessingJobContentValidator.validate(lastErrorMessage: lastErrorMessage)

        try access.write { db in
            try db.execute(
                sql: """
                    UPDATE processing_jobs
                    SET status = ?,
                        last_error_message = ?,
                        started_at = ?,
                        finished_at = ?,
                        updated_at = ?
                    WHERE id = ?
                    """,
                arguments: [
                    status.rawValue,
                    lastErrorMessage,
                    startedAt.map(DatabaseCoding.string(from:)),
                    finishedAt.map(DatabaseCoding.string(from:)),
                    DatabaseCoding.string(from: updatedAt),
                    id
                ]
            )
        }
    }

    public func updateRetryState(
        id: String,
        status: ProcessingJobStatus,
        attemptCount: Int,
        lastErrorMessage: String?,
        scheduledAt: Date,
        startedAt: Date? = nil,
        finishedAt: Date? = nil,
        updatedAt: Date = Date()
    ) throws {
        try SensitiveProcessingJobContentValidator.validate(lastErrorMessage: lastErrorMessage)

        try access.write { db in
            try db.execute(
                sql: """
                    UPDATE processing_jobs
                    SET status = ?,
                        attempt_count = ?,
                        last_error_message = ?,
                        scheduled_at = ?,
                        started_at = ?,
                        finished_at = ?,
                        updated_at = ?
                    WHERE id = ?
                    """,
                arguments: [
                    status.rawValue,
                    attemptCount,
                    lastErrorMessage,
                    DatabaseCoding.string(from: scheduledAt),
                    startedAt.map(DatabaseCoding.string(from:)),
                    finishedAt.map(DatabaseCoding.string(from:)),
                    DatabaseCoding.string(from: updatedAt),
                    id
                ]
            )
        }
    }

    @discardableResult
    public func recoverInterruptedJobs(scheduledAt: Date = Date(), updatedAt: Date = Date()) throws -> Int {
        try access.write { db in
            try db.execute(
                sql: """
                    UPDATE processing_jobs
                    SET status = ?,
                        scheduled_at = ?,
                        started_at = NULL,
                        finished_at = NULL,
                        updated_at = ?
                    WHERE status = ?
                    """,
                arguments: [
                    ProcessingJobStatus.pending.rawValue,
                    DatabaseCoding.string(from: scheduledAt),
                    DatabaseCoding.string(from: updatedAt),
                    ProcessingJobStatus.running.rawValue
                ]
            )
            return db.changesCount
        }
    }

    public func delete(id: String) throws {
        try access.write { db in
            try db.execute(sql: "DELETE FROM processing_jobs WHERE id = ?", arguments: [id])
        }
    }
}

private enum SensitiveProcessingJobContentValidator {
    static func validate(_ job: ProcessingJob) throws {
        var values: [String] = []
        values.append(contentsOf: job.payload.keys)
        values.append(contentsOf: job.payload.values)
        if let lastErrorMessage = job.lastErrorMessage {
            values.append(lastErrorMessage)
        }
        try SensitiveContentValidator.validate(values)
    }

    static func validate(lastErrorMessage: String?) throws {
        guard let lastErrorMessage else { return }
        try SensitiveContentValidator.validate([lastErrorMessage])
    }
}

private extension ProcessingJob {
    var databaseArguments: StatementArguments {
        get throws {
            [
                id,
                jobType.rawValue,
                entityType.rawValue,
                entityID,
                try DatabaseCoding.jsonString(from: payload),
                status.rawValue,
                priority,
                attemptCount,
                maxAttempts,
                lastErrorMessage,
                DatabaseCoding.string(from: scheduledAt),
                startedAt.map(DatabaseCoding.string(from:)),
                finishedAt.map(DatabaseCoding.string(from:)),
                DatabaseCoding.string(from: createdAt),
                DatabaseCoding.string(from: updatedAt)
            ]
        }
    }

    init(row: Row) throws {
        self.init(
            id: try row.requiredString("id"),
            jobType: ProcessingJobType(rawValue: try row.requiredString("job_type"))!,
            entityType: ProcessingJobEntityType(rawValue: try row.requiredString("entity_type"))!,
            entityID: row["entity_id"],
            payload: try DatabaseCoding.value(fromJSONString: try row.requiredString("payload_json")),
            status: ProcessingJobStatus(rawValue: try row.requiredString("status"))!,
            priority: try row.requiredInt("priority"),
            attemptCount: try row.requiredInt("attempt_count"),
            maxAttempts: try row.requiredInt("max_attempts"),
            lastErrorMessage: row["last_error_message"],
            scheduledAt: try row.requiredDate("scheduled_at"),
            startedAt: try row.optionalDate("started_at"),
            finishedAt: try row.optionalDate("finished_at"),
            createdAt: try row.requiredDate("created_at"),
            updatedAt: try row.requiredDate("updated_at")
        )
    }
}
