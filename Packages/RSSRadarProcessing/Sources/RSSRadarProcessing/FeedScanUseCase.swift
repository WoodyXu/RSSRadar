import Foundation
import RSSRadarCore
import RSSRadarFeeds
import RSSRadarPersistence

public final class FeedScanUseCase {
    private let repositories: RSSRadarRepositories
    private let service: FeedScanService

    public init(repositories: RSSRadarRepositories, loader: FeedDataLoader = URLSession.shared) {
        self.repositories = repositories
        service = FeedScanService(loader: loader)
    }

    @discardableResult
    public func scanFeed(id feedID: String, now: Date = Date()) async throws -> FeedScanResult {
        guard let feed = try repositories.feeds.fetch(id: feedID) else {
            throw FeedScanUseCaseError.feedNotFound(feedID)
        }

        let result = await service.scan(feed: feed, now: now)
        let deduplicatedArticles = try deduplicate(result.articles)
        let feedAfterDeduplication = feedAfterDeduplication(
            originalFeed: feed,
            scannedFeed: result.feed,
            articles: deduplicatedArticles
        )
        try repositories.performTransaction { transaction in
            for article in deduplicatedArticles {
                try transaction.articles.save(article)
            }
            try transaction.feeds.save(feedAfterDeduplication)
        }
        return FeedScanResult(feed: feedAfterDeduplication, articles: deduplicatedArticles)
    }

    private func deduplicate(_ articles: [Article]) throws -> [Article] {
        guard !articles.isEmpty else {
            return []
        }

        let existingArticles = try repositories.articles.fetchAll()
        let deduplicator = ArticleDeduplicator()
        return deduplicator.deduplicate(articles, existingArticles: existingArticles)
    }

    private func feedAfterDeduplication(originalFeed: Feed, scannedFeed: Feed, articles: [Article]) -> Feed {
        guard scannedFeed.status == .active else {
            return scannedFeed
        }

        return Feed(
            id: scannedFeed.id,
            title: scannedFeed.title,
            url: scannedFeed.url,
            siteURL: scannedFeed.siteURL,
            status: scannedFeed.status,
            lastCheckedAt: scannedFeed.lastCheckedAt,
            lastSuccessAt: scannedFeed.lastSuccessAt,
            lastProcessedArticlePublishedAt: articles.compactMap(\.publishedAt).max()
                ?? originalFeed.lastProcessedArticlePublishedAt,
            errorMessage: scannedFeed.errorMessage,
            createdAt: scannedFeed.createdAt,
            updatedAt: scannedFeed.updatedAt
        )
    }
}

public enum FeedScanUseCaseError: Error, Equatable, LocalizedError {
    case feedNotFound(String)

    public var errorDescription: String? {
        switch self {
        case let .feedNotFound(feedID):
            "Feed not found: \(feedID)"
        }
    }
}
