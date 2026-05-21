import Foundation

public enum FeedStatus: String, Codable, CaseIterable, Sendable {
    case active
    case error
    case paused
    case noArticles = "no_articles"
}

public struct Feed: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var title: String
    public var url: URL
    public var siteURL: URL?
    public var status: FeedStatus
    public var lastCheckedAt: Date?
    public var lastSuccessAt: Date?
    public var lastProcessedArticlePublishedAt: Date?
    public var errorMessage: String?
    public var createdAt: Date
    public var updatedAt: Date

    public enum CodingKeys: String, CodingKey {
        case id
        case title
        case url
        case siteURL = "site_url"
        case status
        case lastCheckedAt = "last_checked_at"
        case lastSuccessAt = "last_success_at"
        case lastProcessedArticlePublishedAt = "last_processed_article_published_at"
        case errorMessage = "error_message"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    public init(
        id: String = DomainID.make(),
        title: String,
        url: URL,
        siteURL: URL? = nil,
        status: FeedStatus = .active,
        lastCheckedAt: Date? = nil,
        lastSuccessAt: Date? = nil,
        lastProcessedArticlePublishedAt: Date? = nil,
        errorMessage: String? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.title = title
        self.url = url
        self.siteURL = siteURL
        self.status = status
        self.lastCheckedAt = lastCheckedAt
        self.lastSuccessAt = lastSuccessAt
        self.lastProcessedArticlePublishedAt = lastProcessedArticlePublishedAt
        self.errorMessage = errorMessage
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}
