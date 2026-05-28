import Foundation
import RSSRadarAI
import RSSRadarCore
import RSSRadarPersistence

public final class TopicAssignmentUseCase: @unchecked Sendable {
    public static let defaultBatchSize = 50

    private let repositories: RSSRadarRepositories
    private let topicAssigner: any TopicAssigning
    private let batchSize: Int

    public init(
        repositories: RSSRadarRepositories,
        topicAssigner: any TopicAssigning,
        batchSize: Int = TopicAssignmentUseCase.defaultBatchSize
    ) {
        self.repositories = repositories
        self.topicAssigner = topicAssigner
        self.batchSize = max(1, batchSize)
    }

    @discardableResult
    public func assignTopics(
        articleIDs: [String],
        modelName: String,
        assignedAt: Date = Date()
    ) async throws -> TopicAssignmentUseCaseResult {
        let normalizedArticleIDs = articleIDs.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard !normalizedArticleIDs.isEmpty else {
            throw TopicAssignmentUseCaseError.emptyArticleIDs
        }

        // 如果本批次文章数量不足 batchSize，则全选；否则只选前 batchSize 篇。
        let selectedArticleIDs = Array(normalizedArticleIDs.prefix(batchSize))

        guard !modelName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw TopicAssignmentUseCaseError.missingModelName
        }

        let analyses = try selectedArticleIDs.map { articleID in
            guard let analysis = try repositories.articleAnalyses.fetch(articleID: articleID) else {
                throw TopicAssignmentUseCaseError.analysisNotFound(articleID)
            }
            return analysis
        }
        let existingTopics = try fetchAssignableTopics()
        let assignmentResult = try await topicAssigner.assignTopics(
            analyses: analyses,
            existingTopics: existingTopics,
            modelName: modelName,
            assignedAt: assignedAt
        )

        return try persist(
            assignmentResult: assignmentResult,
            existingTopics: existingTopics,
            assignedAt: assignedAt
        )
    }

    private func fetchAssignableTopics() throws -> [Topic] {
        let activeTopics = try repositories.topics.fetch(status: .active)
        let candidateTopics = try repositories.topics.fetch(status: .candidate)
        return activeTopics + candidateTopics
    }

    private func persist(
        assignmentResult: TopicAssignmentResult,
        existingTopics: [Topic],
        assignedAt: Date
    ) throws -> TopicAssignmentUseCaseResult {
        var context = TopicAssignmentPersistenceContext(existingTopics: existingTopics)
        var savedRelationships: [TopicArticle] = []

        try repositories.performTransaction { transaction in
            for assignment in assignmentResult.assignments {
                let topic = try resolveTopic(
                    for: assignment,
                    transaction: transaction,
                    assignedAt: assignedAt,
                    context: &context
                )

                let relationship = TopicArticle(
                    topicID: topic.id,
                    articleID: assignment.articleID,
                    confidence: assignment.confidence,
                    reason: assignment.reason,
                    contributionType: assignment.contributionType,
                    createdAt: assignedAt
                )
                try transaction.topicArticles.save(relationship)
                savedRelationships.append(relationship)
                try queueFullBriefGenerationIfNeeded(
                    topic: topic,
                    modelName: assignmentResult.modelName,
                    scheduledAt: assignedAt,
                    transaction: transaction,
                    context: &context
                )

                if var article = try transaction.articles.fetch(id: assignment.articleID) {
                    article.status = .assigned
                    article.errorMessage = nil
                    article.updatedAt = assignedAt
                    try transaction.articles.save(article)
                }
            }
        }

        return TopicAssignmentUseCaseResult(
            topicsCreated: context.savedTopics,
            topicArticles: savedRelationships,
            activeTopicIDsForBriefGeneration: context.activeTopicIDsQueuedForBriefs,
            topicBriefJobsQueued: context.topicBriefJobsQueued,
            modelName: assignmentResult.modelName
        )
    }

    private func queueFullBriefGenerationIfNeeded(
        topic: Topic,
        modelName: String,
        scheduledAt: Date,
        transaction: RSSRadarRepositoryTransaction,
        context: inout TopicAssignmentPersistenceContext
    ) throws {
        guard topic.status == .active else {
            return
        }
        guard context.activeTopicIDsQueuedForBriefs.insert(topic.id).inserted else {
            return
        }

        let job = ProcessingJob(
            jobType: .generateTopicBrief,
            entityType: .topic,
            entityID: topic.id,
            payload: [
                "topic_id": topic.id,
                "brief_type": TopicBriefType.full.rawValue,
                "model_name": modelName
            ],
            scheduledAt: scheduledAt,
            createdAt: scheduledAt,
            updatedAt: scheduledAt
        )
        try transaction.processingJobs.save(job)
        try transaction.operationLogs.save(
            OperationLog(
                level: .info,
                message: "Queued full TopicBrief generation",
                context: ["job_id": job.id, "topic_id": topic.id],
                createdAt: scheduledAt
            )
        )
        context.topicBriefJobsQueued.append(job)
    }

    private func resolveTopic(
        for assignment: TopicAssignment,
        transaction: RSSRadarRepositoryTransaction,
        assignedAt: Date,
        context: inout TopicAssignmentPersistenceContext
    ) throws -> Topic {
        if let topicID = assignment.topicID, let existingTopic = context.topicsByID[topicID] {
            return existingTopic
        }

        guard let newTopic = assignment.newTopic else {
            throw TopicAssignmentUseCaseError.assignmentMissingTopic(assignment.articleID)
        }

        let normalizedName = Self.normalizeName(newTopic.name)
        if let alreadyCreated = context.newTopicsByNormalizedName[normalizedName] {
            return alreadyCreated
        }
        if let existingAssignableTopic = context.assignableTopicsByNormalizedName[normalizedName] {
            context.newTopicsByNormalizedName[normalizedName] = existingAssignableTopic
            return existingAssignableTopic
        }
        if let persistedTopic = try fetchPersistedAssignableTopic(
            normalizedName: normalizedName,
            transaction: transaction
        ) {
            context.topicsByID[persistedTopic.id] = persistedTopic
            context.assignableTopicsByNormalizedName[normalizedName] = persistedTopic
            context.newTopicsByNormalizedName[normalizedName] = persistedTopic
            return persistedTopic
        }

        let topic = Topic(
            name: newTopic.name,
            description: newTopic.description,
            originalAIName: newTopic.name,
            originalAIDescription: newTopic.description,
            entities: newTopic.entities,
            status: .candidate,
            importanceScore: newTopic.importanceScore ?? assignment.confidence,
            createdAt: assignedAt,
            updatedAt: assignedAt
        )
        try transaction.topics.save(topic)
        context.topicsByID[topic.id] = topic
        context.newTopicsByNormalizedName[normalizedName] = topic
        context.savedTopics.append(topic)
        return topic
    }

    fileprivate static func normalizeName(_ name: String) -> String {
        name
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")
    }

    private func fetchPersistedAssignableTopic(
        normalizedName: String,
        transaction: RSSRadarRepositoryTransaction
    ) throws -> Topic? {
        if let activeTopic = try transaction.topics.fetch(status: .active, normalizedName: normalizedName) {
            return activeTopic
        }
        if let candidateTopic = try transaction.topics.fetch(status: .candidate, normalizedName: normalizedName) {
            return candidateTopic
        }
        return nil
    }
}

