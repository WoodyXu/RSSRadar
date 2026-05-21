import Foundation

public enum ArticleContentType: String, Codable, CaseIterable, Sendable {
    case news
    case analysis
    case opinion
    case tutorial
    case announcement
}

public struct ArticleAnalysis: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var articleID: String
    public var summary: String
    public var keyPoints: [String]
    public var entities: [String]
    public var claims: [String]
    public var events: [String]
    public var metrics: [String]
    public var contentType: ArticleContentType
    public var possibleTopics: [String]
    public var importanceScore: Double
    public var modelName: String
    public var generatedAt: Date

    public enum CodingKeys: String, CodingKey {
        case id
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
        case modelName = "model_name"
        case generatedAt = "generated_at"
    }

    public init(
        id: String = DomainID.make(),
        articleID: String,
        summary: String,
        keyPoints: [String] = [],
        entities: [String] = [],
        claims: [String] = [],
        events: [String] = [],
        metrics: [String] = [],
        contentType: ArticleContentType,
        possibleTopics: [String] = [],
        importanceScore: Double,
        modelName: String,
        generatedAt: Date = Date()
    ) {
        self.id = id
        self.articleID = articleID
        self.summary = summary
        self.keyPoints = keyPoints
        self.entities = entities
        self.claims = claims
        self.events = events
        self.metrics = metrics
        self.contentType = contentType
        self.possibleTopics = possibleTopics
        self.importanceScore = importanceScore
        self.modelName = modelName
        self.generatedAt = generatedAt
    }
}
