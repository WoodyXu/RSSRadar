import Foundation
import RSSRadarAI
import RSSRadarCore
import RSSRadarFeeds
import RSSRadarPersistence

public struct ProcessingEngineExecutor: ProcessingJobExecuting, @unchecked Sendable {
    private let feedScanUseCase: FeedScanUseCase
    private let articleAnalysisUseCase: ArticleAnalysisUseCase?
    private let topicAssignmentUseCase: TopicAssignmentUseCase?
    private let topicBriefGenerationUseCase: TopicBriefGenerationUseCase?

    public init(
        repositories: RSSRadarRepositories,
        loader: FeedDataLoader = URLSession.shared,
        articleAnalyzer: (any ArticleAnalyzing)? = nil,
        topicAssigner: (any TopicAssigning)? = nil,
        topicBriefGenerator: (any TopicBriefGenerating)? = nil
    ) {
        feedScanUseCase = FeedScanUseCase(repositories: repositories, loader: loader)
        articleAnalysisUseCase = articleAnalyzer.map {
            ArticleAnalysisUseCase(repositories: repositories, analyzer: $0)
        }
        topicAssignmentUseCase = topicAssigner.map {
            TopicAssignmentUseCase(repositories: repositories, topicAssigner: $0)
        }
        topicBriefGenerationUseCase = topicBriefGenerator.map {
            TopicBriefGenerationUseCase(repositories: repositories, generator: $0)
        }
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
        _ = try await feedScanUseCase.scanFeed(id: feedID)
    }

    private func executeAnalyzeArticle(_ job: ProcessingJob) async throws {
        guard let articleID = job.entityID else {
            throw ProcessingEngineError.missingEntityID(job.id)
        }
        guard let articleAnalysisUseCase else {
            throw ProcessingEngineError.unsupportedJobType(job.jobType)
        }
        _ = try await articleAnalysisUseCase.analyzeArticle(id: articleID, modelName: modelName(from: job))
    }

    private func executeAssignTopics(_ job: ProcessingJob) async throws {
        guard let topicAssignmentUseCase else {
            throw ProcessingEngineError.unsupportedJobType(job.jobType)
        }
        _ = try await topicAssignmentUseCase.assignTopics(
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
}
