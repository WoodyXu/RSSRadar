import Foundation
import RSSRadarCore

public protocol TopicAssigning: Sendable {
    func assignTopics(
        analyses: [ArticleAnalysis],
        existingTopics: [Topic],
        modelName: String,
        assignedAt: Date
    ) async throws -> TopicAssignmentResult
}

public struct TopicAssignmentResult: Equatable, Sendable {
    public var assignments: [TopicAssignment]
    public var modelName: String

    public init(assignments: [TopicAssignment], modelName: String) {
        self.assignments = assignments
        self.modelName = modelName
    }
}

public struct TopicAssignment: Equatable, Sendable {
    public var articleID: String
    public var topicID: String?
    public var newTopic: NewTopicCandidate?
    public var confidence: Double
    public var reason: String
    public var contributionType: TopicContributionType

    public init(
        articleID: String,
        topicID: String? = nil,
        newTopic: NewTopicCandidate? = nil,
        confidence: Double,
        reason: String,
        contributionType: TopicContributionType
    ) {
        self.articleID = articleID
        self.topicID = topicID
        self.newTopic = newTopic
        self.confidence = confidence
        self.reason = reason
        self.contributionType = contributionType
    }
}

public struct NewTopicCandidate: Equatable, Sendable {
    public var name: String
    public var description: String
    public var entities: [String]
    public var importanceScore: Double?

    public init(
        name: String,
        description: String,
        entities: [String] = [],
        importanceScore: Double? = nil
    ) {
        self.name = name
        self.description = description
        self.entities = entities
        self.importanceScore = importanceScore
    }
}

public final class TopicAssignmentService: TopicAssigning, @unchecked Sendable {
    private let provider: any AIProvider
    private let promptStore: PromptTemplateStore
    private let jsonDecoder: JSONDecoder
    private let jsonEncoder: JSONEncoder

    public init(
        provider: any AIProvider,
        promptStore: PromptTemplateStore = PromptTemplateStore()
    ) {
        self.provider = provider
        self.promptStore = promptStore
        jsonDecoder = JSONDecoder()
        jsonEncoder = JSONEncoder()
        jsonEncoder.outputFormatting = [.sortedKeys]
    }

    public func assignTopics(
        analyses: [ArticleAnalysis],
        existingTopics: [Topic],
        modelName: String,
        assignedAt: Date = Date()
    ) async throws -> TopicAssignmentResult {
        let prompt = try promptStore.load(.topicAssignment).render(
            variables: [
                "article_analyses_json": analysesPromptJSON(analyses),
                "existing_topics_json": topicsPromptJSON(existingTopics)
            ]
        )
        let response = try await provider.complete(
            AIProviderRequest(
                model: modelName,
                messages: [AIMessage(role: .user, content: prompt)],
                temperature: 0.1,
                maxTokens: 2_400
            )
        )
        let assignments = try decodeOutput(
            from: response.text,
            analyses: analyses,
            existingTopics: existingTopics
        )
        let model = response.model?.trimmingCharacters(in: .whitespacesAndNewlines)

        return TopicAssignmentResult(
            assignments: assignments,
            modelName: model?.isEmpty == false ? model! : modelName
        )
    }

    private func analysesPromptJSON(_ analyses: [ArticleAnalysis]) -> String {
        let payload = analyses.map(ArticleAnalysisPromptPayload.init(analysis:))
        return encodedJSONString(payload)
    }

    private func topicsPromptJSON(_ topics: [Topic]) -> String {
        let payload = topics.map(TopicPromptPayload.init(topic:))
        return encodedJSONString(payload)
    }

    private func encodedJSONString<T: Encodable>(_ value: T) -> String {
        guard let data = try? jsonEncoder.encode(value),
              let text = String(data: data, encoding: .utf8) else {
            return "[]"
        }
        return text
    }

    private func decodeOutput(
        from text: String,
        analyses: [ArticleAnalysis],
        existingTopics: [Topic]
    ) throws -> [TopicAssignment] {
        guard let data = text.data(using: .utf8) else {
            throw TopicAssignmentValidationError.invalidUTF8
        }

        do {
            let output = try jsonDecoder.decode(TopicAssignmentOutput.self, from: data)
            try output.validate(
                validArticleIDs: Set(analyses.map(\.articleID)),
                validTopicIDs: Set(existingTopics.map(\.id))
            )
            return output.normalizedAssignments()
        } catch let error as TopicAssignmentValidationError {
            throw error
        } catch {
            throw TopicAssignmentValidationError.invalidJSON(String(describing: error))
        }
    }
}

