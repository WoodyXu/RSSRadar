import Foundation

public enum UserCorrectionType: String, Codable, CaseIterable, Sendable {
    case removeArticleFromTopic = "remove_article_from_topic"
    case addArticleToTopic = "add_article_to_topic"
    case createTopicFromArticle = "create_topic_from_article"
}

public struct UserCorrection: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var correctionType: UserCorrectionType
    public var topicID: String?
    public var articleID: String?
    public var oldValue: String?
    public var newValue: String?
    public var createdAt: Date

    public enum CodingKeys: String, CodingKey {
        case id
        case correctionType = "correction_type"
        case topicID = "topic_id"
        case articleID = "article_id"
        case oldValue = "old_value"
        case newValue = "new_value"
        case createdAt = "created_at"
    }

    public init(
        id: String = DomainID.make(),
        correctionType: UserCorrectionType,
        topicID: String? = nil,
        articleID: String? = nil,
        oldValue: String? = nil,
        newValue: String? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.correctionType = correctionType
        self.topicID = topicID
        self.articleID = articleID
        self.oldValue = oldValue
        self.newValue = newValue
        self.createdAt = createdAt
    }
}
