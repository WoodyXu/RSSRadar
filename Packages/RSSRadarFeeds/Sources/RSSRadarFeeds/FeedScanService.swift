import Foundation
import RSSRadarCore

public struct FeedScanResult: Equatable {
    public var feed: Feed
    public var articles: [Article]

    public init(feed: Feed, articles: [Article]) {
        self.feed = feed
        self.articles = articles
    }
}

public final class FeedScanService {
    public static let newFeedArticleLimit = 20

    private let loader: FeedDataLoader
    private let contentExtractor: ArticleContentExtractionService

    public init(loader: FeedDataLoader = URLSession.shared) {
        self.loader = loader
        contentExtractor = ArticleContentExtractionService(loader: loader)
    }

    public func scan(feed: Feed, now: Date = Date()) async -> FeedScanResult {
        do {
            let data = try await loadFeedData(from: feed.url)
            let parsedArticles = try FeedArticleParser().parse(data)
                .map { $0.article(feedID: feed.id, now: now) }
            let selectedArticles = Self.selectedArticles(
                parsedArticles,
                lastProcessedAt: feed.lastProcessedArticlePublishedAt
            )
            let extractedArticles = await extractContent(from: selectedArticles, now: now)
            let updatedFeed = Self.successFeed(
                from: feed,
                articles: extractedArticles,
                parsedArticleCount: parsedArticles.count,
                now: now
            )
            return FeedScanResult(feed: updatedFeed, articles: extractedArticles)
        } catch {
            return FeedScanResult(feed: Self.errorFeed(from: feed, error: error, now: now), articles: [])
        }
    }

    private func loadFeedData(from url: URL) async throws -> Data {
        let (data, response) = try await loader.data(from: url)
        if let httpResponse = response as? HTTPURLResponse, !(200..<300).contains(httpResponse.statusCode) {
            throw FeedMetadataParserError.httpStatus(httpResponse.statusCode)
        }
        return data
    }

    private func extractContent(from articles: [Article], now: Date) async -> [Article] {
        var extractedArticles: [Article] = []
        extractedArticles.reserveCapacity(articles.count)

        for article in articles {
            extractedArticles.append(await contentExtractor.extractContent(for: article, now: now))
        }

        return extractedArticles
    }

    private static func selectedArticles(_ articles: [Article], lastProcessedAt: Date?) -> [Article] {
        if let lastProcessedAt {
            return sortedByPublishedAt(articles)
                .filter { article in
                    guard let publishedAt = article.publishedAt else {
                        return false
                    }
                    return publishedAt > lastProcessedAt
                }
        }

        return Array(sortedByPublishedAt(articles).prefix(newFeedArticleLimit))
    }

    private static func sortedByPublishedAt(_ articles: [Article]) -> [Article] {
        articles.sorted { lhs, rhs in
            switch (lhs.publishedAt, rhs.publishedAt) {
            case let (lhsDate?, rhsDate?):
                return lhsDate > rhsDate
            case (_?, nil):
                return true
            case (nil, _?):
                return false
            case (nil, nil):
                return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
            }
        }
    }

    private static func successFeed(
        from feed: Feed,
        articles: [Article],
        parsedArticleCount: Int,
        now: Date
    ) -> Feed {
        let latestPublishedAt = articles.compactMap(\.publishedAt).max()
        return Feed(
            id: feed.id,
            title: feed.title,
            url: feed.url,
            siteURL: feed.siteURL,
            status: parsedArticleCount == 0 ? .noArticles : .active,
            lastCheckedAt: now,
            lastSuccessAt: now,
            lastProcessedArticlePublishedAt: latestPublishedAt ?? feed.lastProcessedArticlePublishedAt,
            errorMessage: nil,
            createdAt: feed.createdAt,
            updatedAt: now
        )
    }

    private static func errorFeed(from feed: Feed, error: Error, now: Date) -> Feed {
        Feed(
            id: feed.id,
            title: feed.title,
            url: feed.url,
            siteURL: feed.siteURL,
            status: .error,
            lastCheckedAt: now,
            lastSuccessAt: feed.lastSuccessAt,
            lastProcessedArticlePublishedAt: feed.lastProcessedArticlePublishedAt,
            errorMessage: safeErrorMessage(from: error),
            createdAt: feed.createdAt,
            updatedAt: now
        )
    }

    private static func safeErrorMessage(from error: Error) -> String {
        if let localizedError = error as? LocalizedError, let description = localizedError.errorDescription {
            return description
        }
        return String(describing: error)
    }
}

private extension FeedArticleCandidate {
    func article(feedID: String, now: Date) -> Article {
        Article(
            feedID: feedID,
            title: title,
            url: url,
            author: author,
            publishedAt: publishedAt,
            rssSummary: rssSummary,
            content: content,
            contentSource: content == nil ? nil : .rssFullContent,
            status: .fetched,
            createdAt: now,
            updatedAt: now
        )
    }
}
