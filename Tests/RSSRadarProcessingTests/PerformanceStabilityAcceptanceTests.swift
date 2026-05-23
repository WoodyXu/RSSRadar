import Foundation
import RSSRadarCore
import RSSRadarPersistence
import RSSRadarProcessing
import XCTest

final class PerformanceStabilityAcceptanceTests: XCTestCase {
    func testStartupRecoveryPathShowsMainInterfaceWithinTwoSecondsBudget() throws {
        let databaseURL = makeDatabaseURL()
        try seedLargeAcceptanceDataset(at: databaseURL)

        let startupDuration = try measureDuration {
            let database = try RSSRadarDatabase(path: databaseURL.path)
            try database.migrate()
            let repositories = RSSRadarRepositories(database: database)
            let recoveredCount = try ProcessingStartupRecoveryUseCase(repositories: repositories)
                .recover(now: acceptanceNow)
            let recoveryLogs = try repositories.operationLogs.fetchRecent(limit: 100)
                .filter { $0.message == "Recovered interrupted processing jobs" }

            XCTAssertEqual(recoveredCount, AcceptanceDataset.runningJobCount)
            XCTAssertEqual(recoveryLogs.first?.context["recovered_count"], String(AcceptanceDataset.runningJobCount))
        }

        XCTAssertLessThan(
            startupDuration,
            2.0,
            "Startup bootstrap, migration, repository creation, and recovery should fit the Step 34 2s budget."
        )
    }

    func testLargeFeedsAndProcessingSnapshotsRemainResponsive() throws {
        let repositories = try makeSeededRepositories()

        let snapshotDuration = try measureDuration {
            let feeds = try repositories.feeds.fetchAll()
            let articlesByFeed = try repositories.articles.fetchGroupedByFeedID()
            let jobs = try repositories.processingJobs.fetchAll()
            let logs = try repositories.operationLogs.fetchRecent(limit: 40)

            XCTAssertEqual(feeds.count, AcceptanceDataset.feedCount)
            XCTAssertEqual(articlesByFeed.values.reduce(0) { $0 + $1.count }, AcceptanceDataset.articleCount)
            XCTAssertGreaterThanOrEqual(jobs.count, AcceptanceDataset.totalJobCount)
            XCTAssertEqual(logs.count, 40)
        }

        XCTAssertLessThan(
            snapshotDuration,
            2.0,
            "Feeds and Processing page snapshots should stay responsive on a larger local dataset."
        )
    }

    func testLargeTodaySnapshotRemainsResponsive() throws {
        let repositories = try makeSeededRepositories()

        let snapshotDuration = try measureDuration {
            let todaySnapshot = try TodayPageDataSource(
                repositories: repositories,
                calendar: acceptanceCalendar
            ).load(now: acceptanceNow)

            XCTAssertFalse(todaySnapshot.importantTopics.isEmpty)
        }

        XCTAssertLessThan(
            snapshotDuration,
            2.0,
            "Today page snapshot aggregation should stay responsive on a larger local dataset."
        )
    }

    func testLargePendingQueueRunsBoundedSliceAndLeavesOtherJobsOperable() async throws {
        let repositories = try makeRepositories()
        try seedFeedsForQueue(repositories: repositories, count: 120)
        let engine = ProcessingEngine(
            repositories: repositories,
            executor: SelectiveAcceptanceExecutor(failingJobIDs: ["job-000"]),
            configuration: ProcessingEngineConfiguration(maxConcurrentFeedFetchJobs: 8)
        )
        for feedIndex in 0..<120 {
            var queuedJob = ProcessingJob(
                id: String(format: "job-%03d", feedIndex),
                jobType: .fetchFeed,
                entityType: .feed,
                entityID: String(format: "queue-feed-%03d", feedIndex),
                maxAttempts: 1,
                scheduledAt: acceptanceNow,
                createdAt: acceptanceNow.addingTimeInterval(TimeInterval(feedIndex)),
                updatedAt: acceptanceNow
            )
            queuedJob.payload = ["feed_id": queuedJob.entityID ?? ""]
            try repositories.processingJobs.save(queuedJob)
        }

        let runDuration = await measureAsyncDuration {
            await engine.runPendingJobs(now: acceptanceNow.addingTimeInterval(1))
        }
        let completedJobs = try repositories.processingJobs.fetch(status: .completed)
        let failedJobs = try repositories.processingJobs.fetch(status: .failed)
        let pendingJobs = try repositories.processingJobs.fetch(status: .pending)

        XCTAssertLessThan(
            runDuration,
            2.0,
            "A processing run should execute a bounded ready-job slice quickly enough for the UI to remain usable."
        )
        XCTAssertEqual(completedJobs.count, 7)
        XCTAssertEqual(failedJobs.map(\.id), ["job-000"])
        XCTAssertEqual(pendingJobs.count, 112)
    }

