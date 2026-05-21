import Foundation
import RSSRadarAI
import RSSRadarCore
import RSSRadarPersistence
import RSSRadarProcessing
import XCTest

final class ArticleAnalysisUseCaseTests: XCTestCase {
    func testAnalyzeArticlePersistsAnalysisAndMarksArticleAnalyzed() async throws {
        let repositories = try makeRepositories()
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
            title: "OpenAI improves local-first API workflow",
            url: URL(string: "https://example.com/openai-local-first")!,
            content: "Local-first RSS analysis keeps durable data in SQLite.",
            status: .parsed,
            createdAt: fixedDate,
            updatedAt: fixedDate
        )
        try repositories.feeds.save(feed)
        try repositories.articles.save(article)
        let analyzer = RecordingArticleAnalyzer()
        let useCase = ArticleAnalysisUseCase(repositories: repositories, analyzer: analyzer)

        let analysis = try await useCase.analyzeArticle(
            id: article.id,
            modelName: "gpt-test",
            generatedAt: fixedDate.addingTimeInterval(10)
        )
        let persistedAnalysis = try XCTUnwrap(repositories.articleAnalyses.fetch(articleID: article.id))
        let updatedArticle = try XCTUnwrap(repositories.articles.fetch(id: article.id))
        let capturedRequest = await analyzer.request

        XCTAssertEqual(analysis.articleID, article.id)
        XCTAssertEqual(persistedAnalysis.summary, "Fixture summary")
        XCTAssertEqual(persistedAnalysis.keyPoints, ["Point A", "Point B"])
        XCTAssertEqual(persistedAnalysis.entities, ["OpenAI"])
        XCTAssertEqual(persistedAnalysis.claims, ["Claim A"])
        XCTAssertEqual(persistedAnalysis.events, ["Event A"])
        XCTAssertEqual(persistedAnalysis.metrics, ["Metric A"])
        XCTAssertEqual(persistedAnalysis.contentType, .analysis)
        XCTAssertEqual(persistedAnalysis.possibleTopics, ["Local-first AI workflows"])
        XCTAssertEqual(persistedAnalysis.importanceScore, 0.76)
        XCTAssertEqual(persistedAnalysis.modelName, "gpt-test")
        XCTAssertEqual(updatedArticle.status, .analyzed)
        XCTAssertEqual(updatedArticle.importanceScore, 0.76)
        XCTAssertNil(updatedArticle.errorMessage)
        XCTAssertEqual(capturedRequest?.article.id, article.id)
        XCTAssertEqual(capturedRequest?.sourceTitle, "Example Feed")
        XCTAssertEqual(capturedRequest?.modelName, "gpt-test")
    }

    func testProcessingEngineExecutorRunsAnalyzeArticleJobWhenAnalyzerIsInjected() async throws {
        let repositories = try makeRepositories()
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
            title: "OpenAI improves local-first API workflow",
            url: URL(string: "https://example.com/openai-local-first")!,
            content: "Local-first RSS analysis keeps durable data in SQLite.",
            status: .parsed,
            createdAt: fixedDate,
            updatedAt: fixedDate
        )
        try repositories.feeds.save(feed)
        try repositories.articles.save(article)
        let executor = ProcessingEngineExecutor(
            repositories: repositories,
            articleAnalyzer: RecordingArticleAnalyzer()
        )
        let engine = ProcessingEngine(repositories: repositories, executor: executor)
        let job = ProcessingJob(
            id: "analyze-job-1",
            jobType: .analyzeArticle,
            entityType: .article,
            entityID: article.id,
            payload: ["model_name": "gpt-test"],
            scheduledAt: fixedDate,
            createdAt: fixedDate,
            updatedAt: fixedDate
        )
        try repositories.processingJobs.save(job)

        await engine.runPendingJobs(now: fixedDate.addingTimeInterval(1))

        let completedJob = try XCTUnwrap(repositories.processingJobs.fetch(id: job.id))
        let persistedAnalysis = try XCTUnwrap(repositories.articleAnalyses.fetch(articleID: article.id))
        let updatedArticle = try XCTUnwrap(repositories.articles.fetch(id: article.id))

        XCTAssertEqual(completedJob.status, .completed)
        XCTAssertEqual(persistedAnalysis.summary, "Fixture summary")
        XCTAssertEqual(updatedArticle.status, .analyzed)
    }
}

private extension ArticleAnalysisUseCaseTests {
    func makeRepositories() throws -> RSSRadarRepositories {
        let directoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("RSSRadarArticleAnalysisUseCaseTests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let databaseURL = directoryURL.appendingPathComponent("rssradar.sqlite")
        let database = try RSSRadarDatabase(path: databaseURL.path)
        try database.migrate()
        return RSSRadarRepositories(database: database)
    }
}

private actor RecordingArticleAnalyzer: ArticleAnalyzing {
    private(set) var request: ArticleAnalysisRequest?

    func analyze(
        article: Article,
        sourceTitle: String,
        modelName: String,
        generatedAt: Date
    ) async throws -> ArticleAnalysis {
        request = ArticleAnalysisRequest(
            article: article,
            sourceTitle: sourceTitle,
            modelName: modelName,
            generatedAt: generatedAt
        )
        return ArticleAnalysis(
            articleID: article.id,
            summary: "Fixture summary",
            keyPoints: ["Point A", "Point B"],
            entities: ["OpenAI"],
            claims: ["Claim A"],
            events: ["Event A"],
            metrics: ["Metric A"],
            contentType: .analysis,
            possibleTopics: ["Local-first AI workflows"],
            importanceScore: 0.76,
            modelName: modelName,
            generatedAt: generatedAt
        )
    }
}

private struct ArticleAnalysisRequest: Sendable {
    var article: Article
    var sourceTitle: String
    var modelName: String
    var generatedAt: Date
}

private let fixedDate = Date(timeIntervalSince1970: 1_700_000_000)
