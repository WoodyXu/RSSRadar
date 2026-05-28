import Foundation
import RSSRadarAI
import RSSRadarCore
import RSSRadarPersistence
import RSSRadarProcessing
import XCTest

final class TopicAssignmentUseCaseTests: XCTestCase {
    func testAssignTopicsPersistsExistingAndNewTopicRelationships() async throws {
        let repositories = try makeRepositories()
        try seedAnalyzedArticle(id: "article-1", repositories: repositories)
        let existingTopic = Topic(
            id: "topic-existing",
            name: "Claude Code performance in large Swift codebases",
            description: "Tracks Claude Code behavior on large codebases.",
            status: .active,
            createdAt: fixedDate,
            updatedAt: fixedDate
        )
        try repositories.topics.save(existingTopic)
        let assigner = RecordingTopicAssigner(result: existingAndNewTopicAssignmentResult(topicID: existingTopic.id))
        let useCase = TopicAssignmentUseCase(repositories: repositories, topicAssigner: assigner)

        let result = try await useCase.assignTopics(
            articleIDs: ["article-1"],
            modelName: "gpt-test",
            assignedAt: fixedDate.addingTimeInterval(10)
        )
        let createdTopic = try XCTUnwrap(result.topicsCreated.first)
        let existingRelationship = try XCTUnwrap(
            repositories.topicArticles.fetch(topicID: existingTopic.id, articleID: "article-1")
        )
        let newRelationship = try XCTUnwrap(
            repositories.topicArticles.fetch(topicID: createdTopic.id, articleID: "article-1")
        )
        let updatedArticle = try XCTUnwrap(repositories.articles.fetch(id: "article-1"))
        let request = await assigner.request

        XCTAssertEqual(result.modelName, "gpt-topic")
        XCTAssertEqual(result.topicsCreated.count, 1)
        XCTAssertEqual(createdTopic.status, .candidate)
        XCTAssertEqual(createdTopic.name, "AI coding tools reshape junior developer onboarding")
        XCTAssertEqual(createdTopic.originalAIName, createdTopic.name)
        XCTAssertEqual(createdTopic.entities, ["AI coding tools", "junior developers"])
        XCTAssertEqual(createdTopic.importanceScore, 0.78)
        XCTAssertEqual(existingRelationship.confidence, 0.91)
        XCTAssertEqual(existingRelationship.contributionType, .newEvent)
        XCTAssertEqual(newRelationship.confidence, 0.84)
        XCTAssertEqual(newRelationship.contributionType, .newOpinion)
        XCTAssertEqual(updatedArticle.status, .assigned)
        XCTAssertNil(updatedArticle.errorMessage)
        XCTAssertEqual(request?.analyses.map(\.articleID), ["article-1"])
        XCTAssertEqual(request?.existingTopics.map(\.id), [existingTopic.id])
        XCTAssertEqual(request?.modelName, "gpt-test")
    }

    func testProcessingEngineExecutorRunsAssignTopicsJobWhenAssignerIsInjected() async throws {
        let repositories = try makeRepositories()
        try seedAnalyzedArticle(id: "article-1", repositories: repositories)
        let assigner = RecordingTopicAssigner(
            result: TopicAssignmentResult(
                assignments: [
                    TopicAssignment(
                        articleID: "article-1",
                        newTopic: NewTopicCandidate(
                            name: "AI coding tools reshape junior developer onboarding",
                            description: "Tracks onboarding impact from AI coding tools."
                        ),
                        confidence: 0.84,
                        reason: "The article discusses onboarding.",
                        contributionType: .newOpinion
                    )
                ],
                modelName: "gpt-topic"
            )
        )
        let executor = ProcessingEngineExecutor(repositories: repositories, topicAssigner: assigner)
        let engine = ProcessingEngine(repositories: repositories, executor: executor)
        let job = ProcessingJob(
            id: "assign-job-1",
            jobType: .assignTopics,
            entityType: .article,
            entityID: "article-1",
            payload: [
                "article_ids": "article-1",
                "model_name": "gpt-test"
            ],
            scheduledAt: fixedDate,
            createdAt: fixedDate,
            updatedAt: fixedDate
        )
        try repositories.processingJobs.save(job)

        await engine.runPendingJobs(now: fixedDate.addingTimeInterval(1))

        let completedJob = try XCTUnwrap(repositories.processingJobs.fetch(id: job.id))
        let topics = try repositories.topics.fetch(status: .candidate)
        let updatedArticle = try XCTUnwrap(repositories.articles.fetch(id: "article-1"))

        XCTAssertEqual(completedJob.status, .completed)
        XCTAssertEqual(topics.count, 1)
        XCTAssertEqual(try repositories.topicArticles.fetchForArticle(id: "article-1").count, 1)
        XCTAssertEqual(updatedArticle.status, .assigned)
    }

