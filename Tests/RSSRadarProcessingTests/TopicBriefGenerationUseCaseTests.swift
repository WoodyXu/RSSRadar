import Foundation
import RSSRadarAI
import RSSRadarCore
import RSSRadarPersistence
import RSSRadarProcessing
import XCTest

final class TopicBriefGenerationUseCaseTests: XCTestCase {
    func testActiveTopicFullBriefGeneratesAndCachesResult() async throws {
        let repositories = try makeRepositories()
        try seedTopicGraph(topicStatus: .active, repositories: repositories)
        let generator = RecordingTopicBriefGenerator(
            brief: brief(topicID: "topic-1", briefType: .full, generatedAt: fixedDate)
        )
        let useCase = TopicBriefGenerationUseCase(repositories: repositories, generator: generator)

        let result = try await useCase.generateIfNeeded(
            topicID: "topic-1",
            briefType: .full,
            modelName: "gpt-test",
            generatedAt: fixedDate
        )
        let cachedResult = try await useCase.generateIfNeeded(
            topicID: "topic-1",
            briefType: .full,
            modelName: "gpt-test",
            generatedAt: fixedDate.addingTimeInterval(30)
        )
        let requests = await generator.allRequests()
        let request = requests.first
        let persistedBrief = try XCTUnwrap(repositories.topicBriefs.fetch(topicID: "topic-1", briefType: .full))

        XCTAssertTrue(result.didGenerate)
        XCTAssertFalse(cachedResult.didGenerate)
        XCTAssertEqual(requests.count, 1)
        XCTAssertEqual(request?.topic.id, "topic-1")
        XCTAssertEqual(request?.briefType, .full)
        XCTAssertEqual(request?.modelName, "gpt-test")
        XCTAssertEqual(request?.relatedArticles.map(\.article.id), ["article-1"])
        XCTAssertEqual(request?.relatedArticles.first?.feedTitle, "Example Feed")
        XCTAssertEqual(persistedBrief.currentTakeaway, "Cached takeaway")
        XCTAssertEqual(cachedResult.brief.id, persistedBrief.id)
    }

    func testCandidateTopicOnlyGeneratesPreview() async throws {
        let repositories = try makeRepositories()
        try seedTopicGraph(topicStatus: .candidate, repositories: repositories)
        let generator = RecordingTopicBriefGenerator(
            brief: brief(topicID: "topic-1", briefType: .preview, generatedAt: fixedDate)
        )
        let useCase = TopicBriefGenerationUseCase(repositories: repositories, generator: generator)

        let result = try await useCase.generateIfNeeded(
            topicID: "topic-1",
            briefType: .preview,
            modelName: "gpt-test",
            generatedAt: fixedDate
        )

        XCTAssertTrue(result.didGenerate)
        XCTAssertEqual(result.brief.briefType, .preview)

        do {
            _ = try await useCase.generateIfNeeded(
                topicID: "topic-1",
                briefType: .full,
                modelName: "gpt-test",
                generatedAt: fixedDate
            )
            XCTFail("Expected candidate full brief generation to throw")
        } catch let error as TopicBriefGenerationUseCaseError {
            XCTAssertEqual(error, .candidateRequiresPreview("topic-1"))
        }
    }

    func testManualRegenerateFailurePreservesExistingBriefAndLogsFailure() async throws {
        let repositories = try makeRepositories()
        try seedTopicGraph(topicStatus: .active, repositories: repositories)
        var existingBrief = brief(topicID: "topic-1", briefType: .full, generatedAt: fixedDate)
        existingBrief.id = "existing-brief"
        existingBrief.currentTakeaway = "Existing takeaway"
        try repositories.topicBriefs.save(existingBrief)
        let generator = FailingTopicBriefGenerator()
        let useCase = TopicBriefGenerationUseCase(repositories: repositories, generator: generator)

        do {
            _ = try await useCase.regenerate(
                topicID: "topic-1",
                briefType: .full,
                modelName: "gpt-test",
                generatedAt: fixedDate.addingTimeInterval(60)
            )
            XCTFail("Expected manual TopicBrief regeneration to throw")
        } catch FailingTopicBriefGenerator.Failure.expected {
            // Expected failure path.
        }

        let persistedBrief = try XCTUnwrap(repositories.topicBriefs.fetch(topicID: "topic-1", briefType: .full))
        let logs = try repositories.operationLogs.fetchAll()

        XCTAssertEqual(persistedBrief.id, "existing-brief")
        XCTAssertEqual(persistedBrief.currentTakeaway, "Existing takeaway")
        XCTAssertTrue(logs.contains { log in
            log.level == .error
                && log.message == "Failed to regenerate TopicBrief"
                && log.context["topic_id"] == "topic-1"
                && log.context["brief_type"] == TopicBriefType.full.rawValue
        })
    }

