import Foundation
import RSSRadarAI
import RSSRadarCore
import RSSRadarFeeds
import RSSRadarPersistence

public struct ProcessingAISettings: Sendable {
    public var modelName: String
    public var maxArticlesPerScan: Int
    public var maxArticlesPerTopicBatch: Int

    public init(
        modelName: String,
        maxArticlesPerScan: Int,
        maxArticlesPerTopicBatch: Int
    ) {
        self.modelName = modelName
        self.maxArticlesPerScan = max(1, maxArticlesPerScan)
        self.maxArticlesPerTopicBatch = max(1, maxArticlesPerTopicBatch)
    }
}

public struct ProcessingEngineExecutor: ProcessingJobExecuting, @unchecked Sendable {
    public typealias AIProviderFactory = @Sendable () throws -> any AIProvider
    public typealias AISettingsProvider = @Sendable () throws -> ProcessingAISettings

    private let repositories: RSSRadarRepositories
    private let feedScanUseCase: FeedScanUseCase
    private let articleAnalyzer: (any ArticleAnalyzing)?
    private let topicAssigner: (any TopicAssigning)?
    private let topicBriefGenerationUseCase: TopicBriefGenerationUseCase?
    private let aiProviderFactory: AIProviderFactory?
    private let aiSettingsProvider: AISettingsProvider?

    public init(
        repositories: RSSRadarRepositories,
        loader: FeedDataLoader = URLSession.shared,
        articleAnalyzer: (any ArticleAnalyzing)? = nil,
        topicAssigner: (any TopicAssigning)? = nil,
        topicBriefGenerator: (any TopicBriefGenerating)? = nil,
        aiProviderFactory: AIProviderFactory? = nil,
        aiSettingsProvider: AISettingsProvider? = nil
    ) {
        self.repositories = repositories
        feedScanUseCase = FeedScanUseCase(repositories: repositories, loader: loader)
        self.articleAnalyzer = articleAnalyzer
        self.topicAssigner = topicAssigner
        topicBriefGenerationUseCase = topicBriefGenerator.map {
            TopicBriefGenerationUseCase(repositories: repositories, generator: $0)
        }
        self.aiProviderFactory = aiProviderFactory
        self.aiSettingsProvider = aiSettingsProvider
    }

    public func execute(job: ProcessingJob) async throws {
        switch job.jobType {
        case .fetchFeed:
            try await executeFetchFeed(job)
        case .analyzeArticle:
            try await executeAnalyzeArticle(job)
        case .assignTopics:
            try await executeAssignTopics(job)
        case .generateTopicBrief:
            try await executeGenerateTopicBrief(job)
        case .parseArticle, .retryFailedJob:
            throw ProcessingEngineError.unsupportedJobType(job.jobType)
        }
    }

    private func executeFetchFeed(_ job: ProcessingJob) async throws {
        guard let feedID = job.entityID else {
            throw ProcessingEngineError.missingEntityID(job.id)
        }
        let result = try await feedScanUseCase.scanFeed(id: feedID)
        try enqueueAnalysisJobsIfNeeded(for: result.articles)
    }

    private func executeAnalyzeArticle(_ job: ProcessingJob) async throws {
        guard let articleID = job.entityID else {
            throw ProcessingEngineError.missingEntityID(job.id)
        }
        let useCase = try makeArticleAnalysisUseCase()
        let analysis = try await useCase.analyzeArticle(id: articleID, modelName: modelName(from: job))
        try enqueueTopicAssignmentIfNeeded(articleID: analysis.articleID, modelName: analysis.modelName)
    }

    private func executeAssignTopics(_ job: ProcessingJob) async throws {
        let useCase = try makeTopicAssignmentUseCase()
        _ = try await useCase.assignTopics(
            articleIDs: articleIDs(from: job),
            modelName: modelName(from: job)
        )
    }

    private func executeGenerateTopicBrief(_ job: ProcessingJob) async throws {
        guard let topicBriefGenerationUseCase else {
            throw ProcessingEngineError.unsupportedJobType(job.jobType)
        }
        guard let briefType = TopicBriefType(rawValue: job.payload["brief_type"] ?? "") else {
            throw ProcessingEngineError.invalidPayload(job.id, "brief_type")
        }
        _ = try await topicBriefGenerationUseCase.generateIfNeeded(
            topicID: topicID(from: job),
            briefType: briefType,
            modelName: modelName(from: job)
        )
    }