public enum TopicAssignmentValidationError: Error, Equatable, LocalizedError {
    case invalidUTF8
    case invalidJSON(String)
    case emptyAssignments
    case unknownArticleID(String)
    case unknownTopicID(String)
    case missingTopicTarget(String)
    case emptyField(String)
    case confidenceOutOfRange(Double)
    case broadTopicName(String)
    case importanceScoreOutOfRange(Double)

    public var errorDescription: String? {
        switch self {
        case .invalidUTF8:
            "AI topic assignment output is not valid UTF-8."
        case let .invalidJSON(message):
            "AI topic assignment output is not valid JSON: \(message)"
        case .emptyAssignments:
            "AI topic assignment output has no assignments."
        case let .unknownArticleID(articleID):
            "AI topic assignment references an unknown article: \(articleID)."
        case let .unknownTopicID(topicID):
            "AI topic assignment references an unknown topic: \(topicID)."
        case let .missingTopicTarget(articleID):
            "AI topic assignment has neither an existing topic nor a new topic for article: \(articleID)."
        case let .emptyField(name):
            "AI topic assignment output has an empty required field: \(name)."
        case let .confidenceOutOfRange(confidence):
            "AI topic assignment confidence is outside 0...1: \(confidence)."
        case let .broadTopicName(name):
            "AI topic assignment proposed a broad topic name: \(name)."
        case let .importanceScoreOutOfRange(score):
            "AI topic assignment topic importance score is outside 0...1: \(score)."
        }
    }
}

private struct TopicAssignmentOutput: Decodable {
    var assignments: [TopicAssignmentOutputItem]

    func validate(validArticleIDs: Set<String>, validTopicIDs: Set<String>) throws {
        guard !assignments.isEmpty else {
            throw TopicAssignmentValidationError.emptyAssignments
        }

        for assignment in assignments {
            try assignment.validate(validArticleIDs: validArticleIDs, validTopicIDs: validTopicIDs)
        }
    }

    func normalizedAssignments() -> [TopicAssignment] {
        assignments.map { $0.normalized() }
    }
}

private struct TopicAssignmentOutputItem: Decodable {
    var articleID: String
    var topicID: String?
    var newTopicName: String?
    var newTopicDescription: String?
    var newTopicEntities: [String]?
    var newTopicImportanceScore: Double?
    var confidence: Double
    var reason: String
    var contributionType: TopicContributionType

    enum CodingKeys: String, CodingKey {
        case articleID = "article_id"
        case topicID = "topic_id"
        case newTopicName = "new_topic_name"
        case newTopicDescription = "new_topic_description"
        case newTopicEntities = "new_topic_entities"
        case newTopicImportanceScore = "new_topic_importance_score"
        case confidence
        case reason
        case contributionType = "contribution_type"
    }

    func validate(validArticleIDs: Set<String>, validTopicIDs: Set<String>) throws {
        let trimmedArticleID = articleID.trimmed()
        guard !trimmedArticleID.isEmpty else {
            throw TopicAssignmentValidationError.emptyField("article_id")
        }
        guard validArticleIDs.contains(trimmedArticleID) else {
            throw TopicAssignmentValidationError.unknownArticleID(trimmedArticleID)
        }
        if confidence < 0 || confidence > 1 {
            throw TopicAssignmentValidationError.confidenceOutOfRange(confidence)
        }
        if reason.trimmed().isEmpty {
            throw TopicAssignmentValidationError.emptyField("reason")
        }

        let trimmedTopicID = topicID?.trimmedNonEmpty()
        let trimmedNewTopicName = newTopicName?.trimmedNonEmpty()
        let trimmedNewTopicDescription = newTopicDescription?.trimmedNonEmpty()

        if let trimmedTopicID, !validTopicIDs.contains(trimmedTopicID) {
            throw TopicAssignmentValidationError.unknownTopicID(trimmedTopicID)
        }

        if trimmedTopicID == nil {
            guard let trimmedNewTopicName, let trimmedNewTopicDescription else {
                throw TopicAssignmentValidationError.missingTopicTarget(trimmedArticleID)
            }
            try TopicSpecificityValidator.validate(name: trimmedNewTopicName)
            if trimmedNewTopicDescription.isEmpty {
                throw TopicAssignmentValidationError.emptyField("new_topic_description")
            }
        } else if let trimmedNewTopicName {
            try TopicSpecificityValidator.validate(name: trimmedNewTopicName)
        }

        if let score = newTopicImportanceScore, score < 0 || score > 1 {
            throw TopicAssignmentValidationError.importanceScoreOutOfRange(score)
        }
    }