    func testProcessingEngineExecutorDoesNotGenerateTopicBriefJobs() async throws {
        let repositories = try makeRepositories()
        try seedTopicGraph(topicStatus: .active, repositories: repositories)
        let executor = ProcessingEngineExecutor(repositories: repositories)
        let engine = ProcessingEngine(repositories: repositories, executor: executor)
        let job = ProcessingJob(
            id: "brief-job-1",
            jobType: .generateTopicBrief,
            entityType: .topic,
            entityID: "topic-1",
            payload: [
                "topic_id": "topic-1",
                "brief_type": TopicBriefType.full.rawValue,
                "model_name": "gpt-test"
            ],
            scheduledAt: fixedDate,
            createdAt: fixedDate,
            updatedAt: fixedDate
        )
        try repositories.processingJobs.save(job)

        await engine.runPendingJobs(now: fixedDate.addingTimeInterval(1))

        let retriedJob = try XCTUnwrap(repositories.processingJobs.fetch(id: job.id))
        let persistedBrief = try repositories.topicBriefs.fetch(topicID: "topic-1", briefType: .full)

        XCTAssertEqual(retriedJob.status, .pending)
        XCTAssertEqual(retriedJob.attemptCount, 1)
        XCTAssertNil(persistedBrief)
    }
}

private func seedTopicGraph(topicStatus: TopicStatus, repositories: RSSRadarRepositories) throws {
    let feed = Feed(
        id: "feed-1",
        title: "Example Feed",
        url: URL(string: "https://example.com/feed.xml")!,
        createdAt: fixedDate,
        updatedAt: fixedDate
    )
    let article = Article(
        id: "article-1",
        feedID: feed.id,
        title: "Claude Code adoption update",
        url: URL(string: "https://example.com/article-1")!,
        publishedAt: fixedDate,
        status: .assigned,
        createdAt: fixedDate,
        updatedAt: fixedDate
    )
    let analysis = ArticleAnalysis(
        articleID: article.id,
        summary: "Claude Code adoption improved in a large Swift codebase.",
        keyPoints: ["Teams adopted AI coding tools for multi-file edits."],
        entities: ["Claude Code", "Swift"],
        claims: ["AI coding tools can speed onboarding."],
        events: ["A team expanded Claude Code usage."],
        metrics: ["30% faster setup"],
        contentType: .analysis,
        possibleTopics: ["Claude Code in large Swift codebases"],
        importanceScore: 0.82,
        modelName: "gpt-test",
        generatedAt: fixedDate
    )
    let topic = Topic(
        id: "topic-1",
        name: "Claude Code performance in large Swift codebases",
        description: "Tracks Claude Code behavior on large Swift projects.",
        status: topicStatus,
        createdAt: fixedDate,
        updatedAt: fixedDate
    )
    let relationship = TopicArticle(
        topicID: topic.id,
        articleID: article.id,
        confidence: 0.93,
        reason: "Matches the topic.",
        contributionType: .newData,
        createdAt: fixedDate
    )

    try repositories.feeds.save(feed)
    try repositories.articles.save(article)
    try repositories.articleAnalyses.save(analysis)
    try repositories.topics.save(topic)
    try repositories.topicArticles.save(relationship)
}

private func brief(topicID: String, briefType: TopicBriefType, generatedAt: Date) -> TopicBrief {
    TopicBrief(
        topicID: topicID,
        briefType: briefType,
        currentTakeaway: "Cached takeaway",
        latestChanges: [TopicBriefChange(text: "Latest change")],
        evidence: [
            TopicBriefEvidence(
                content: "Evidence",
                sourceArticleID: "article-1",
                sourceArticleTitle: "Claude Code adoption update",
                sourceName: "Example Feed",
                sourceURL: URL(string: "https://example.com/article-1")!,
                publishedAt: fixedDate
            )
        ],
        questionsToWatch: ["Question"],
        relatedArticleIDs: ["article-1"],
        modelName: "gpt-test",
        generatedAt: generatedAt
    )
}

private func makeRepositories() throws -> RSSRadarRepositories {
    let directoryURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("RSSRadarTopicBriefGenerationUseCaseTests", isDirectory: true)
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    let databaseURL = directoryURL.appendingPathComponent("rssradar.sqlite")
    let database = try RSSRadarDatabase(path: databaseURL.path)
    try database.migrate()
    return RSSRadarRepositories(database: database)
}

private actor RecordingTopicBriefGenerator: TopicBriefGenerating {
    private(set) var requests: [TopicBriefGenerationRequest] = []
    private let brief: TopicBrief

    init(brief: TopicBrief) {
        self.brief = brief
    }

    func generateBrief(
        topic: Topic,
        relatedArticles: [TopicBriefSourceArticle],
        briefType: TopicBriefType,
        modelName: String,
        generatedAt: Date
    ) async throws -> TopicBrief {
        requests.append(
            TopicBriefGenerationRequest(
                topic: topic,
                relatedArticles: relatedArticles,
                briefType: briefType,
                modelName: modelName,
                generatedAt: generatedAt
            )
        )
        return brief
    }

    func allRequests() -> [TopicBriefGenerationRequest] {
        requests
    }
}

private actor FailingTopicBriefGenerator: TopicBriefGenerating {
    enum Failure: Error {
        case expected
    }

    func generateBrief(
        topic: Topic,
        relatedArticles: [TopicBriefSourceArticle],
        briefType: TopicBriefType,
        modelName: String,
        generatedAt: Date
    ) async throws -> TopicBrief {
        throw Failure.expected
    }
}

private struct TopicBriefGenerationRequest: Sendable {
    var topic: Topic
    var relatedArticles: [TopicBriefSourceArticle]
    var briefType: TopicBriefType
    var modelName: String
    var generatedAt: Date
}

private let fixedDate = Date(timeIntervalSince1970: 1_700_000_000)
