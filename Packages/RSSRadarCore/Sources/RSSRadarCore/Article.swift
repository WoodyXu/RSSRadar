import Foundation

public enum ArticleContentSource: String, Codable, CaseIterable, Sendable {
    case rssFullContent = "rss_full_content"
    case webExtracted = "web_extracted"
    case rssSummary = "rss_summary"
}

public enum ArticleStatus: String, Codable, CaseIterable, Sendable {
    case fetched
    case parsed
    case analyzed
    case assigned
    case ignored
    case failed
}

public struct Article: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var feedID: String
    public var title: String
    public var url: URL
    public var author: String?
    public var publishedAt: Date?
    public var rssSummary: String?
    public var content: String?
    public var contentSource: ArticleContentSource?
    public var status: ArticleStatus
    public var importanceScore: Double?
    public var errorMessage: String?
    public var createdAt: Date
    public var updatedAt: Date

    public enum CodingKeys: String, CodingKey {
        case id
        case feedID = "feed_id"
        case title
        case url
        case author
        case publishedAt = "published_at"
        case rssSummary = "rss_summary"
        case content
        case contentSource = "content_source"
        case status
        case importanceScore = "importance_score"
        case errorMessage = "error_message"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    public init(
        id: String = DomainID.make(),
        feedID: String,
        title: String,
        url: URL,
        author: String? = nil,
        publishedAt: Date? = nil,
        rssSummary: String? = nil,
        content: String? = nil,
        contentSource: ArticleContentSource? = nil,
        status: ArticleStatus = .fetched,
        importanceScore: Double? = nil,
        errorMessage: String? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.feedID = feedID
        self.title = title
        self.url = url
        self.author = author
        self.publishedAt = publishedAt
        self.rssSummary = rssSummary
        self.content = content
        self.contentSource = contentSource
        self.status = status
        self.importanceScore = importanceScore
        self.errorMessage = errorMessage
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}
