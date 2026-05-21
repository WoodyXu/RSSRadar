import Foundation

public enum TopicStatus: String, Codable, CaseIterable, Sendable {
    case candidate
    case active
    case ignored
    case archived
}

public enum TopicContributionType: String, Codable, CaseIterable, Sendable {
    case newEvent = "new_event"
    case newOpinion = "new_opinion"
    case newData = "new_data"
    case background
}

public struct Topic: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var name: String
    public var description: String
    public var originalAIName: String?
    public var originalAIDescription: String?
    public var entities: [String]
    public var status: TopicStatus
    public var importanceScore: Double?
    public var createdAt: Date
    public var updatedAt: Date

    public enum CodingKeys: String, CodingKey {
        case id
        case name
        case description
        case originalAIName = "original_ai_name"
        case originalAIDescription = "original_ai_description"
        case entities
        case status
        case importanceScore = "importance_score"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    public init(
        id: String = DomainID.make(),
        name: String,
        description: String,
        originalAIName: String? = nil,
        originalAIDescription: String? = nil,
        entities: [String] = [],
        status: TopicStatus = .candidate,
        importanceScore: Double? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.description = description
        self.originalAIName = originalAIName
        self.originalAIDescription = originalAIDescription
        self.entities = entities
        self.status = status
        self.importanceScore = importanceScore
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

public struct TopicArticle: Codable, Equatable, Sendable {
    public var topicID: String
    public var articleID: String
    public var confidence: Double
    public var reason: String
    public var contributionType: TopicContributionType
    public var createdAt: Date

    public enum CodingKeys: String, CodingKey {
        case topicID = "topic_id"
        case articleID = "article_id"
        case confidence
        case reason
        case contributionType = "contribution_type"
        case createdAt = "created_at"
    }

    public init(
        topicID: String,
        articleID: String,
        confidence: Double,
        reason: String,
        contributionType: TopicContributionType,
        createdAt: Date = Date()
    ) {
        self.topicID = topicID
        self.articleID = articleID
        self.confidence = confidence
        self.reason = reason
        self.contributionType = contributionType
        self.createdAt = createdAt
    }
}
