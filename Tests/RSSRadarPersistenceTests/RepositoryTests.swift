import GRDB
import RSSRadarCore
import XCTest
@testable import RSSRadarPersistence

final class RepositoryTests: XCTestCase {
    func testFeedRepositoryCreatesReadsUpdatesListsAndDeletes() throws {
        let repositories = try makeRepositories()
        let feed = makeFeed(id: "feed-1", title: "Original")

        try repositories.feeds.save(feed)
        XCTAssertEqual(try repositories.feeds.fetch(id: "feed-1")?.title, "Original")

        var updated = feed
        updated.title = "Updated"
        updated.status = .paused
        try repositories.feeds.save(updated)

        XCTAssertEqual(try repositories.feeds.fetchAll().map(\.id), ["feed-1"])
        XCTAssertEqual(try repositories.feeds.fetch(status: .paused).first?.title, "Updated")

        try repositories.feeds.delete(id: "feed-1")
        XCTAssertNil(try repositories.feeds.fetch(id: "feed-1"))
    }

    func testArticleRepositoryCreatesReadsUpdatesListsAndDeletes() throws {
        let repositories = try makeRepositories()
        try repositories.feeds.save(makeFeed(id: "feed-1"))

        let article = makeArticle(id: "article-1", feedID: "feed-1", title: "Original")
        try repositories.articles.save(article)
        XCTAssertEqual(try repositories.articles.fetch(id: "article-1")?.title, "Original")

        var updated = article
        updated.title = "Updated"
        updated.status = .parsed
        updated.contentSource = .rssSummary
        try repositories.articles.save(updated)

        XCTAssertEqual(try repositories.articles.fetch(feedID: "feed-1").map(\.id), ["article-1"])
        XCTAssertEqual(try repositories.articles.fetch(status: .parsed).first?.contentSource, .rssSummary)

        try repositories.articles.delete(id: "article-1")
        XCTAssertNil(try repositories.articles.fetch(id: "article-1"))
    }

    func testArticleAnalysisRepositoryUpsertsByArticleID() throws {
        let repositories = try makeRepositories()
        try repositories.feeds.save(makeFeed(id: "feed-1"))
        try repositories.articles.save(makeArticle(id: "article-1", feedID: "feed-1"))

        try repositories.articleAnalyses.save(makeAnalysis(id: "analysis-1", articleID: "article-1", summary: "First"))
        try repositories.articleAnalyses.save(makeAnalysis(id: "analysis-2", articleID: "article-1", summary: "Second"))

        let analysis = try XCTUnwrap(repositories.articleAnalyses.fetch(articleID: "article-1"))
        XCTAssertEqual(analysis.id, "analysis-2")
        XCTAssertEqual(analysis.summary, "Second")
        XCTAssertEqual(analysis.keyPoints, ["point"])
        XCTAssertEqual(try repositories.articleAnalyses.fetchAll().count, 1)
    }

    func testTopicRepositoryCreatesReadsUpdatesAndNormalizesNames() throws {
        let repositories = try makeRepositories()
        let topic = makeTopic(id: "topic-1", name: "  Claude   Code  Updates ")

        try repositories.topics.save(topic)
        XCTAssertEqual(
            try repositories.topics.fetch(status: .candidate, normalizedName: "claude code updates")?.id,
            "topic-1"
        )

        var updated = topic
        updated.name = "Claude Code Enterprise Adoption"
        updated.status = .active
        try repositories.topics.save(updated)

        XCTAssertEqual(try repositories.topics.fetch(status: .active).map(\.id), ["topic-1"])
        XCTAssertEqual(try repositories.topics.fetch(id: "topic-1")?.entities, ["Claude Code"])

        try repositories.topics.delete(id: "topic-1")
        XCTAssertNil(try repositories.topics.fetch(id: "topic-1"))
    }

    func testTopicArticleRepositoryCreatesReadsUpdatesAndDeletes() throws {
        let repositories = try makeRepositories()
        try repositories.feeds.save(makeFeed(id: "feed-1"))
        try repositories.articles.save(makeArticle(id: "article-1", feedID: "feed-1"))
        try repositories.topics.save(makeTopic(id: "topic-1"))

        let relation = TopicArticle(
            topicID: "topic-1",
            articleID: "article-1",
            confidence: 0.6,
            reason: "Initial",
            contributionType: .background,
            createdAt: fixedDate
        )
        try repositories.topicArticles.save(relation)

        var updated = relation
        updated.confidence = 0.9
        updated.reason = "Updated"
        updated.contributionType = .newData
        try repositories.topicArticles.save(updated)

        XCTAssertEqual(
            try repositories.topicArticles.fetch(topicID: "topic-1", articleID: "article-1")?.reason,
            "Updated"
        )
        XCTAssertEqual(try repositories.topicArticles.fetchForTopic(id: "topic-1").count, 1)
        let articleRelations = try repositories.topicArticles.fetchForArticle(id: "article-1")
        XCTAssertEqual(articleRelations.first?.contributionType, .newData)

        try repositories.topicArticles.delete(topicID: "topic-1", articleID: "article-1")
        XCTAssertNil(try repositories.topicArticles.fetch(topicID: "topic-1", articleID: "article-1"))
    }