private struct TopicAssignmentPersistenceContext {
    var topicsByID: [String: Topic]
    var assignableTopicsByNormalizedName: [String: Topic]
    var newTopicsByNormalizedName: [String: Topic]
    var savedTopics: [Topic]
    var activeTopicIDsQueuedForBriefs: Set<String>
    var topicBriefJobsQueued: [ProcessingJob]

    init(existingTopics: [Topic]) {
        topicsByID = Dictionary(uniqueKeysWithValues: existingTopics.map { ($0.id, $0) })
        assignableTopicsByNormalizedName = Dictionary(
            existingTopics.map { (TopicAssignmentUseCase.normalizeName($0.name), $0) },
            uniquingKeysWith: { first, _ in first }
        )
        newTopicsByNormalizedName = [:]
        savedTopics = []
        activeTopicIDsQueuedForBriefs = []
        topicBriefJobsQueued = []
    }
}

public struct TopicAssignmentUseCaseResult: Equatable, Sendable {
    public var topicsCreated: [Topic]
    public var topicArticles: [TopicArticle]
    public var activeTopicIDsForBriefGeneration: Set<String>
    public var topicBriefJobsQueued: [ProcessingJob]
    public var modelName: String

    public init(
        topicsCreated: [Topic],
        topicArticles: [TopicArticle],
        activeTopicIDsForBriefGeneration: Set<String> = [],
        topicBriefJobsQueued: [ProcessingJob] = [],
        modelName: String
    ) {
        self.topicsCreated = topicsCreated
        self.topicArticles = topicArticles
        self.activeTopicIDsForBriefGeneration = activeTopicIDsForBriefGeneration
        self.topicBriefJobsQueued = topicBriefJobsQueued
        self.modelName = modelName
    }
}

public enum TopicAssignmentUseCaseError: Error, Equatable, LocalizedError {
    case emptyArticleIDs
    case batchTooLarge(Int, max: Int)
    case missingModelName
    case analysisNotFound(String)
    case assignmentMissingTopic(String)

    public var errorDescription: String? {
        switch self {
        case .emptyArticleIDs:
            "Topic assignment requires at least one article analysis."
        case let .batchTooLarge(count, max):
            "Topic assignment batch has \(count) articles, exceeding the limit of \(max)."
        case .missingModelName:
            "AI model name is not configured for topic assignment."
        case let .analysisNotFound(articleID):
            "Article analysis was not found for topic assignment: \(articleID)."
        case let .assignmentMissingTopic(articleID):
            "Topic assignment did not include a topic target for article: \(articleID)."
        }
    }
}