    func normalized() -> TopicAssignment {
        let newTopic: NewTopicCandidate?
        if let newTopicName = newTopicName?.trimmedNonEmpty(),
           let newTopicDescription = newTopicDescription?.trimmedNonEmpty() {
            newTopic = NewTopicCandidate(
                name: newTopicName,
                description: newTopicDescription,
                entities: (newTopicEntities ?? []).trimmedNonEmptyValues(),
                importanceScore: newTopicImportanceScore
            )
        } else {
            newTopic = nil
        }

        return TopicAssignment(
            articleID: articleID.trimmed(),
            topicID: topicID?.trimmedNonEmpty(),
            newTopic: newTopic,
            confidence: confidence,
            reason: reason.trimmed(),
            contributionType: contributionType
        )
    }
}

private enum TopicSpecificityValidator {
    private static let broadNames: Set<String> = [
        "ai",
        "artificial intelligence",
        "stocks",
        "stock",
        "programming",
        "macro economy",
        "macroeconomy",
        "electric vehicles",
        "ev",
        "technology",
        "tech",
        "白酒",
        "股票",
        "新能源车",
        "编程",
        "宏观经济",
        "人工智能"
    ]

    static func validate(name: String) throws {
        let normalized = name.trimmed().lowercased()
        if broadNames.contains(normalized) {
            throw TopicAssignmentValidationError.broadTopicName(name)
        }

        let asciiWordCount = normalized
            .split { !$0.isLetter && !$0.isNumber }
            .count
        if normalized.allSatisfy(\.isASCII), asciiWordCount <= 1 {
            throw TopicAssignmentValidationError.broadTopicName(name)
        }
    }
}

private struct ArticleAnalysisPromptPayload: Encodable {
    var articleID: String
    var summary: String
    var keyPoints: [String]
    var entities: [String]
    var claims: [String]
    var events: [String]
    var metrics: [String]
    var contentType: String
    var possibleTopics: [String]
    var importanceScore: Double

    enum CodingKeys: String, CodingKey {
        case articleID = "article_id"
        case summary
        case keyPoints = "key_points"
        case entities
        case claims
        case events
        case metrics
        case contentType = "content_type"
        case possibleTopics = "possible_topics"
        case importanceScore = "importance_score"
    }

    init(analysis: ArticleAnalysis) {
        articleID = analysis.articleID
        summary = analysis.summary
        keyPoints = analysis.keyPoints
        entities = analysis.entities
        claims = analysis.claims
        events = analysis.events
        metrics = analysis.metrics
        contentType = analysis.contentType.rawValue
        possibleTopics = analysis.possibleTopics
        importanceScore = analysis.importanceScore
    }
}

private struct TopicPromptPayload: Encodable {
    var topicID: String
    var name: String
    var description: String
    var entities: [String]
    var status: String
    var importanceScore: Double?

    enum CodingKeys: String, CodingKey {
        case topicID = "topic_id"
        case name
        case description
        case entities
        case status
        case importanceScore = "importance_score"
    }

    init(topic: Topic) {
        topicID = topic.id
        name = topic.name
        description = topic.description
        entities = topic.entities
        status = topic.status.rawValue
        importanceScore = topic.importanceScore
    }
}

private extension String {
    func trimmed() -> String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func trimmedNonEmpty() -> String? {
        let value = trimmed()
        return value.isEmpty ? nil : value
    }
}

private extension Array where Element == String {
    func trimmedNonEmptyValues() -> [String] {
        map { $0.trimmed() }.filter { !$0.isEmpty }
    }
}
