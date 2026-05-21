import Foundation
import RSSRadarAI
import RSSRadarCore
import RSSRadarFeeds
import RSSRadarPersistence
import RSSRadarProcessing
import XCTest

final class ProcessingEngineTests: XCTestCase {
    func testEnqueueScanAllFeedsCreatesJobsForNonPausedFeeds() async throws {
        let repositories = try makeRepositories()
        try repositories.feeds.save(feed(id: "feed-1", status: .active))
        try repositories.feeds.save(feed(id: "feed-2", status: .paused))
        try repositories.feeds.save(feed(id: "feed-3", status: .noArticles))

        let engine = ProcessingEngine(repositories: repositories, executor: RecordingProcessingJobExecutor())
        let jobs = try await engine.enqueueScanAllFeeds(priority: 7, scheduledAt: fixedDate)

        XCTAssertEqual(jobs.compactMap(\.entityID).sorted(), ["feed-1", "feed-3"])
        XCTAssertEqual(jobs.allSatisfy { $0.status == .pending }, true)
        XCTAssertEqual(jobs.allSatisfy { $0.priority == 7 }, true)
        XCTAssertEqual(try repositories.processingJobs.fetch(status: .pending).count, 2)
        XCTAssertEqual(try repositories.operationLogs.fetchRecent(limit: 10).count, 2)
    }

    func testRunPendingJobsCompletesSelectedJobsAndHonorsPerTypeConcurrency() async throws {
        let repositories = try makeRepositories()
        let executor = RecordingProcessingJobExecutor(delayNanoseconds: 50_000_000)
        let engine = ProcessingEngine(
            repositories: repositories,
            executor: executor,
            configuration: ProcessingEngineConfiguration(
                maxConcurrentFeedFetchJobs: 2,
                maxConcurrentParseArticleJobs: 1,
                maxConcurrentAnalyzeArticleJobs: 1,
                maxConcurrentAssignTopicsJobs: 1,
                maxConcurrentGenerateTopicBriefJobs: 1
            )
        )
        let jobs = [
            job(id: "fetch-1", type: .fetchFeed, entityType: .feed, entityID: "feed-1", createdAtOffset: 1),
            job(id: "fetch-2", type: .fetchFeed, entityType: .feed, entityID: "feed-2", createdAtOffset: 2),
            job(id: "fetch-3", type: .fetchFeed, entityType: .feed, entityID: "feed-3", createdAtOffset: 3),
            job(id: "parse-1", type: .parseArticle, entityType: .article, entityID: "article-1", createdAtOffset: 4),
            job(id: "parse-2", type: .parseArticle, entityType: .article, entityID: "article-2", createdAtOffset: 5),
            job(
                id: "analyze-1",
                type: .analyzeArticle,
                entityType: .article,
                entityID: "article-3",
                createdAtOffset: 6
            ),
            job(id: "assign-1", type: .assignTopics, entityType: .article, entityID: "article-4", createdAtOffset: 7),
            job(id: "brief-1", type: .generateTopicBrief, entityType: .topic, entityID: "topic-1", createdAtOffset: 8)
        ]
        for job in jobs {
            try repositories.processingJobs.save(job)
        }

        await engine.runPendingJobs(now: fixedDate.addingTimeInterval(60))

        let completedJobs = try repositories.processingJobs.fetch(status: .completed)
        let pendingJobs = try repositories.processingJobs.fetch(status: .pending)
        let maxConcurrentCounts = await executor.maxConcurrentCounts()

        XCTAssertEqual(completedJobs.map(\.id).sorted(), [
            "analyze-1",
            "assign-1",
            "brief-1",
            "fetch-1",
            "fetch-2",
            "parse-1"
        ])
        XCTAssertEqual(pendingJobs.map(\.id).sorted(), ["fetch-3", "parse-2"])
        XCTAssertEqual(maxConcurrentCounts[.fetchFeed], 2)
        XCTAssertEqual(maxConcurrentCounts[.parseArticle], 1)
        XCTAssertEqual(maxConcurrentCounts[.analyzeArticle], 1)
        XCTAssertEqual(maxConcurrentCounts[.assignTopics], 1)
        XCTAssertEqual(maxConcurrentCounts[.generateTopicBrief], 1)
        XCTAssertTrue(completedJobs.allSatisfy { $0.startedAt != nil && $0.finishedAt != nil })
    }