    func testInterruptedJobsRecoverAndExecuteWithoutRepeatingCompletedJobs() async throws {
        let repositories = try makeRepositories()
        let executor = RecordingAcceptanceExecutor()
        let engine = ProcessingEngine(
            repositories: repositories,
            executor: executor,
            configuration: ProcessingEngineConfiguration(maxConcurrentFeedFetchJobs: 12)
        )
        try seedFeedsForQueue(repositories: repositories, count: 36)
        for index in 0..<24 {
            var queuedJob = ProcessingJob(
                id: String(format: "recovery-job-%03d", index),
                jobType: .fetchFeed,
                entityType: .feed,
                entityID: String(format: "queue-feed-%03d", index),
                scheduledAt: acceptanceNow,
                createdAt: acceptanceNow.addingTimeInterval(TimeInterval(index)),
                updatedAt: acceptanceNow
            )
            if index < 12 {
                queuedJob.status = .running
                queuedJob.attemptCount = 2
                queuedJob.startedAt = acceptanceNow.addingTimeInterval(5)
            } else {
                queuedJob.status = .completed
                queuedJob.finishedAt = acceptanceNow.addingTimeInterval(10)
            }
            try repositories.processingJobs.save(queuedJob)
        }

        let recoveredCount = try await engine.recoverInterruptedJobs(now: acceptanceNow.addingTimeInterval(30))
        await engine.runPendingJobs(now: acceptanceNow.addingTimeInterval(31))

        let executedIDs = await executor.executedJobIDs()
        let completedJobs = try repositories.processingJobs.fetch(status: .completed)
        let pendingJobs = try repositories.processingJobs.fetch(status: .pending)
        let recoveredJob = try XCTUnwrap(repositories.processingJobs.fetch(id: "recovery-job-000"))

        XCTAssertEqual(recoveredCount, 12)
        XCTAssertEqual(executedIDs.sorted(), (0..<12).map { String(format: "recovery-job-%03d", $0) })
        XCTAssertEqual(recoveredJob.attemptCount, 2)
        XCTAssertEqual(completedJobs.count, 24)
        XCTAssertEqual(pendingJobs.count, 0)
    }
}

private enum AcceptanceDataset {
    static let feedCount = 60
    static let articlesPerFeed = 50
    static let articleCount = feedCount * articlesPerFeed
    static let topicCount = 120
    static let runningJobCount = 80
    static let pendingJobCount = 120
    static let failedJobCount = 30
    static let completedJobCount = 60
    static let totalJobCount = runningJobCount + pendingJobCount + failedJobCount + completedJobCount
}

private func makeSeededRepositories() throws -> RSSRadarRepositories {
    let databaseURL = makeDatabaseURL()
    try seedLargeAcceptanceDataset(at: databaseURL)
    let database = try RSSRadarDatabase(path: databaseURL.path)
    try database.migrate()
    return RSSRadarRepositories(database: database)
}

private func makeRepositories() throws -> RSSRadarRepositories {
    let database = try RSSRadarDatabase(path: makeDatabaseURL().path)
    try database.migrate()
    return RSSRadarRepositories(database: database)
}

private func makeDatabaseURL() -> URL {
    FileManager.default.temporaryDirectory
        .appendingPathComponent("RSSRadarPerformanceStabilityAcceptanceTests", isDirectory: true)
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
        .appendingPathComponent("rssradar.sqlite")
}

