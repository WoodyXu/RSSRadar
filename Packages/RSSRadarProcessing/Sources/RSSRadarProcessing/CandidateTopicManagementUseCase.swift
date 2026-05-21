import Foundation
import RSSRadarCore
import RSSRadarPersistence

public final class CandidateTopicManagementUseCase: @unchecked Sendable {
    private let repositories: RSSRadarRepositories

    public init(repositories: RSSRadarRepositories) {
        self.repositories = repositories
    }

    public func listCandidates() throws -> [CandidateTopicPreview] {
        let candidates = try repositories.topics.fetch(status: .candidate)
        return try candidates.map { try makePreview(for: $0) }
    }

    public func previewCandidate(id topicID: String) throws -> CandidateTopicPreview {
        guard let topic = try repositories.topics.fetch(id: topicID) else {
            throw CandidateTopicManagementError.topicNotFound(topicID)
        }
        guard topic.status == .candidate else {
            throw CandidateTopicManagementError.topicIsNotCandidate(topicID)
        }
        return try makePreview(for: topic)
    }

    @discardableResult
    public func trackCandidate(id topicID: String, updatedAt: Date = Date()) throws -> Topic {
        try updateCandidateStatus(id: topicID, status: .active, updatedAt: updatedAt)
    }

    @discardableResult
    public func ignoreCandidate(id topicID: String, updatedAt: Date = Date()) throws -> Topic {
        try updateCandidateStatus(id: topicID, status: .ignored, updatedAt: updatedAt)
    }

    @discardableResult
    public func renameCandidate(id topicID: String, name: String, updatedAt: Date = Date()) throws -> Topic {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            throw CandidateTopicManagementError.emptyName
        }

        return try updateCandidate(id: topicID) { topic in
            if let duplicate = try repositories.topics.fetch(status: .candidate, normalizedName: trimmedName),
               duplicate.id != topic.id {
                throw CandidateTopicManagementError.duplicateCandidateName(trimmedName)
            }
            topic.name = trimmedName
            topic.updatedAt = updatedAt
        }
    }

    @discardableResult
    public func updateCandidateDescription(
        id topicID: String,
        description: String,
        updatedAt: Date = Date()
    ) throws -> Topic {
        let trimmedDescription = description.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedDescription.isEmpty else {
            throw CandidateTopicManagementError.emptyDescription
        }

        return try updateCandidate(id: topicID) { topic in
            topic.description = trimmedDescription
            topic.updatedAt = updatedAt
        }
    }

    private func updateCandidateStatus(
        id topicID: String,
        status: TopicStatus,
        updatedAt: Date
    ) throws -> Topic {
        try updateCandidate(id: topicID) { topic in
            topic.status = status
            topic.updatedAt = updatedAt
        }
    }

    private func updateCandidate(
        id topicID: String,
        mutate: (inout Topic) throws -> Void
    ) throws -> Topic {
        guard var topic = try repositories.topics.fetch(id: topicID) else {
            throw CandidateTopicManagementError.topicNotFound(topicID)
        }
        guard topic.status == .candidate else {
            throw CandidateTopicManagementError.topicIsNotCandidate(topicID)
        }
        try mutate(&topic)
        try repositories.topics.save(topic)
        return topic
    }

    private func makePreview(for topic: Topic) throws -> CandidateTopicPreview {
        let relationships = try repositories.topicArticles.fetchForTopic(id: topic.id)
        let articles = try relationships.compactMap { relationship in
            try repositories.articles.fetch(id: relationship.articleID)
        }
        let previewBrief = try repositories.topicBriefs.fetch(topicID: topic.id, briefType: .preview)

        return CandidateTopicPreview(
            topic: topic,
            previewBrief: previewBrief,
            articleCount: relationships.count,
            relatedArticles: articles
        )
    }
}

public struct CandidateTopicPreview: Equatable, Sendable {
    public var topic: Topic
    public var previewBrief: TopicBrief?
    public var articleCount: Int
    public var relatedArticles: [Article]

    public init(
        topic: Topic,
        previewBrief: TopicBrief?,
        articleCount: Int,
        relatedArticles: [Article]
    ) {
        self.topic = topic
        self.previewBrief = previewBrief
        self.articleCount = articleCount
        self.relatedArticles = relatedArticles
    }
}

public enum CandidateTopicManagementError: Error, Equatable, LocalizedError {
    case topicNotFound(String)
    case topicIsNotCandidate(String)
    case emptyName
    case emptyDescription
    case duplicateCandidateName(String)

    public var errorDescription: String? {
        switch self {
        case let .topicNotFound(topicID):
            "Candidate topic was not found: \(topicID)."
        case let .topicIsNotCandidate(topicID):
            "Topic is not a candidate topic: \(topicID)."
        case .emptyName:
            "Candidate topic name cannot be empty."
        case .emptyDescription:
            "Candidate topic description cannot be empty."
        case let .duplicateCandidateName(name):
            "A candidate topic with the same name already exists: \(name)."
        }
    }
}