    func testDefaultExecutorRunsFetchFeedJobThroughFeedScanUseCase() async throws {
        let repositories = try makeRepositories()
        let sourceFeed = feed(id: "feed-1", status: .active)
        try repositories.feeds.save(sourceFeed)
        let executor = ProcessingEngineExecutor(
            repositories: repositories,
            loader: FixtureFeedDataLoader(fixtureName: "valid-rss")
        )
        let engine = ProcessingEngine(repositories: repositories, executor: executor)
        let queuedJob = try await engine.enqueueFeedScan(feedID: sourceFeed.id, scheduledAt: fixedDate)

        await engine.runPendingJobs(now: fixedDate.addingTimeInterval(60))

        let completedJob = try XCTUnwrap(repositories.processingJobs.fetch(id: queuedJob.id))
        let persistedArticles = try repositories.articles.fetch(feedID: sourceFeed.id)

        XCTAssertEqual(completedJob.status, .completed)
        XCTAssertEqual(persistedArticles.count, 1)
        XCTAssertEqual(persistedArticles.first?.status, .parsed)
    }

    func testFailedJobRetriesTwiceThenBecomesFailed() async throws {
        let repositories = try makeRepositories()
        let engine = ProcessingEngine(
            repositories: repositories,
            executor: FailingProcessingJobExecutor(),
            configuration: ProcessingEngineConfiguration(retryBackoffSeconds: [0, 30])
        )
        let initialJob = job(
            id: "retry-job",
            type: .fetchFeed,
            entityType: .feed,
            entityID: "feed-1",
            createdAtOffset: 1
        )
        try repositories.processingJobs.save(initialJob)

        await engine.runPendingJobs(now: Date().addingTimeInterval(1))
        let firstFailure = try XCTUnwrap(repositories.processingJobs.fetch(id: initialJob.id))
        XCTAssertEqual(firstFailure.status, .pending)
        XCTAssertEqual(firstFailure.attemptCount, 1)
        XCTAssertNotNil(firstFailure.lastErrorMessage)

        await engine.runPendingJobs(now: Date().addingTimeInterval(5))
        let secondFailure = try XCTUnwrap(repositories.processingJobs.fetch(id: initialJob.id))
        XCTAssertEqual(secondFailure.status, .pending)
        XCTAssertEqual(secondFailure.attemptCount, 2)
        XCTAssertGreaterThan(secondFailure.scheduledAt, secondFailure.finishedAt ?? .distantPast)

        await engine.runPendingJobs(now: Date().addingTimeInterval(60))
        let finalFailure = try XCTUnwrap(repositories.processingJobs.fetch(id: initialJob.id))
        XCTAssertEqual(finalFailure.status, .failed)
        XCTAssertEqual(finalFailure.attemptCount, 3)
        XCTAssertNotNil(finalFailure.finishedAt)

        let logs = try repositories.operationLogs.fetchRecent(limit: 10)
        XCTAssertEqual(logs.filter { $0.message == "Processing job scheduled for retry" }.count, 2)
        XCTAssertEqual(logs.filter { $0.message == "Processing job failed" }.count, 1)
    }

    func testFailedJobDoesNotBlockOtherReadyJobs() async throws {
        let repositories = try makeRepositories()
        let executor = SelectivelyFailingProcessingJobExecutor(failingJobIDs: ["failing-job"])
        let engine = ProcessingEngine(
            repositories: repositories,
            executor: executor,
            configuration: ProcessingEngineConfiguration(maxConcurrentFeedFetchJobs: 2)
        )
        let failingJob = job(
            id: "failing-job",
            type: .fetchFeed,
            entityType: .feed,
            entityID: "feed-1",
            createdAtOffset: 1
        )
        let successfulJob = job(
            id: "successful-job",
            type: .fetchFeed,
            entityType: .feed,
            entityID: "feed-2",
            createdAtOffset: 2
        )
        try repositories.processingJobs.save(failingJob)
        try repositories.processingJobs.save(successfulJob)

        await engine.runPendingJobs(now: Date().addingTimeInterval(1))

        let retriedJob = try XCTUnwrap(repositories.processingJobs.fetch(id: failingJob.id))
        let completedJob = try XCTUnwrap(repositories.processingJobs.fetch(id: successfulJob.id))
        XCTAssertEqual(retriedJob.status, .pending)
        XCTAssertEqual(retriedJob.attemptCount, 1)
        XCTAssertEqual(completedJob.status, .completed)
    }