private func seedLargeAcceptanceDataset(at databaseURL: URL) throws {
    let database = try RSSRadarDatabase(path: databaseURL.path)
    try database.migrate()
    let repositories = RSSRadarRepositories(database: database)
    try repositories.performTransaction { transaction in
        try seedAcceptanceFeedsAndArticles(transaction: transaction)
        try seedAcceptanceTopics(transaction: transaction)
        try seedAcceptanceJobs(transaction: transaction)
        try seedAcceptanceLogs(transaction: transaction)
    }
}

private func seedAcceptanceFeedsAndArticles(transaction: RSSRadarRepositoryTransaction) throws {
    for feedIndex in 0..<AcceptanceDataset.feedCount {
        let feedID = String(format: "feed-%03d", feedIndex)
        let feed = Feed(
            id: feedID,
            title: String(format: "Feed %03d", feedIndex),
            url: URL(string: "https://example.com/feed-\(feedIndex).xml")!,
            lastCheckedAt: acceptanceNow.addingTimeInterval(-60),
            lastSuccessAt: acceptanceNow.addingTimeInterval(-60),
            createdAt: acceptanceNow.addingTimeInterval(-10_000),
            updatedAt: acceptanceNow
        )
        try transaction.feeds.save(feed)
        try seedAcceptanceArticles(feedID: feedID, feedIndex: feedIndex, transaction: transaction)
    }
}

private func seedAcceptanceArticles(
    feedID: String,
    feedIndex: Int,
    transaction: RSSRadarRepositoryTransaction
) throws {
    for articleIndex in 0..<AcceptanceDataset.articlesPerFeed {
        let articleID = String(format: "article-%03d-%03d", feedIndex, articleIndex)
        let article = Article(
            id: articleID,
            feedID: feedID,
            title: "Article \(feedIndex)-\(articleIndex)",
            url: URL(string: "https://example.com/\(feedID)/\(articleIndex)")!,
            publishedAt: acceptanceNow.addingTimeInterval(TimeInterval(-articleIndex * 60)),
            rssSummary: "Summary \(articleIndex)",
            content: "Parsed content \(articleIndex)",
            contentSource: articleIndex.isMultiple(of: 5) ? .rssSummary : .webExtracted,
            status: articleIndex.isMultiple(of: 17) ? .failed : .assigned,
            importanceScore: Double(articleIndex % 10) / 10,
            createdAt: acceptanceNow.addingTimeInterval(TimeInterval(-articleIndex * 60)),
            updatedAt: acceptanceNow
        )
        try transaction.articles.save(article)
    }
}

private func seedAcceptanceTopics(transaction: RSSRadarRepositoryTransaction) throws {
    for topicIndex in 0..<AcceptanceDataset.topicCount {
        let topicID = String(format: "topic-%03d", topicIndex)
        let topic = Topic(
            id: topicID,
            name: "Topic \(topicIndex)",
            description: "Performance acceptance topic \(topicIndex).",
            status: topicIndex.isMultiple(of: 4) ? .candidate : .active,
            importanceScore: Double((topicIndex % 10) + 1) / 10,
            createdAt: acceptanceNow.addingTimeInterval(TimeInterval(-topicIndex * 120)),
            updatedAt: acceptanceNow.addingTimeInterval(TimeInterval(-topicIndex * 60))
        )
        try transaction.topics.save(topic)
        try seedAcceptanceBrief(topic: topic, topicIndex: topicIndex, transaction: transaction)
        try seedAcceptanceTopicRelations(topicID: topicID, topicIndex: topicIndex, transaction: transaction)
    }
}

private func seedAcceptanceBrief(
    topic: Topic,
    topicIndex: Int,
    transaction: RSSRadarRepositoryTransaction
) throws {
    let relatedArticleID = String(
        format: "article-%03d-%03d",
        topicIndex % AcceptanceDataset.feedCount,
        0
    )
    try transaction.topicBriefs.save(
        TopicBrief(
            topicID: topic.id,
            briefType: topic.status == .candidate ? .preview : .full,
            currentTakeaway: "Takeaway \(topicIndex)",
            latestChanges: [TopicBriefChange(text: "Change \(topicIndex)")],
            relatedArticleIDs: [relatedArticleID],
            modelName: "gpt-test",
            generatedAt: acceptanceNow
        )
    )
}