    func testTopicBriefRepositoryUpsertsByTopicAndType() throws {
        let repositories = try makeRepositories()
        try repositories.topics.save(makeTopic(id: "topic-1"))

        try repositories.topicBriefs.save(makeBrief(id: "brief-1", topicID: "topic-1", takeaway: "First"))
        try repositories.topicBriefs.save(makeBrief(id: "brief-2", topicID: "topic-1", takeaway: "Second"))

        let brief = try XCTUnwrap(repositories.topicBriefs.fetch(topicID: "topic-1", briefType: .full))
        XCTAssertEqual(brief.id, "brief-2")
        XCTAssertEqual(brief.currentTakeaway, "Second")
        XCTAssertEqual(brief.latestChanges, [TopicBriefChange(text: "change", articleIDs: ["article-1"])])
        XCTAssertEqual(try repositories.topicBriefs.fetchForTopic(id: "topic-1").count, 1)

        try repositories.topicBriefs.delete(id: "brief-2")
        XCTAssertNil(try repositories.topicBriefs.fetch(topicID: "topic-1", briefType: .full))
    }

    func testRepositoryTransactionRollsBackOnFailure() throws {
        let repositories = try makeRepositories()

        XCTAssertThrowsError(
            try repositories.performTransaction { transaction in
                try transaction.feeds.save(makeFeed(id: "feed-1"))
                try transaction.articles.save(makeArticle(id: "orphan", feedID: "missing-feed"))
            }
        )

        XCTAssertNil(try repositories.feeds.fetch(id: "feed-1"))
        XCTAssertNil(try repositories.articles.fetch(id: "orphan"))
    }

    func testAppSettingsRepositoryReturnsDefaultsWhenNoRowExists() throws {
        let repositories = try makeRepositories()

        let settings = try repositories.appSettings.fetch()

        XCTAssertEqual(settings.aiProvider, .openAICompatible)
        XCTAssertEqual(settings.baseURL.absoluteString, "https://api.openai.com/v1")
        XCTAssertEqual(settings.modelName, "")
        XCTAssertNil(settings.databasePath)
        XCTAssertNil(settings.keychainAccountIdentifier)
        XCTAssertEqual(settings.scanMode, .manual)
        XCTAssertEqual(settings.scanIntervalHours, 6)
        XCTAssertEqual(settings.maxArticlesPerScan, 100)
        XCTAssertEqual(settings.maxArticlesForNewFeed, 20)
        XCTAssertEqual(settings.maxArticlesPerTopicBatch, 20)
        XCTAssertEqual(settings.aiRequestTimeoutSeconds, 60)
    }

    func testAppSettingsRepositorySavesReadsAndUpsertsDefaultSettings() throws {
        let repositories = try makeRepositories()
        let settings = AppSettings(
            aiProvider: .anthropic,
            baseURL: URL(string: "https://api.anthropic.com")!,
            modelName: "claude-test",
            databasePath: "/tmp/rssradar-custom.sqlite",
            keychainAccountIdentifier: "rssradar-default-key",
            scanMode: .interval,
            scanIntervalHours: 12,
            maxArticlesPerScan: 50,
            maxArticlesForNewFeed: 10,
            maxArticlesPerTopicBatch: 15,
            aiRequestTimeoutSeconds: 45
        )

        try repositories.appSettings.save(settings, updatedAt: fixedDate)
        XCTAssertEqual(try repositories.appSettings.fetch(), settings)

        var updated = settings
        updated.aiProvider = .custom
        updated.baseURL = URL(string: "https://models.example.com/v1")!
        updated.modelName = "custom-model"
        updated.scanMode = .onLaunch
        try repositories.appSettings.save(updated, updatedAt: fixedDate)

        XCTAssertEqual(try repositories.appSettings.fetch(), updated)
    }