    func testActiveTopicUpdateUsesEditedNameWithoutQueuingBriefGeneration() async throws {
        let repositories = try makeRepositories()
        try seedAnalyzedArticle(id: "article-1", repositories: repositories)
        let activeTopic = Topic(
            id: "topic-active",
            name: "User edited Claude Code enterprise rollout",
            description: "User edited description for enterprise adoption tracking.",
            originalAIName: "Claude Code adoption",
            originalAIDescription: "Original AI topic description.",
            status: .active,
            createdAt: fixedDate,
            updatedAt: fixedDate.addingTimeInterval(5)
        )
        let staleRelationship = TopicArticle(
            topicID: activeTopic.id,
            articleID: "article-1",
            confidence: 0.21,
            reason: "Old matching reason.",
            contributionType: .background,
            createdAt: fixedDate
        )
        try repositories.topics.save(activeTopic)
        try repositories.topicArticles.save(staleRelationship)
        let assigner = RecordingTopicAssigner(
            result: TopicAssignmentResult(
                assignments: [
                    TopicAssignment(
                        articleID: "article-1",
                        topicID: activeTopic.id,
                        confidence: 0.93,
                        reason: "Matches the edited enterprise rollout topic.",
                        contributionType: .newData
                    )
                ],
                modelName: "gpt-topic"
            )
        )
        let useCase = TopicAssignmentUseCase(repositories: repositories, topicAssigner: assigner)

        let result = try await useCase.assignTopics(
            articleIDs: ["article-1"],
            modelName: "gpt-test",
            assignedAt: fixedDate.addingTimeInterval(30)
        )

        let request = await assigner.request
        let requestTopic = try XCTUnwrap(request?.existingTopics.first)
        let updatedRelationship = try XCTUnwrap(
            repositories.topicArticles.fetch(topicID: activeTopic.id, articleID: "article-1")
        )

        XCTAssertEqual(requestTopic.name, activeTopic.name)
        XCTAssertEqual(requestTopic.description, activeTopic.description)
        XCTAssertEqual(updatedRelationship.confidence, 0.93)
        XCTAssertEqual(updatedRelationship.reason, "Matches the edited enterprise rollout topic.")
        XCTAssertEqual(updatedRelationship.contributionType, .newData)
        XCTAssertTrue(result.activeTopicIDsForBriefGeneration.isEmpty)
        XCTAssertTrue(result.topicBriefJobsQueued.isEmpty)
        XCTAssertTrue(try repositories.processingJobs.fetchAll().isEmpty)
    }

    func testEnqueueTopicAssignmentCreatesDefaultSizedArticleBatches() async throws {
        let repositories = try makeRepositories()
        let engine = ProcessingEngine(repositories: repositories, executor: NoOpExecutor())
        let articleIDs = (1...(TopicAssignmentUseCase.defaultBatchSize + 1)).map { "article-\($0)" }

        let jobs = try await engine.enqueueTopicAssignment(
            articleIDs: articleIDs,
            modelName: "gpt-test",
            scheduledAt: fixedDate
        )

        XCTAssertEqual(jobs.count, 2)
        XCTAssertEqual(
            jobs[0].payload["article_ids"]?.split(separator: ",").count,
            TopicAssignmentUseCase.defaultBatchSize
        )
        XCTAssertEqual(jobs[1].payload["article_ids"], "article-\(TopicAssignmentUseCase.defaultBatchSize + 1)")
        XCTAssertEqual(try repositories.processingJobs.fetch(status: .pending).count, 2)
    }

    func testAssignTopicsReusesExistingCandidateWithSameNormalizedName() async throws {
        let repositories = try makeRepositories()
        try seedAnalyzedArticle(id: "article-1", repositories: repositories)
        let existingCandidate = Topic(
            id: "topic-candidate",
            name: "AI coding tools reshape junior developer onboarding",
            description: "Existing candidate.",
            status: .candidate,
            createdAt: fixedDate,
            updatedAt: fixedDate
        )
        try repositories.topics.save(existingCandidate)
        let assigner = RecordingTopicAssigner(
            result: TopicAssignmentResult(
                assignments: [
                    TopicAssignment(
                        articleID: "article-1",
                        newTopic: NewTopicCandidate(
                            name: "  AI   coding tools reshape junior developer onboarding  ",
                            description: "Duplicate candidate."
                        ),
                        confidence: 0.84,
                        reason: "The article discusses the same candidate.",
                        contributionType: .newOpinion
                    )
                ],
                modelName: "gpt-topic"
            )
        )
        let useCase = TopicAssignmentUseCase(repositories: repositories, topicAssigner: assigner)

        let result = try await useCase.assignTopics(
            articleIDs: ["article-1"],
            modelName: "gpt-test",
            assignedAt: fixedDate.addingTimeInterval(10)
        )

        XCTAssertTrue(result.topicsCreated.isEmpty)
        XCTAssertEqual(try repositories.topics.fetch(status: .candidate).count, 1)
        XCTAssertNotNil(try repositories.topicArticles.fetch(topicID: existingCandidate.id, articleID: "article-1"))
    }