    private func topicID(from job: ProcessingJob) throws -> String {
        let topicID = job.payload["topic_id"] ?? job.entityID ?? ""
        guard !topicID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ProcessingEngineError.missingEntityID(job.id)
        }
        return topicID
    }

    private func articleIDs(from job: ProcessingJob) -> [String] {
        (job.payload["article_ids"] ?? "")
            .split(separator: ",")
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private func modelName(from job: ProcessingJob) -> String {
        job.payload["model_name"] ?? ""
    }

    private func makeArticleAnalysisUseCase() throws -> ArticleAnalysisUseCase {
        if let articleAnalyzer {
            return ArticleAnalysisUseCase(repositories: repositories, analyzer: articleAnalyzer)
        }
        guard let aiProviderFactory else {
            throw ProcessingEngineError.unsupportedJobType(.analyzeArticle)
        }
        return ArticleAnalysisUseCase(
            repositories: repositories,
            analyzer: ArticleAnalysisService(provider: try aiProviderFactory())
        )
    }

    private func makeTopicAssignmentUseCase() throws -> TopicAssignmentUseCase {
        let batchSize = (try? aiSettingsProvider?().maxArticlesPerTopicBatch) ?? TopicAssignmentUseCase.defaultBatchSize
        if let topicAssigner {
            return TopicAssignmentUseCase(
                repositories: repositories,
                topicAssigner: topicAssigner,
                batchSize: batchSize
            )
        }
        guard let aiProviderFactory else {
            throw ProcessingEngineError.unsupportedJobType(.assignTopics)
        }
        return TopicAssignmentUseCase(
            repositories: repositories,
            topicAssigner: TopicAssignmentService(provider: try aiProviderFactory()),
            batchSize: batchSize
        )
    }

    private func enqueueAnalysisJobsIfNeeded(for articles: [Article]) throws {
        guard !articles.isEmpty, let aiSettingsProvider else {
            return
        }

        let settings = try aiSettingsProvider()
        let modelName = settings.modelName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !modelName.isEmpty else {
            try repositories.operationLogs.save(
                OperationLog(
                    level: .warning,
                    message: "Skipped article analysis queueing because AI model is not configured",
                    context: [:],
                    createdAt: Date()
                )
            )
            return
        }

        let existingJobs = try repositories.processingJobs.fetchAll()
        let existingAnalysisArticleIDs = Set(
            existingJobs
                .filter { $0.jobType == .analyzeArticle && $0.entityType == .article }
                .compactMap(\.entityID)
        )
        let articleIDs = articles
            .prefix(settings.maxArticlesPerScan)
            .filter { $0.status == .parsed }
            .filter { !existingAnalysisArticleIDs.contains($0.id) }
            .map(\.id)
        guard !articleIDs.isEmpty else {
            return
        }

        let now = Date()
        for articleID in articleIDs {
            let analysisJob = ProcessingJob(
                jobType: .analyzeArticle,
                entityType: .article,
                entityID: articleID,
                payload: ["model_name": modelName],
                scheduledAt: now,
                createdAt: now,
                updatedAt: now
            )
            try repositories.processingJobs.save(analysisJob)
            try repositories.operationLogs.save(
                OperationLog(
                    level: .info,
                    message: "Queued article analysis",
                    context: ["job_id": analysisJob.id, "article_id": articleID],
                    createdAt: now
                )
            )
        }
    }

    private func enqueueTopicAssignmentIfNeeded(articleID: String, modelName: String) throws {
        let existingJobs = try repositories.processingJobs.fetchAll()
        let hasExistingAssignmentJob = existingJobs.contains { job in
            guard job.jobType == .assignTopics else {
                return false
            }
            return articleIDs(from: job).contains(articleID)
        }
        guard !hasExistingAssignmentJob else {
            return
        }

        let now = Date()
        let assignmentJob = ProcessingJob(
            jobType: .assignTopics,
            entityType: .article,
            entityID: articleID,
            payload: [
                "article_ids": articleID,
                "model_name": modelName
            ],
            scheduledAt: now,
            createdAt: now,
            updatedAt: now
        )
        try repositories.processingJobs.save(assignmentJob)
        try repositories.operationLogs.save(
            OperationLog(
                level: .info,
                message: "Queued topic assignment",
                context: [
                    "job_id": assignmentJob.id,
                    "article_count": "1"
                ],
                createdAt: now
            )
        )
    }
}
