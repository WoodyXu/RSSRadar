// swiftlint:disable file_length
import Foundation
import RSSRadarAI
import RSSRadarCore
import RSSRadarExport
import RSSRadarFeeds
import RSSRadarPersistence
import RSSRadarProcessing
import XCTest

final class MVPEndToEndAcceptanceTests: XCTestCase {
    func testMVPFlowFromEmptyDatabaseToMarkdownExport() async throws {
        let repositories = try makeRepositories()
        XCTAssertTrue(try repositories.feeds.fetchAll().isEmpty)
        XCTAssertTrue(try repositories.topics.fetchAll().isEmpty)

        try configureSupportedProviders(repositories: repositories)
        let loader = AcceptanceFeedDataLoader()
        let manualFeed = try await importSources(repositories: repositories, loader: loader)
        try await scanAndValidateArticles(repositories: repositories, loader: loader, manualFeed: manualFeed)
        let analyzedArticleIDs = try await analyzeArticlesWithRetry(repositories: repositories)
        let activeTopic = try await createAndTrackTopic(repositories: repositories, articleIDs: analyzedArticleIDs)
        try await updateActiveTopicAndGenerateBrief(
            repositories: repositories,
            topic: activeTopic,
            articleID: analyzedArticleIDs[0]
        )
        try exportAndValidateMarkdown(repositories: repositories, topicID: activeTopic.id)
    }

    private func importSources(
        repositories: RSSRadarRepositories,
        loader: AcceptanceFeedDataLoader
    ) async throws -> Feed {
        let manualFeed = try await ManualFeedAddUseCase(repositories: repositories, loader: loader)
            .addFeed(urlString: "https://manual.example.com/feed.xml", now: acceptanceNow)
        let opmlData = try fixtureData(name: "feeds", extension: "opml")
        let importResult = try OPMLImportUseCase(repositories: repositories)
            .importOPML(data: opmlData, now: acceptanceNow)

        XCTAssertEqual(manualFeed.status, .active)
        XCTAssertEqual(importResult.importedFeeds.count, 3)
        XCTAssertEqual(importResult.skippedDuplicates.count, 1)
        XCTAssertEqual(importResult.errors.count, 2)
        XCTAssertEqual(try repositories.feeds.fetchAll().count, 4)
        return manualFeed
    }

    private func scanAndValidateArticles(
        repositories: RSSRadarRepositories,
        loader: AcceptanceFeedDataLoader,
        manualFeed: Feed
    ) async throws {
        let scanEngine = ProcessingEngine(
            repositories: repositories,
            executor: ProcessingEngineExecutor(repositories: repositories, loader: loader),
            configuration: ProcessingEngineConfiguration(maxConcurrentFeedFetchJobs: 8)
        )
        let scanJobs = try await scanEngine.enqueueScanAllFeeds(scheduledAt: acceptanceNow)
        await scanEngine.runPendingJobs(now: acceptanceNow.addingTimeInterval(1))

        let completedScanJobs = try repositories.processingJobs.fetch(status: .completed)
            .filter { $0.jobType == .fetchFeed }
        let articlesAfterFirstScan = try repositories.articles.fetchAll()
        let firstScannedFeed = try XCTUnwrap(repositories.feeds.fetch(id: manualFeed.id))

        XCTAssertEqual(scanJobs.count, 4)
        XCTAssertEqual(completedScanJobs.count, 4)
        XCTAssertEqual(articlesAfterFirstScan.count, 80)
        XCTAssertEqual(firstScannedFeed.lastProcessedArticlePublishedAt, acceptanceArticleDate(day: 22))
        XCTAssertTrue(articlesAfterFirstScan.contains { $0.contentSource == .rssSummary })
        XCTAssertTrue(articlesAfterFirstScan.allSatisfy { $0.status == .parsed })

        _ = try await FeedScanUseCase(repositories: repositories, loader: loader)
            .scanFeed(id: manualFeed.id, now: acceptanceNow.addingTimeInterval(120))
        XCTAssertEqual(try repositories.articles.fetchAll().count, articlesAfterFirstScan.count)
    }

