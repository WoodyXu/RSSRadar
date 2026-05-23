import Foundation
import RSSRadarCore
import XCTest
@testable import RSSRadarPersistence

final class ProcessingJobRepositoryTests: XCTestCase {
    func testUpdatesRetryState() throws {
        let repositories = try makeRepositories()
        let job = ProcessingJob(
            id: "job-1",
            jobType: .fetchFeed,
            entityType: .feed,
            entityID: "feed-1",
            payload: ["feed_id": "feed-1"],
            scheduledAt: fixedDate,
            createdAt: fixedDate,
            updatedAt: fixedDate
        )
        let retryDate = fixedDate.addingTimeInterval(30)

        try repositories.processingJobs.save(job)
        try repositories.processingJobs.updateRetryState(
            id: job.id,
            status: .pending,
            attemptCount: 2,
            lastErrorMessage: "Temporary failure",
            scheduledAt: retryDate,
            startedAt: fixedDate,
            finishedAt: fixedDate.addingTimeInterval(1),
            updatedAt: fixedDate.addingTimeInterval(1)
        )

        let persisted = try XCTUnwrap(repositories.processingJobs.fetch(id: job.id))
        XCTAssertEqual(persisted.status, .pending)
        XCTAssertEqual(persisted.attemptCount, 2)
        XCTAssertEqual(persisted.lastErrorMessage, "Temporary failure")
        XCTAssertEqual(persisted.scheduledAt, retryDate)
        XCTAssertEqual(persisted.startedAt, fixedDate)
        XCTAssertEqual(persisted.finishedAt, fixedDate.addingTimeInterval(1))
    }

    func testRecoversInterruptedRunningJobsWithoutIncrementingAttempts() throws {
        let repositories = try makeRepositories()
        var runningJob = ProcessingJob(
            id: "running-job",
            jobType: .fetchFeed,
            entityType: .feed,
            entityID: "feed-1",
            scheduledAt: fixedDate,
            createdAt: fixedDate,
            updatedAt: fixedDate
        )
        runningJob.status = .running
        runningJob.attemptCount = 2
        runningJob.startedAt = fixedDate.addingTimeInterval(1)
        let pendingJob = ProcessingJob(
            id: "pending-job",
            jobType: .fetchFeed,
            entityType: .feed,
            entityID: "feed-2",
            scheduledAt: fixedDate,
            createdAt: fixedDate,
            updatedAt: fixedDate
        )
        var completedJob = ProcessingJob(
            id: "completed-job",
            jobType: .fetchFeed,
            entityType: .feed,
            entityID: "feed-3",
            scheduledAt: fixedDate,
            createdAt: fixedDate,
            updatedAt: fixedDate
        )
        completedJob.status = .completed
        completedJob.finishedAt = fixedDate.addingTimeInterval(2)
        try repositories.processingJobs.save(runningJob)
        try repositories.processingJobs.save(pendingJob)
        try repositories.processingJobs.save(completedJob)

        let recoveredCount = try repositories.processingJobs.recoverInterruptedJobs(
            scheduledAt: fixedDate.addingTimeInterval(30),
            updatedAt: fixedDate.addingTimeInterval(30)
        )

        let recoveredJob = try XCTUnwrap(repositories.processingJobs.fetch(id: runningJob.id))
        let persistedPendingJob = try XCTUnwrap(repositories.processingJobs.fetch(id: pendingJob.id))
        let persistedCompletedJob = try XCTUnwrap(repositories.processingJobs.fetch(id: completedJob.id))
        XCTAssertEqual(recoveredCount, 1)
        XCTAssertEqual(recoveredJob.status, .pending)
        XCTAssertEqual(recoveredJob.attemptCount, 2)
        XCTAssertEqual(recoveredJob.scheduledAt, fixedDate.addingTimeInterval(30))
        XCTAssertNil(recoveredJob.startedAt)
        XCTAssertNil(recoveredJob.finishedAt)
        XCTAssertEqual(persistedPendingJob.status, .pending)
        XCTAssertEqual(persistedPendingJob.scheduledAt, fixedDate)
        XCTAssertEqual(persistedCompletedJob.status, .completed)
        XCTAssertEqual(persistedCompletedJob.finishedAt, fixedDate.addingTimeInterval(2))
    }

    func testRejectsSensitivePayloadAndErrorContent() throws {
        let repositories = try makeRepositories()
        var payloadJob = makeProcessingJob(id: "job-sensitive-payload")
        payloadJob.payload = ["api_key": "sk-test-secret-value"]

        XCTAssertThrowsError(try repositories.processingJobs.save(payloadJob)) { error in
            XCTAssertEqual(error as? RSSRadarRepositoryError, .sensitiveLogContent)
        }

        var failedJob = makeProcessingJob(id: "job-sensitive-error")
        failedJob.lastErrorMessage = "Authorization failed for Bearer sk-test-secret-value"

        XCTAssertThrowsError(try repositories.processingJobs.save(failedJob)) { error in
            XCTAssertEqual(error as? RSSRadarRepositoryError, .sensitiveLogContent)
        }

        try repositories.processingJobs.save(makeProcessingJob(id: "job-plain-error"))
        XCTAssertThrowsError(
            try repositories.processingJobs.updateStatus(
                id: "job-plain-error",
                status: .failed,
                lastErrorMessage: "x-api-key was rejected",
                updatedAt: fixedDate
            )
        ) { error in
            XCTAssertEqual(error as? RSSRadarRepositoryError, .sensitiveLogContent)
        }
    }
}

private extension ProcessingJobRepositoryTests {
    var fixedDate: Date {
        Date(timeIntervalSince1970: 1_778_889_600)
    }

    func makeRepositories() throws -> RSSRadarRepositories {
        let directoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("RSSRadarProcessingJobRepositoryTests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let databaseURL = directoryURL.appendingPathComponent("rssradar.sqlite")
        let database = try RSSRadarDatabase(path: databaseURL.path)
        try database.migrate()
        return RSSRadarRepositories(database: database)
    }

    func makeProcessingJob(id: String) -> ProcessingJob {
        ProcessingJob(
            id: id,
            jobType: .fetchFeed,
            entityType: .feed,
            entityID: "feed-1",
            payload: ["feed_id": "feed-1"],
            scheduledAt: fixedDate,
            createdAt: fixedDate,
            updatedAt: fixedDate
        )
    }
}
