import Foundation
import RSSRadarCore
import RSSRadarPersistence

public final class UserCorrectionUseCase: @unchecked Sendable {
    private let repositories: RSSRadarRepositories

    public init(repositories: RSSRadarRepositories) {
        self.repositories = repositories
    }

    @discardableResult
    public func removeArticleFromTopic(
        topicID: String,
        articleID: String,
        correctedAt: Date = Date()
    ) throws -> UserCorrectionResult {
        let topic = try fetchTopic(id: topicID)
        let article = try fetchArticle(id: articleID)
        guard let relationship = try repositories.topicArticles.fetch(topicID: topic.id, articleID: article.id) else {
            throw UserCorrectionError.topicArticleNotFound(topicID: topic.id, articleID: article.id)
        }

        let correction = UserCorrection(
            correctionType: .removeArticleFromTopic,
            topicID: topic.id,
            articleID: article.id,
            oldValue: oldValue(for: relationship),
            newValue: nil,
            createdAt: correctedAt
        )

        try repositories.performTransaction { transaction in
            try transaction.topicArticles.delete(topicID: topic.id, articleID: article.id)
            try transaction.userCorrections.save(correction)
        }

        return UserCorrectionResult(correction: correction)
    }

    @discardableResult
    public func addArticleToExistingTopic(
        topicID: String,
        articleID: String,
        contributionType: TopicContributionType = .background,
        reason: String = "User correction",
        correctedAt: Date = Date()
    ) throws -> UserCorrectionResult {
        let topic = try fetchTopic(id: topicID)
        let article = try fetchArticle(id: articleID)
        let trimmedReason = reason.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedReason.isEmpty else {
            throw UserCorrectionError.emptyReason
        }

        let relationship = TopicArticle(
            topicID: topic.id,
            articleID: article.id,
            confidence: 1,
            reason: trimmedReason,
            contributionType: contributionType,
            createdAt: correctedAt
        )
        let correction = UserCorrection(
            correctionType: .addArticleToTopic,
            topicID: topic.id,
            articleID: article.id,
            oldValue: nil,
            newValue: newValue(for: relationship),
            createdAt: correctedAt
        )

        try repositories.performTransaction { transaction in
            try transaction.topicArticles.save(relationship)
            try transaction.userCorrections.save(correction)
        }

        return UserCorrectionResult(correction: correction, topicArticle: relationship)
    }

    @discardableResult
    public func createTopicFromArticle(
        articleID: String,
        name: String,
        description: String,
        entities: [String] = [],
        contributionType: TopicContributionType = .newEvent,
        reason: String = "User created topic from article",
        correctedAt: Date = Date()
    ) throws -> UserCorrectionResult {
        let article = try fetchArticle(id: articleID)
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedDescription = description.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedReason = reason.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            throw UserCorrectionError.emptyTopicName
        }
        guard !trimmedDescription.isEmpty else {
            throw UserCorrectionError.emptyTopicDescription
        }
        guard !trimmedReason.isEmpty else {
            throw UserCorrectionError.emptyReason
        }

        let topic = Topic(
            name: trimmedName,
            description: trimmedDescription,
            originalAIName: nil,
            originalAIDescription: nil,
            entities: normalizedEntities(entities),
            status: .active,
            importanceScore: article.importanceScore,
            createdAt: correctedAt,
            updatedAt: correctedAt
        )
        let relationship = TopicArticle(
            topicID: topic.id,
            articleID: article.id,
            confidence: 1,
            reason: trimmedReason,
            contributionType: contributionType,
            createdAt: correctedAt
        )
        let correction = UserCorrection(
            correctionType: .createTopicFromArticle,
            topicID: topic.id,
            articleID: article.id,
            oldValue: nil,
            newValue: newValue(for: topic, relationship: relationship),
            createdAt: correctedAt
        )

        try repositories.performTransaction { transaction in
            try transaction.topics.save(topic)
            try transaction.topicArticles.save(relationship)
            try transaction.userCorrections.save(correction)
        }

        return UserCorrectionResult(correction: correction, topic: topic, topicArticle: relationship)
    }

    private func fetchTopic(id topicID: String) throws -> Topic {
        guard let topic = try repositories.topics.fetch(id: topicID) else {
            throw UserCorrectionError.topicNotFound(topicID)
        }
        return topic
    }

    private func fetchArticle(id articleID: String) throws -> Article {
        guard let article = try repositories.articles.fetch(id: articleID) else {
            throw UserCorrectionError.articleNotFound(articleID)
        }
        return article
    }

    private func oldValue(for relationship: TopicArticle) -> String {
        "topic_id=\(relationship.topicID);article_id=\(relationship.articleID);confidence=\(relationship.confidence)"
    }

    private func newValue(for relationship: TopicArticle) -> String {
        "topic_id=\(relationship.topicID);article_id=\(relationship.articleID);contribution_type="
            + "\(relationship.contributionType.rawValue)"
    }

    private func newValue(for topic: Topic, relationship: TopicArticle) -> String {
        "topic_id=\(topic.id);topic_name=\(topic.name);article_id=\(relationship.articleID)"
    }

    private func normalizedEntities(_ entities: [String]) -> [String] {
        entities.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
    }
}

public struct UserCorrectionResult: Equatable, Sendable {
    public static let topicBriefRegenerationPrompt = "TopicBrief can be regenerated after this correction."

    public var correction: UserCorrection
    public var topic: Topic?
    public var topicArticle: TopicArticle?
    public var shouldPromptTopicBriefRegeneration: Bool
    public var promptMessage: String

    public init(
        correction: UserCorrection,
        topic: Topic? = nil,
        topicArticle: TopicArticle? = nil,
        shouldPromptTopicBriefRegeneration: Bool = true,
        promptMessage: String = UserCorrectionResult.topicBriefRegenerationPrompt
    ) {
        self.correction = correction
        self.topic = topic
        self.topicArticle = topicArticle
        self.shouldPromptTopicBriefRegeneration = shouldPromptTopicBriefRegeneration
        self.promptMessage = promptMessage
    }
}

public enum UserCorrectionError: Error, Equatable, LocalizedError {
    case topicNotFound(String)
    case articleNotFound(String)
    case topicArticleNotFound(topicID: String, articleID: String)
    case emptyTopicName
    case emptyTopicDescription
    case emptyReason

    public var errorDescription: String? {
        switch self {
        case let .topicNotFound(topicID):
            "Topic was not found for user correction: \(topicID)."
        case let .articleNotFound(articleID):
            "Article was not found for user correction: \(articleID)."
        case let .topicArticleNotFound(topicID, articleID):
            "Article \(articleID) is not linked to topic \(topicID)."
        case .emptyTopicName:
            "User-created topic name cannot be empty."
        case .emptyTopicDescription:
            "User-created topic description cannot be empty."
        case .emptyReason:
            "User correction reason cannot be empty."
        }
    }
}