    func testAssignTopicsReusesExistingActiveTopicWithSameNormalizedName() async throws {
        let repositories = try makeRepositories()
        try seedAnalyzedArticle(id: "article-1", repositories: repositories)
        let existingActive = Topic(
            id: "topic-active",
            name: "Claude Code",
            description: "Tracks Claude Code product updates and adoption.",
            status: .active,
            createdAt: fixedDate,
            updatedAt: fixedDate
        )
        try repositories.topics.save(existingActive)
        let assigner = RecordingTopicAssigner(
            result: TopicAssignmentResult(
                assignments: [
                    TopicAssignment(
                        articleID: "article-1",
                        newTopic: NewTopicCandidate(
                            name: "  Claude   Code  ",
                            description: "Duplicate active topic."
                        ),
                        confidence: 0.84,
                        reason: "The article centers on Claude Code.",
                        contributionType: .newEvent
                    )
                ],
                modelName: "gpt-topic"
            )
        )
        let useCase = TopicAssignmentUseCase(repositories: repositories, topicAssigner: assigner)

        let result = try await useCase.assignTopics(
            articleIDs: ["article-1"],
            modelName: "gpt-test",
            assignedAt: fixedDate.addingTimeInterval(10)
        )

        XCTAssertTrue(result.topicsCreated.isEmpty)
        XCTAssertEqual(try repositories.topics.fetch(status: .active).count, 1)
        XCTAssertEqual(try repositories.topics.fetch(status: .candidate).count, 0)
        XCTAssertNotNil(try repositories.topicArticles.fetch(topicID: existingActive.id, articleID: "article-1"))
        XCTAssertTrue(result.activeTopicIDsForBriefGeneration.isEmpty)
        XCTAssertTrue(result.topicBriefJobsQueued.isEmpty)
    }
}

private func seedAnalyzedArticle(id articleID: String, repositories: RSSRadarRepositories) throws {
    let feed = Feed(
        id: "feed-\(articleID)",
        title: "Example Feed",
        url: URL(string: "https://example.com/\(articleID)/feed.xml")!,
        createdAt: fixedDate,
        updatedAt: fixedDate
    )
    let article = Article(
        id: articleID,
        feedID: feed.id,
        title: "Claude Code adoption update",
        url: URL(string: "https://example.com/\(articleID)")!,
        content: "Claude Code adoption improved in a large Swift codebase.",
        status: .analyzed,
        createdAt: fixedDate,
        updatedAt: fixedDate
    )
    let analysis = ArticleAnalysis(
        articleID: articleID,
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
    try repositories.feeds.save(feed)
    try repositories.articles.save(article)
    try repositories.articleAnalyses.save(analysis)
}

private func existingAndNewTopicAssignmentResult(topicID: String) -> TopicAssignmentResult {
    TopicAssignmentResult(
        assignments: [
            TopicAssignment(
                articleID: "article-1",
                topicID: topicID,
                confidence: 0.91,
                reason: "Matches the existing Claude Code topic.",
                contributionType: .newEvent
            ),
            TopicAssignment(
                articleID: "article-1",
                newTopic: NewTopicCandidate(
                    name: "AI coding tools reshape junior developer onboarding",
                    description: "Tracks onboarding impact from AI coding tools.",
                    entities: ["AI coding tools", "junior developers"],
                    importanceScore: 0.78
                ),
                confidence: 0.84,
                reason: "The article also discusses junior developer onboarding.",
                contributionType: .newOpinion
            )
        ],
        modelName: "gpt-topic"
    )
}

private func makeRepositories() throws -> RSSRadarRepositories {
    let directoryURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("RSSRadarTopicAssignmentUseCaseTests", isDirectory: true)
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    let databaseURL = directoryURL.appendingPathComponent("rssradar.sqlite")
    let database = try RSSRadarDatabase(path: databaseURL.path)
    try database.migrate()
    return RSSRadarRepositories(database: database)
}

private actor RecordingTopicAssigner: TopicAssigning {
    private(set) var request: TopicAssignmentRequest?
    private let result: TopicAssignmentResult

    init(result: TopicAssignmentResult) {
        self.result = result
    }

    func assignTopics(
        analyses: [ArticleAnalysis],
        existingTopics: [Topic],
        modelName: String,
        assignedAt: Date
    ) async throws -> TopicAssignmentResult {
        request = TopicAssignmentRequest(
            analyses: analyses,
            existingTopics: existingTopics,
            modelName: modelName,
            assignedAt: assignedAt
        )
        return result
    }
}

private struct TopicAssignmentRequest: Sendable {
    var analyses: [ArticleAnalysis]
    var existingTopics: [Topic]
    var modelName: String
    var assignedAt: Date
}

private struct NoOpExecutor: ProcessingJobExecuting {
    func execute(job: ProcessingJob) async throws {}
}

private let fixedDate = Date(timeIntervalSince1970: 1_700_000_000)