    private func analyzeArticlesWithRetry(repositories: RSSRadarRepositories) async throws -> [String] {
        let parsedArticles = try repositories.articles.fetch(status: .parsed).sorted { $0.title < $1.title }
        let flakyArticleID = try XCTUnwrap(parsedArticles.first?.id)
        try saveRetryAnalysisJob(articleID: flakyArticleID, repositories: repositories)

        let retryEngine = ProcessingEngine(
            repositories: repositories,
            executor: ProcessingEngineExecutor(
                repositories: repositories,
                articleAnalyzer: FlakyAcceptanceArticleAnalyzer()
            ),
            configuration: ProcessingEngineConfiguration(maxConcurrentAnalyzeArticleJobs: 1, retryBackoffSeconds: [0])
        )
        await retryEngine.runPendingJobs(now: acceptanceNow.addingTimeInterval(2))
        let pendingRetryJob = try XCTUnwrap(repositories.processingJobs.fetch(id: "acceptance-ai-retry"))
        XCTAssertEqual(pendingRetryJob.status, .pending)
        await retryEngine.runPendingJobs(now: pendingRetryJob.scheduledAt.addingTimeInterval(1))
        XCTAssertEqual(try repositories.processingJobs.fetch(id: "acceptance-ai-retry")?.status, .completed)
        XCTAssertEqual(try repositories.processingJobs.fetch(id: "acceptance-ai-retry")?.attemptCount, 1)

        try await analyzeTwoMoreParsedArticles(repositories: repositories)
        let analyzedArticleIDs = try repositories.articles.fetch(status: .analyzed).map(\.id).sorted()
        XCTAssertEqual(analyzedArticleIDs.count, 3)
        return analyzedArticleIDs
    }

    private func createAndTrackTopic(
        repositories: RSSRadarRepositories,
        articleIDs: [String]
    ) async throws -> Topic {
        _ = try await TopicAssignmentUseCase(
            repositories: repositories,
            topicAssigner: AcceptanceTopicAssigner(mode: .createCandidates)
        )
        .assignTopics(
            articleIDs: articleIDs,
            modelName: "gpt-acceptance",
            assignedAt: acceptanceNow.addingTimeInterval(5)
        )

        let candidateUseCase = CandidateTopicManagementUseCase(repositories: repositories)
        let candidates = try candidateUseCase.listCandidates().sorted { $0.topic.name < $1.topic.name }
        let candidateForPreview = try XCTUnwrap(candidates.first?.topic)
        XCTAssertGreaterThanOrEqual(candidates.count, 2)
        XCTAssertTrue(candidates.first?.articleCount ?? 0 > 0)

        try await validateCandidatePreview(topicID: candidateForPreview.id, repositories: repositories)
        let activeTopic = try trackFirstAndIgnoreSecondCandidate(
            candidateUseCase: candidateUseCase,
            candidates: candidates,
            candidateForPreview: candidateForPreview
        )
        XCTAssertEqual(activeTopic.status, .active)
        XCTAssertEqual(activeTopic.name, "Claude Code rollout effects in Swift teams")
        XCTAssertEqual(try repositories.topics.fetch(status: .ignored).count, 1)
        return activeTopic
    }

    private func updateActiveTopicAndGenerateBrief(
        repositories: RSSRadarRepositories,
        topic: Topic,
        articleID: String
    ) async throws {
        let activeAssigner = AcceptanceTopicAssigner(mode: .matchActiveTopic(topicID: topic.id))
        _ = try await TopicAssignmentUseCase(repositories: repositories, topicAssigner: activeAssigner)
            .assignTopics(
                articleIDs: [articleID],
                modelName: "gpt-acceptance",
                assignedAt: acceptanceNow.addingTimeInterval(11)
            )
        let assignerRequest = await activeAssigner.lastRequest()
        let existingTopicPrompt = try XCTUnwrap(assignerRequest?.existingTopics.first { $0.id == topic.id })
        XCTAssertEqual(existingTopicPrompt.name, "Claude Code rollout effects in Swift teams")
        XCTAssertEqual(
            existingTopicPrompt.description,
            "Tracks how Claude Code changes Swift team refactoring and onboarding."
        )

        let briefEngine = ProcessingEngine(
            repositories: repositories,
            executor: ProcessingEngineExecutor(
                repositories: repositories,
                topicBriefGenerator: AcceptanceTopicBriefGenerator()
            ),
            configuration: ProcessingEngineConfiguration(maxConcurrentGenerateTopicBriefJobs: 2)
        )
        await briefEngine.runPendingJobs(now: acceptanceNow.addingTimeInterval(12))
    }