    func testExhaustedArticleAnalysisValidationFailureMarksArticleFailedWithoutAnalysis() async throws {
        let repositories = try makeRepositories()
        let feed = feed(id: "feed-1", status: .active)
        let article = article(id: "article-1", feedID: feed.id, status: .parsed)
        try repositories.feeds.save(feed)
        try repositories.articles.save(article)
        let engine = ProcessingEngine(
            repositories: repositories,
            executor: ValidationFailingProcessingJobExecutor(),
            configuration: ProcessingEngineConfiguration(maxConcurrentAnalyzeArticleJobs: 1)
        )
        let analysisJob = ProcessingJob(
            id: "invalid-analysis-job",
            jobType: .analyzeArticle,
            entityType: .article,
            entityID: article.id,
            payload: ["model_name": "gpt-test"],
            maxAttempts: 1,
            scheduledAt: fixedDate,
            createdAt: fixedDate,
            updatedAt: fixedDate
        )
        try repositories.processingJobs.save(analysisJob)

        await engine.runPendingJobs(now: fixedDate.addingTimeInterval(1))

        let failedJob = try XCTUnwrap(repositories.processingJobs.fetch(id: analysisJob.id))
        let failedArticle = try XCTUnwrap(repositories.articles.fetch(id: article.id))
        let persistedAnalysis = try repositories.articleAnalyses.fetch(articleID: article.id)
        let logs = try repositories.operationLogs.fetchRecent(limit: 10)

        XCTAssertEqual(failedJob.status, .failed)
        XCTAssertEqual(failedJob.attemptCount, 1)
        XCTAssertEqual(failedArticle.status, .failed)
        XCTAssertEqual(failedArticle.importanceScore, nil)
        XCTAssertTrue(failedArticle.errorMessage?.contains("emptyField") == true)
        XCTAssertNil(persistedAnalysis)
        XCTAssertEqual(logs.filter { $0.message == "Processing job failed" }.count, 1)
    }

    func testManualRetryRequeuesFailedJob() async throws {
        let repositories = try makeRepositories()
        let engine = ProcessingEngine(repositories: repositories, executor: RecordingProcessingJobExecutor())
        var failedJob = job(
            id: "manual-retry-job",
            type: .fetchFeed,
            entityType: .feed,
            entityID: "feed-1",
            createdAtOffset: 1
        )
        failedJob.status = .failed
        failedJob.attemptCount = 3
        failedJob.lastErrorMessage = "Failed after automatic retries"
        failedJob.finishedAt = fixedDate
        try repositories.processingJobs.save(failedJob)

        let retriedJob = try await engine.retry(jobID: failedJob.id, scheduledAt: fixedDate)
        XCTAssertEqual(retriedJob.status, .pending)
        XCTAssertEqual(retriedJob.attemptCount, 0)
        XCTAssertNil(retriedJob.lastErrorMessage)
        XCTAssertNil(retriedJob.startedAt)
        XCTAssertNil(retriedJob.finishedAt)

        await engine.runPendingJobs(now: fixedDate.addingTimeInterval(1))

        let completedJob = try XCTUnwrap(repositories.processingJobs.fetch(id: failedJob.id))
        XCTAssertEqual(completedJob.status, .completed)
    }

    func testRecoveryRequeuesInterruptedRunningJobsWithoutRepeatingCompletedJobs() async throws {
        let repositories = try makeRepositories()
        let executor = RecordingProcessingJobExecutor()
        let engine = ProcessingEngine(
            repositories: repositories,
            executor: executor,
            configuration: ProcessingEngineConfiguration(maxConcurrentFeedFetchJobs: 3)
        )
        var runningJob = job(
            id: "running-job",
            type: .fetchFeed,
            entityType: .feed,
            entityID: "feed-1",
            createdAtOffset: 1
        )
        runningJob.status = .running
        runningJob.attemptCount = 2
        runningJob.startedAt = fixedDate.addingTimeInterval(5)
        let pendingJob = job(
            id: "pending-job",
            type: .fetchFeed,
            entityType: .feed,
            entityID: "feed-2",
            createdAtOffset: 2
        )
        var completedJob = job(
            id: "completed-job",
            type: .fetchFeed,
            entityType: .feed,
            entityID: "feed-3",
            createdAtOffset: 3
        )
        completedJob.status = .completed
        completedJob.finishedAt = fixedDate.addingTimeInterval(10)
        try repositories.processingJobs.save(runningJob)
        try repositories.processingJobs.save(pendingJob)
        try repositories.processingJobs.save(completedJob)

        let recoveredCount = try await engine.recoverInterruptedJobs(now: fixedDate.addingTimeInterval(30))
        await engine.runPendingJobs(now: fixedDate.addingTimeInterval(31))

        let recoveredJob = try XCTUnwrap(repositories.processingJobs.fetch(id: runningJob.id))
        let completedPendingJob = try XCTUnwrap(repositories.processingJobs.fetch(id: pendingJob.id))
        let untouchedCompletedJob = try XCTUnwrap(repositories.processingJobs.fetch(id: completedJob.id))
        let executedIDs = await executor.executedJobIDs()
        let recoveryLogs = try repositories.operationLogs.fetchRecent(limit: 10)
            .filter { $0.message == "Recovered interrupted processing jobs" }

        XCTAssertEqual(recoveredCount, 1)
        XCTAssertEqual(recoveredJob.status, .completed)
        XCTAssertEqual(recoveredJob.attemptCount, 2)
        XCTAssertEqual(completedPendingJob.status, .completed)
        XCTAssertEqual(untouchedCompletedJob.status, .completed)
        XCTAssertEqual(untouchedCompletedJob.finishedAt, fixedDate.addingTimeInterval(10))
        XCTAssertEqual(executedIDs.sorted(), ["pending-job", "running-job"])
        XCTAssertEqual(recoveryLogs.count, 1)
        XCTAssertEqual(recoveryLogs.first?.context["recovered_count"], "1")
    }
}