private func seedAcceptanceTopicRelations(
    topicID: String,
    topicIndex: Int,
    transaction: RSSRadarRepositoryTransaction
) throws {
    for relationIndex in 0..<5 {
        try transaction.topicArticles.save(
            TopicArticle(
                topicID: topicID,
                articleID: String(
                    format: "article-%03d-%03d",
                    (topicIndex + relationIndex) % AcceptanceDataset.feedCount,
                    relationIndex
                ),
                confidence: 0.8,
                reason: "Acceptance relationship",
                contributionType: .newEvent,
                createdAt: acceptanceNow
            )
        )
    }
}

private func seedAcceptanceJobs(transaction: RSSRadarRepositoryTransaction) throws {
    let specs: [(ProcessingJobStatus, Int)] = [
        (.running, AcceptanceDataset.runningJobCount),
        (.pending, AcceptanceDataset.pendingJobCount),
        (.failed, AcceptanceDataset.failedJobCount),
        (.completed, AcceptanceDataset.completedJobCount)
    ]
    var offset = 0
    for (status, count) in specs {
        for index in 0..<count {
            var job = ProcessingJob(
                id: "\(status.rawValue)-job-\(index)",
                jobType: .fetchFeed,
                entityType: .feed,
                entityID: String(format: "feed-%03d", index % AcceptanceDataset.feedCount),
                scheduledAt: acceptanceNow,
                createdAt: acceptanceNow.addingTimeInterval(TimeInterval(offset)),
                updatedAt: acceptanceNow
            )
            job.status = status
            if status == .running {
                job.startedAt = acceptanceNow.addingTimeInterval(1)
                job.attemptCount = 1
            } else if status == .failed {
                job.attemptCount = 3
                job.lastErrorMessage = "Network request failed"
                job.finishedAt = acceptanceNow.addingTimeInterval(2)
            } else if status == .completed {
                job.finishedAt = acceptanceNow.addingTimeInterval(2)
            }
            try transaction.processingJobs.save(job)
            offset += 1
        }
    }
}

private func seedAcceptanceLogs(transaction: RSSRadarRepositoryTransaction) throws {
    for logIndex in 0..<80 {
        try transaction.operationLogs.save(
            OperationLog(
                level: logIndex.isMultiple(of: 7) ? .warning : .info,
                message: "Acceptance log \(logIndex)",
                context: ["log_index": String(logIndex)],
                createdAt: acceptanceNow.addingTimeInterval(TimeInterval(logIndex))
            )
        )
    }
}

private func seedFeedsForQueue(repositories: RSSRadarRepositories, count: Int) throws {
    try repositories.performTransaction { transaction in
        for index in 0..<count {
            try transaction.feeds.save(
                Feed(
                    id: String(format: "queue-feed-%03d", index),
                    title: String(format: "Queue Feed %03d", index),
                    url: URL(string: "https://example.com/queue-\(index).xml")!,
                    createdAt: acceptanceNow,
                    updatedAt: acceptanceNow
                )
            )
        }
    }
}

private func measureDuration(_ operation: () throws -> Void) throws -> TimeInterval {
    let start = Date()
    try operation()
    return Date().timeIntervalSince(start)
}

private func measureAsyncDuration(_ operation: () async -> Void) async -> TimeInterval {
    let start = Date()
    await operation()
    return Date().timeIntervalSince(start)
}

private actor SelectiveAcceptanceExecutor: ProcessingJobExecuting {
    private let failingJobIDs: Set<String>

    init(failingJobIDs: Set<String>) {
        self.failingJobIDs = failingJobIDs
    }

    func execute(job: ProcessingJob) async throws {
        if failingJobIDs.contains(job.id) {
            throw AcceptanceExecutorError.plannedFailure(job.id)
        }
    }
}

private actor RecordingAcceptanceExecutor: ProcessingJobExecuting {
    private var ids: [String] = []

    func execute(job: ProcessingJob) async throws {
        ids.append(job.id)
    }

    func executedJobIDs() -> [String] {
        ids
    }
}

private enum AcceptanceExecutorError: Error, Equatable {
    case plannedFailure(String)
}

private let acceptanceNow = Date(timeIntervalSince1970: 1_700_500_000)
private let acceptanceCalendar = Calendar(identifier: .gregorian)