    private func exportAndValidateMarkdown(repositories: RSSRadarRepositories, topicID: String) throws {
        let fullBrief = try XCTUnwrap(repositories.topicBriefs.fetch(topicID: topicID, briefType: .full))
        let topicDetail = try TopicDetailDataSource(repositories: repositories).load(topicID: topicID)
        let markdownService = TopicBriefMarkdownExportService(clipboardWriter: AcceptanceClipboardWriter())
        let markdown = try markdownService.copyMarkdown(snapshot: topicDetail)
        let exportURL = temporaryDirectory()
            .appendingPathComponent("RSSRadarMVPEndToEndAcceptance", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
            .appendingPathComponent("topic.md")
        let exportedMarkdown = try markdownService.exportMarkdown(snapshot: topicDetail, to: exportURL)

        XCTAssertEqual(topicDetail.briefType, .full)
        XCTAssertEqual(topicDetail.brief?.id, fullBrief.id)
        XCTAssertFalse(topicDetail.evidence.isEmpty)
        XCTAssertNotNil(topicDetail.evidence.first?.sourceArticle)
        XCTAssertNotNil(topicDetail.evidence.first?.analysisSummary)
        XCTAssertTrue(topicDetail.relatedArticles.contains { $0.analysisSummary?.isEmpty == false })
        XCTAssertTrue(markdown.contains("# Claude Code rollout effects in Swift teams"))
        XCTAssertTrue(markdown.contains("## 当前结论"))
        XCTAssertTrue(markdown.contains("## 时间线"))
        XCTAssertTrue(markdown.contains("## 主要观点分歧"))
        XCTAssertTrue(markdown.contains("## 关键证据"))
        XCTAssertTrue(markdown.contains("## 接下来值得观察"))
        XCTAssertTrue(markdown.contains("## 相关文章"))
        XCTAssertEqual(try String(contentsOf: exportURL, encoding: .utf8), exportedMarkdown)
        XCTAssertFalse(exportedMarkdown.isEmpty)
    }
}

private func configureSupportedProviders(
    repositories: RSSRadarRepositories
) throws {
    let keychain = KeychainAPIKeyStore(service: "com.rssradar.acceptance.\(UUID().uuidString)")
    let accountIdentifier = "acceptance-\(UUID().uuidString)"
    defer {
        try? keychain.deleteAPIKey(accountIdentifier: accountIdentifier)
    }

    try keychain.saveAPIKey("acceptance-key", accountIdentifier: accountIdentifier)
    XCTAssertEqual(try keychain.readAPIKey(accountIdentifier: accountIdentifier), "acceptance-key")

    var settings = AppSettings(
        aiProvider: .openAICompatible,
        baseURL: URL(string: "https://api.openai.com/v1")!,
        modelName: "gpt-acceptance",
        keychainAccountIdentifier: accountIdentifier,
        scanMode: .manual,
        maxArticlesPerScan: 3
    )
    try repositories.appSettings.save(settings)
    XCTAssertEqual(try repositories.appSettings.fetch().aiProvider, .openAICompatible)

    settings.aiProvider = .anthropic
    settings.baseURL = URL(string: "https://api.anthropic.com")!
    settings.scanMode = .onLaunch
    try repositories.appSettings.save(settings)
    XCTAssertEqual(try repositories.appSettings.fetch().scanMode, .onLaunch)

    settings.aiProvider = .custom
    settings.baseURL = URL(string: "https://models.example.com/v1")!
    settings.scanMode = .interval
    settings.scanIntervalHours = 2
    try repositories.appSettings.save(settings)
    let persisted = try repositories.appSettings.fetch()
    XCTAssertEqual(persisted.aiProvider, .custom)
    XCTAssertEqual(persisted.baseURL.absoluteString, "https://models.example.com/v1")
    XCTAssertEqual(persisted.scanMode, .interval)
    XCTAssertEqual(persisted.scanIntervalHours, 2)
    XCTAssertEqual(persisted.maxArticlesPerScan, 3)
}

private func saveRetryAnalysisJob(articleID: String, repositories: RSSRadarRepositories) throws {
    try repositories.processingJobs.save(
        ProcessingJob(
            id: "acceptance-ai-retry",
            jobType: .analyzeArticle,
            entityType: .article,
            entityID: articleID,
            payload: ["model_name": "gpt-acceptance"],
            scheduledAt: acceptanceNow,
            createdAt: acceptanceNow,
            updatedAt: acceptanceNow
        )
    )
}

private func analyzeTwoMoreParsedArticles(repositories: RSSRadarRepositories) async throws {
    let remainingParsedArticles = try repositories.articles.fetch(status: .parsed)
        .sorted { $0.title < $1.title }
        .prefix(2)
    let articleAnalysisUseCase = ArticleAnalysisUseCase(
        repositories: repositories,
        analyzer: DeterministicAcceptanceArticleAnalyzer()
    )
    for article in remainingParsedArticles {
        _ = try await articleAnalysisUseCase.analyzeArticle(
            id: article.id,
            modelName: "gpt-acceptance",
            generatedAt: acceptanceNow.addingTimeInterval(4)
        )
    }
}

private func validateCandidatePreview(topicID: String, repositories: RSSRadarRepositories) async throws {
    let preview = try await TopicBriefGenerationUseCase(
        repositories: repositories,
        generator: AcceptanceTopicBriefGenerator()
    )
    .generateIfNeeded(
        topicID: topicID,
        briefType: .preview,
        modelName: "gpt-acceptance",
        generatedAt: acceptanceNow.addingTimeInterval(6)
    )
    XCTAssertEqual(preview.brief.briefType, .preview)
    XCTAssertFalse(preview.brief.currentTakeaway.isEmpty)
}

private func trackFirstAndIgnoreSecondCandidate(
    candidateUseCase: CandidateTopicManagementUseCase,
    candidates: [CandidateTopicPreview],
    candidateForPreview: Topic
) throws -> Topic {
    let renamedCandidate = try candidateUseCase.renameCandidate(
        id: candidateForPreview.id,
        name: "Claude Code rollout effects in Swift teams",
        updatedAt: acceptanceNow.addingTimeInterval(7)
    )
    let describedCandidate = try candidateUseCase.updateCandidateDescription(
        id: renamedCandidate.id,
        description: "Tracks how Claude Code changes Swift team refactoring and onboarding.",
        updatedAt: acceptanceNow.addingTimeInterval(8)
    )
    let activeTopic = try candidateUseCase.trackCandidate(
        id: describedCandidate.id,
        updatedAt: acceptanceNow.addingTimeInterval(9)
    )
    if let ignoredCandidateID = candidates.map(\.topic.id).first(where: { $0 != activeTopic.id }) {
        _ = try candidateUseCase.ignoreCandidate(
            id: ignoredCandidateID,
            updatedAt: acceptanceNow.addingTimeInterval(10)
        )
    }
    return activeTopic
}

private struct AcceptanceFeedDataLoader: FeedDataLoader {
    func data(from url: URL) async throws -> (Data, URLResponse) {
        let data = try fixtureData(name: "many-articles-rss", extension: "xml")
        let response = HTTPURLResponse(
            url: url,
            statusCode: 200,
            httpVersion: nil,
            headerFields: nil
        )!
        return (data, response)
    }
}

private actor FlakyAcceptanceArticleAnalyzer: ArticleAnalyzing {
    private var attempts = 0

    func analyze(
        article: Article,
        sourceTitle: String,
        modelName: String,
        generatedAt: Date
    ) async throws -> ArticleAnalysis {
        attempts += 1
        if attempts == 1 {
            throw ArticleAnalysisValidationError.emptyField("summary")
        }
        return acceptanceAnalysis(article: article, modelName: modelName, generatedAt: generatedAt)
    }
}

private struct DeterministicAcceptanceArticleAnalyzer: ArticleAnalyzing {
    func analyze(
        article: Article,
        sourceTitle: String,
        modelName: String,
        generatedAt: Date
    ) async throws -> ArticleAnalysis {
        acceptanceAnalysis(article: article, modelName: modelName, generatedAt: generatedAt)
    }
}

private func acceptanceAnalysis(article: Article, modelName: String, generatedAt: Date) -> ArticleAnalysis {
    ArticleAnalysis(
        articleID: article.id,
        summary: "\(article.title) signals continued Claude Code adoption in Swift teams.",
        keyPoints: ["Teams report better multi-file editing.", "Onboarding impact remains important."],
        entities: ["Claude Code", "Swift teams", "AI coding tools"],
        claims: ["Claude Code can improve large-codebase refactoring workflows."],
        events: ["A Swift team expanded Claude Code usage."],
        metrics: ["30% faster setup"],
        contentType: .analysis,
        possibleTopics: ["Claude Code rollout effects in Swift teams"],
        importanceScore: 0.82,
        modelName: modelName,
        generatedAt: generatedAt
    )
}

private actor AcceptanceTopicAssigner: TopicAssigning {
    enum Mode {
        case createCandidates
        case matchActiveTopic(topicID: String)
    }

    private let mode: Mode
    private var request: AcceptanceTopicAssignmentRequest?

    init(mode: Mode) {
        self.mode = mode
    }

    func assignTopics(
        analyses: [ArticleAnalysis],
        existingTopics: [Topic],
        modelName: String,
        assignedAt: Date
    ) async throws -> TopicAssignmentResult {
        request = AcceptanceTopicAssignmentRequest(
            analyses: analyses,
            existingTopics: existingTopics,
            modelName: modelName,
            assignedAt: assignedAt
        )

        switch mode {
        case .createCandidates:
            return TopicAssignmentResult(
                assignments: candidateAssignments(for: analyses),
                modelName: modelName
            )

        case let .matchActiveTopic(topicID):
            return TopicAssignmentResult(
                assignments: activeAssignments(for: analyses, topicID: topicID),
                modelName: modelName
            )
        }
    }

    func lastRequest() -> AcceptanceTopicAssignmentRequest? {
        request
    }

    private func candidateAssignments(for analyses: [ArticleAnalysis]) -> [TopicAssignment] {
        analyses.enumerated().flatMap { index, analysis -> [TopicAssignment] in
            index == 0 ? firstCandidateAssignments(articleID: analysis.articleID) : [
                claudeCodeAssignment(articleID: analysis.articleID, confidence: 0.88, contributionType: .newData)
            ]
        }
    }

    private func firstCandidateAssignments(articleID: String) -> [TopicAssignment] {
        [
            claudeCodeAssignment(articleID: articleID, confidence: 0.91, contributionType: .newEvent),
            TopicAssignment(
                articleID: articleID,
                newTopic: NewTopicCandidate(
                    name: "AI coding tools reshape junior developer onboarding",
                    description: "Tracks onboarding changes from AI coding tools.",
                    entities: ["AI coding tools", "junior developers"],
                    importanceScore: 0.76
                ),
                confidence: 0.81,
                reason: "The article also discusses onboarding impact.",
                contributionType: .newOpinion
            )
        ]
    }

    private func claudeCodeAssignment(
        articleID: String,
        confidence: Double,
        contributionType: TopicContributionType
    ) -> TopicAssignment {
        TopicAssignment(
            articleID: articleID,
            newTopic: NewTopicCandidate(
                name: "Claude Code adoption in Swift refactors",
                description: "Tracks Claude Code usage in Swift refactoring work.",
                entities: ["Claude Code", "Swift"],
                importanceScore: 0.84
            ),
            confidence: confidence,
            reason: "The article adds evidence for the Claude Code topic.",
            contributionType: contributionType
        )
    }

    private func activeAssignments(for analyses: [ArticleAnalysis], topicID: String) -> [TopicAssignment] {
        analyses.map { analysis in
            TopicAssignment(
                articleID: analysis.articleID,
                topicID: topicID,
                confidence: 0.94,
                reason: "Matches the edited active topic scope.",
                contributionType: .newData
            )
        }
    }
}

private struct AcceptanceTopicAssignmentRequest: Sendable {
    var analyses: [ArticleAnalysis]
    var existingTopics: [Topic]
    var modelName: String
    var assignedAt: Date
}

private struct AcceptanceTopicBriefGenerator: TopicBriefGenerating {
    func generateBrief(
        topic: Topic,
        relatedArticles: [TopicBriefSourceArticle],
        briefType: TopicBriefType,
        modelName: String,
        generatedAt: Date
    ) async throws -> TopicBrief {
        let firstArticle = relatedArticles[0].article
        return TopicBrief(
            topicID: topic.id,
            briefType: briefType,
            currentTakeaway: "\(topic.name) is worth tracking based on recent source evidence.",
            latestChanges: [
                TopicBriefChange(
                    text: "Recent articles added evidence about Claude Code adoption.",
                    articleIDs: [firstArticle.id]
                )
            ],
            timeline: [
                TopicBriefTimelineItem(
                    date: firstArticle.publishedAt,
                    title: "Adoption update",
                    description: "A source reported expanded Claude Code usage.",
                    articleIDs: [firstArticle.id]
                )
            ],
            viewpoints: [
                TopicBriefViewpoint(
                    title: "Practitioner view",
                    summary: "Teams are optimistic but still watching quality.",
                    articleIDs: [firstArticle.id]
                )
            ],
            evidence: [
                TopicBriefEvidence(
                    content: "The source reported a 30% faster setup metric.",
                    sourceArticleID: firstArticle.id,
                    sourceArticleTitle: firstArticle.title,
                    sourceName: relatedArticles[0].feedTitle,
                    sourceURL: firstArticle.url,
                    publishedAt: firstArticle.publishedAt
                )
            ],
            questionsToWatch: ["Whether the gains persist after onboarding."],
            relatedArticleIDs: relatedArticles.map(\.article.id),
            modelName: modelName,
            generatedAt: generatedAt
        )
    }
}

private final class AcceptanceClipboardWriter: MarkdownClipboardWriting, @unchecked Sendable {
    private(set) var markdown: String?

    func writeMarkdown(_ markdown: String) throws {
        self.markdown = markdown
    }
}

private func makeRepositories() throws -> RSSRadarRepositories {
    let databaseURL = temporaryDirectory()
        .appendingPathComponent("RSSRadarMVPEndToEndAcceptanceTests", isDirectory: true)
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
        .appendingPathComponent("rssradar.sqlite")
    let database = try RSSRadarDatabase(path: databaseURL.path)
    try database.migrate()
    return RSSRadarRepositories(database: database)
}

private func fixtureData(name: String, extension fileExtension: String) throws -> Data {
    let url = try XCTUnwrap(Bundle.module.url(forResource: name, withExtension: fileExtension))
    return try Data(contentsOf: url)
}

private func temporaryDirectory() -> URL {
    FileManager.default.temporaryDirectory
}

private func acceptanceArticleDate(day: Int) -> Date {
    ISO8601DateFormatter().date(from: "2026-05-\(String(format: "%02d", day))T10:00:00Z")!
}

private let acceptanceNow = Date(timeIntervalSince1970: 1_778_889_600)