    func testAppSettingsRejectsInvalidProviderValues() throws {
        let database = try makeTemporaryDatabase()
        try database.migrate()

        XCTAssertThrowsError(
            try database.queue.write { db in
                try db.execute(
                    sql: """
                        INSERT INTO app_settings (
                            id, ai_provider, base_url, model_name, scan_mode, scan_interval_hours,
                            max_articles_per_scan, max_articles_for_new_feed, max_articles_per_topic_batch,
                            ai_request_timeout_seconds, updated_at
                        ) VALUES (
                            'default', 'unknown', 'https://example.com/v1', 'model', 'manual', 6, 100, 20, 20, 60,
                            '2026-05-20T00:00:00Z'
                        )
                        """
                )
            }
        )
    }

    func testAppSettingsPersistenceDoesNotStoreAPIKeyPlaintext() throws {
        let database = try makeTemporaryDatabase()
        try database.migrate()
        let repositories = RSSRadarRepositories(database: database)
        let secretAPIKey = "sk-test-secret-value"

        try repositories.appSettings.save(
            AppSettings(
                aiProvider: .openAICompatible,
                baseURL: URL(string: "https://api.openai.com/v1")!,
                modelName: "gpt-test",
                databasePath: "/tmp/rssradar.sqlite",
                keychainAccountIdentifier: "rssradar-account-id"
            ),
            updatedAt: fixedDate
        )

        try database.queue.read { db in
            let schemaSQL = try String.fetchAll(
                db,
                sql: "SELECT sql FROM sqlite_master WHERE type = 'table' AND name = 'app_settings'"
            ).joined(separator: "\n")
            XCTAssertFalse(schemaSQL.lowercased().contains("api_key"))

            let textValues = try Row.fetchOne(
                db,
                sql: """
                    SELECT
                        id, ai_provider, base_url, model_name, database_path, keychain_account_identifier,
                        scan_mode, updated_at
                    FROM app_settings
                    WHERE id = 'default'
                    """
            ).map { row in
                row.columnNames.compactMap { columnName -> String? in
                    row[columnName]
                }
            } ?? []
            XCTAssertFalse(textValues.contains(secretAPIKey))
        }
    }

    func testProcessingJobRepositoryCreatesReadsUpdatesAndListsReadyJobs() throws {
        let repositories = try makeRepositories()
        let laterDate = fixedDate.addingTimeInterval(60)
        let readyLowPriority = makeProcessingJob(id: "job-1", priority: 1)
        let readyHighPriority = makeProcessingJob(id: "job-2", priority: 5)
        let future = makeProcessingJob(id: "job-3", scheduledAt: laterDate)

        try repositories.processingJobs.save(readyLowPriority)
        try repositories.processingJobs.save(readyHighPriority)
        try repositories.processingJobs.save(future)

        XCTAssertEqual(try repositories.processingJobs.fetch(id: "job-1")?.jobType, .fetchFeed)
        XCTAssertEqual(try repositories.processingJobs.fetch(status: .pending).map(\.id), ["job-2", "job-1", "job-3"])
        XCTAssertEqual(
            try repositories.processingJobs.fetchReady(now: fixedDate, limit: 10).map(\.id),
            ["job-2", "job-1"]
        )

        try repositories.processingJobs.updateStatus(
            id: "job-1",
            status: .running,
            startedAt: fixedDate,
            updatedAt: fixedDate
        )
        XCTAssertEqual(try repositories.processingJobs.fetch(id: "job-1")?.status, .running)

        try repositories.processingJobs.delete(id: "job-1")
        XCTAssertNil(try repositories.processingJobs.fetch(id: "job-1"))
    }

    func testProcessingJobRepositoryPersistsPayloadAndFailureStatus() throws {
        let repositories = try makeRepositories()
        var job = makeProcessingJob(id: "job-1")
        job.payload = ["feed_id": "feed-1", "reason": "manual_refresh"]
        job.status = .failed
        job.attemptCount = 3
        job.lastErrorMessage = "Feed returned HTTP 500"
        job.finishedAt = fixedDate

        try repositories.processingJobs.save(job)

        let persisted = try XCTUnwrap(repositories.processingJobs.fetch(id: "job-1"))
        XCTAssertEqual(persisted.payload["reason"], "manual_refresh")
        XCTAssertEqual(persisted.status, .failed)
        XCTAssertEqual(persisted.attemptCount, 3)
        XCTAssertEqual(persisted.lastErrorMessage, "Feed returned HTTP 500")
        XCTAssertEqual(persisted.finishedAt, fixedDate)
    }