private extension ProcessingEngineTests {
    func makeRepositories() throws -> RSSRadarRepositories {
        let directoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("RSSRadarProcessingEngineTests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let databaseURL = directoryURL.appendingPathComponent("rssradar.sqlite")
        let database = try RSSRadarDatabase(path: databaseURL.path)
        try database.migrate()
        return RSSRadarRepositories(database: database)
    }

    func feed(id: String, status: FeedStatus) -> Feed {
        Feed(
            id: id,
            title: "Feed \(id)",
            url: URL(string: "https://example.com/\(id).xml")!,
            status: status,
            createdAt: fixedDate,
            updatedAt: fixedDate
        )
    }

    func article(id: String, feedID: String, status: ArticleStatus) -> Article {
        Article(
            id: id,
            feedID: feedID,
            title: "Article \(id)",
            url: URL(string: "https://example.com/\(id)")!,
            content: "Parsed article content",
            status: status,
            createdAt: fixedDate,
            updatedAt: fixedDate
        )
    }

    func job(
        id: String,
        type: ProcessingJobType,
        entityType: ProcessingJobEntityType,
        entityID: String,
        createdAtOffset: TimeInterval
    ) -> ProcessingJob {
        ProcessingJob(
            id: id,
            jobType: type,
            entityType: entityType,
            entityID: entityID,
            scheduledAt: fixedDate,
            createdAt: fixedDate.addingTimeInterval(createdAtOffset),
            updatedAt: fixedDate.addingTimeInterval(createdAtOffset)
        )
    }
}

private actor RecordingProcessingJobExecutor: ProcessingJobExecuting {
    private let delayNanoseconds: UInt64
    private var currentCounts: [ProcessingJobType: Int] = [:]
    private var maximumCounts: [ProcessingJobType: Int] = [:]
    private var executedIDs: [String] = []

    init(delayNanoseconds: UInt64 = 0) {
        self.delayNanoseconds = delayNanoseconds
    }

    func execute(job: ProcessingJob) async throws {
        executedIDs.append(job.id)
        let currentCount = currentCounts[job.jobType, default: 0] + 1
        currentCounts[job.jobType] = currentCount
        maximumCounts[job.jobType] = max(maximumCounts[job.jobType, default: 0], currentCount)

        if delayNanoseconds > 0 {
            try await Task.sleep(nanoseconds: delayNanoseconds)
        }

        currentCounts[job.jobType] = currentCounts[job.jobType, default: 1] - 1
    }

    func maxConcurrentCounts() -> [ProcessingJobType: Int] {
        maximumCounts
    }

    func executedJobIDs() -> [String] {
        executedIDs
    }
}

private struct FixtureFeedDataLoader: FeedDataLoader {
    var fixtureName: String

    func data(from url: URL) async throws -> (Data, URLResponse) {
        let fixtureURL = Bundle.module.url(forResource: fixtureName, withExtension: "xml")!
        let data = try Data(contentsOf: fixtureURL)
        let response = HTTPURLResponse(
            url: url,
            statusCode: 200,
            httpVersion: nil,
            headerFields: nil
        )!
        return (data, response)
    }
}

private actor ValidationFailingProcessingJobExecutor: ProcessingJobExecuting {
    func execute(job: ProcessingJob) async throws {
        throw ArticleAnalysisValidationError.emptyField("summary")
    }
}

private actor FailingProcessingJobExecutor: ProcessingJobExecuting {
    func execute(job: ProcessingJob) async throws {
        throw ProcessingEngineTestError.plannedFailure(job.id)
    }
}

private actor SelectivelyFailingProcessingJobExecutor: ProcessingJobExecuting {
    private let failingJobIDs: Set<String>

    init(failingJobIDs: Set<String>) {
        self.failingJobIDs = failingJobIDs
    }

    func execute(job: ProcessingJob) async throws {
        if failingJobIDs.contains(job.id) {
            throw ProcessingEngineTestError.plannedFailure(job.id)
        }
    }
}

private enum ProcessingEngineTestError: Error, Equatable {
    case plannedFailure(String)
}

private let fixedDate = Date(timeIntervalSince1970: 1_700_000_000)
