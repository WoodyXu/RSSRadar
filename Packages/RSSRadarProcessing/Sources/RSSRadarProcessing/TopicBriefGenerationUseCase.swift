import Foundation
import RSSRadarAI
import RSSRadarCore
import RSSRadarPersistence

public final class TopicBriefGenerationUseCase: @unchecked Sendable {
    private let repositories: RSSRadarRepositories
    private let generator: any TopicBriefGenerating

    public init(repositories: RSSRadarRepositories, generator: any TopicBriefGenerating) {
        self.repositories = repositories
        self.generator = generator
    }

    @discardableResult
    public func generateIfNeeded(
        topicID: String,
        briefType: TopicBriefType,
        modelName: String,
        generatedAt: Date = Date()
    ) async throws -> TopicBriefGenerationUseCaseResult {
        let topic = try fetchTopic(id: topicID)
        try validate(topic: topic, briefType: briefType)

        if let cachedBrief = try repositories.topicBriefs.fetch(topicID: topic.id, briefType: briefType) {
            return TopicBriefGenerationUseCaseResult(brief: cachedBrief, didGenerate: false)
        }

        try validateModelName(modelName)

        let sourceArticles = try fetchSourceArticles(topicID: topic.id)
        guard !sourceArticles.isEmpty else {
            throw TopicBriefGenerationUseCaseError.noAnalyzedRelatedArticles(topic.id)
        }

        let brief = try await generator.generateBrief(
            topic: topic,
            relatedArticles: sourceArticles,
            briefType: briefType,
            modelName: modelName,
            generatedAt: generatedAt
        )
        try repositories.topicBriefs.save(brief)
        try repositories.operationLogs.save(
            OperationLog(
                level: .info,
                message: "Generated TopicBrief",
                context: [
                    "topic_id": topic.id,
                    "brief_type": briefType.rawValue
                ],
                createdAt: generatedAt
            )
        )

        return TopicBriefGenerationUseCaseResult(brief: brief, didGenerate: true)
    }

    @discardableResult
    public func regenerate(
        topicID: String,
        briefType: TopicBriefType,
        modelName: String,
        generatedAt: Date = Date()
    ) async throws -> TopicBriefGenerationUseCaseResult {
        let topic = try fetchTopic(id: topicID)
        try validate(topic: topic, briefType: briefType)
        try validateModelName(modelName)

        let sourceArticles = try fetchSourceArticles(topicID: topic.id)
        guard !sourceArticles.isEmpty else {
            throw TopicBriefGenerationUseCaseError.noAnalyzedRelatedArticles(topic.id)
        }

        do {
            let brief = try await generator.generateBrief(
                topic: topic,
                relatedArticles: sourceArticles,
                briefType: briefType,
                modelName: modelName,
                generatedAt: generatedAt
            )
            try repositories.topicBriefs.save(brief)
            try repositories.operationLogs.save(
                OperationLog(
                    level: .info,
                    message: "Regenerated TopicBrief",
                    context: [
                        "topic_id": topic.id,
                        "brief_type": briefType.rawValue
                    ],
                    createdAt: generatedAt
                )
            )

            return TopicBriefGenerationUseCaseResult(brief: brief, didGenerate: true)
        } catch {
            try repositories.operationLogs.save(
                OperationLog(
                    level: .error,
                    message: "Failed to regenerate TopicBrief",
                    context: [
                        "topic_id": topic.id,
                        "brief_type": briefType.rawValue
                    ],
                    createdAt: generatedAt
                )
            )
            throw error
        }
    }

    private func fetchTopic(id topicID: String) throws -> Topic {
        guard let topic = try repositories.topics.fetch(id: topicID) else {
            throw TopicBriefGenerationUseCaseError.topicNotFound(topicID)
        }
        return topic
    }

    private func validate(topic: Topic, briefType: TopicBriefType) throws {
        switch (topic.status, briefType) {
        case (.active, .full), (.candidate, .preview):
            return
        case (.candidate, .full):
            throw TopicBriefGenerationUseCaseError.candidateRequiresPreview(topic.id)
        case (.active, .preview):
            throw TopicBriefGenerationUseCaseError.activeRequiresFull(topic.id)
        case (.ignored, _), (.archived, _):
            throw TopicBriefGenerationUseCaseError.unsupportedTopicStatus(topic.status)
        }
    }

    private func validateModelName(_ modelName: String) throws {
        guard !modelName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw TopicBriefGenerationUseCaseError.missingModelName
        }
    }

    private func fetchSourceArticles(topicID: String) throws -> [TopicBriefSourceArticle] {
        let relationships = try repositories.topicArticles.fetchForTopic(id: topicID)
        var sourceArticles: [TopicBriefSourceArticle] = []

        for relationship in relationships {
            guard let article = try repositories.articles.fetch(id: relationship.articleID),
                  let analysis = try repositories.articleAnalyses.fetch(articleID: article.id) else {
                continue
            }
            let feedTitle = try repositories.feeds.fetch(id: article.feedID)?.title ?? "Unknown source"
            sourceArticles.append(
                TopicBriefSourceArticle(
                    article: article,
                    analysis: analysis,
                    feedTitle: feedTitle,
                    contributionType: relationship.contributionType
                )
            )
        }

        return sourceArticles
    }
}

public struct TopicBriefGenerationUseCaseResult: Equatable, Sendable {
    public var brief: TopicBrief
    public var didGenerate: Bool

    public init(brief: TopicBrief, didGenerate: Bool) {
        self.brief = brief
        self.didGenerate = didGenerate
    }
}

public enum TopicBriefGenerationUseCaseError: Error, Equatable, LocalizedError {
    case topicNotFound(String)
    case missingModelName
    case activeRequiresFull(String)
    case candidateRequiresPreview(String)
    case unsupportedTopicStatus(TopicStatus)
    case noAnalyzedRelatedArticles(String)

    public var errorDescription: String? {
        switch self {
        case let .topicNotFound(topicID):
            "Topic was not found for TopicBrief generation: \(topicID)."
        case .missingModelName:
            "AI model name is not configured for TopicBrief generation."
        case let .activeRequiresFull(topicID):
            "Active topic requires a full TopicBrief: \(topicID)."
        case let .candidateRequiresPreview(topicID):
            "Candidate topic requires a preview TopicBrief: \(topicID)."
        case let .unsupportedTopicStatus(status):
            "Topic status is not supported for TopicBrief generation: \(status.rawValue)."
        case let .noAnalyzedRelatedArticles(topicID):
            "Topic has no analyzed related articles for TopicBrief generation: \(topicID)."
        }
    }
}