    func testOperationLogRepositoryCreatesReadsAndRejectsSensitiveContent() throws {
        let repositories = try makeRepositories()
        let log = OperationLog(
            id: "log-1",
            level: .info,
            message: "Feed scan completed",
            context: ["feed_id": "feed-1", "job_id": "job-1"],
            createdAt: fixedDate
        )

        try repositories.operationLogs.save(log)

        XCTAssertEqual(try repositories.operationLogs.fetch(id: "log-1"), log)
        XCTAssertEqual(try repositories.operationLogs.fetchRecent(limit: 1).map(\.id), ["log-1"])

        XCTAssertThrowsError(
            try repositories.operationLogs.save(
                OperationLog(
                    id: "log-2",
                    level: .error,
                    message: "API key failed",
                    context: ["token": "sk-test-secret-value"],
                    createdAt: fixedDate
                )
            )
        ) { error in
            XCTAssertEqual(error as? RSSRadarRepositoryError, .sensitiveLogContent)
        }

        try repositories.operationLogs.delete(id: "log-1")
        XCTAssertNil(try repositories.operationLogs.fetch(id: "log-1"))
    }

}

private extension RepositoryTests {
    var fixedDate: Date {
        Date(timeIntervalSince1970: 1_778_889_600)
    }

    func makeRepositories() throws -> RSSRadarRepositories {
        let database = try makeTemporaryDatabase()
        try database.migrate()
        return RSSRadarRepositories(database: database)
    }

    func makeTemporaryDatabase() throws -> RSSRadarDatabase {
        let directoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("RSSRadarRepositoryTests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let databaseURL = directoryURL.appendingPathComponent("rssradar.sqlite")

        return try RSSRadarDatabase(path: databaseURL.path)
    }

    func makeFeed(id: String, title: String = "Feed") -> Feed {
        Feed(
            id: id,
            title: title,
            url: URL(string: "https://example.com/\(id).xml")!,
            siteURL: URL(string: "https://example.com")!,
            lastCheckedAt: fixedDate,
            lastSuccessAt: fixedDate,
            lastProcessedArticlePublishedAt: fixedDate,
            createdAt: fixedDate,
            updatedAt: fixedDate
        )
    }

    func makeArticle(id: String, feedID: String, title: String = "Article") -> Article {
        Article(
            id: id,
            feedID: feedID,
            title: title,
            url: URL(string: "https://example.com/articles/\(id)")!,
            author: "Author",
            publishedAt: fixedDate,
            rssSummary: "RSS summary",
            content: "Content",
            contentSource: .rssFullContent,
            status: .fetched,
            importanceScore: 0.7,
            createdAt: fixedDate,
            updatedAt: fixedDate
        )
    }

    func makeAnalysis(id: String, articleID: String, summary: String) -> ArticleAnalysis {
        ArticleAnalysis(
            id: id,
            articleID: articleID,
            summary: summary,
            keyPoints: ["point"],
            entities: ["entity"],
            claims: ["claim"],
            events: ["event"],
            metrics: ["metric"],
            contentType: .analysis,
            possibleTopics: ["topic"],
            importanceScore: 0.8,
            modelName: "test-model",
            generatedAt: fixedDate
        )
    }

    func makeTopic(id: String, name: String = "Topic") -> Topic {
        Topic(
            id: id,
            name: name,
            description: "Description",
            originalAIName: "AI Topic",
            originalAIDescription: "AI Description",
            entities: ["Claude Code"],
            status: .candidate,
            importanceScore: 0.9,
            createdAt: fixedDate,
            updatedAt: fixedDate
        )
    }

    func makeBrief(id: String, topicID: String, takeaway: String) -> TopicBrief {
        TopicBrief(
            id: id,
            topicID: topicID,
            briefType: .full,
            currentTakeaway: takeaway,
            latestChanges: [TopicBriefChange(text: "change", articleIDs: ["article-1"])],
            timeline: [TopicBriefTimelineItem(date: fixedDate, title: "event", description: "description")],
            viewpoints: [TopicBriefViewpoint(title: "view", summary: "summary")],
            evidence: [
                TopicBriefEvidence(
                    content: "evidence",
                    sourceArticleID: "article-1",
                    sourceArticleTitle: "Article",
                    sourceName: "Feed",
                    sourceURL: URL(string: "https://example.com/articles/article-1")!,
                    publishedAt: fixedDate
                )
            ],
            questionsToWatch: ["question"],
            relatedArticleIDs: ["article-1"],
            modelName: "test-model",
            generatedAt: fixedDate
        )
    }

    func makeProcessingJob(
        id: String,
        priority: Int = 0,
        scheduledAt: Date? = nil
    ) -> ProcessingJob {
        ProcessingJob(
            id: id,
            jobType: .fetchFeed,
            entityType: .feed,
            entityID: "feed-1",
            payload: ["feed_id": "feed-1"],
            priority: priority,
            scheduledAt: scheduledAt ?? fixedDate,
            createdAt: fixedDate,
            updatedAt: fixedDate
        )
    }
}
