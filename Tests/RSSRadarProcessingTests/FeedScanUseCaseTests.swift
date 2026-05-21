import Foundation
import RSSRadarCore
import RSSRadarFeeds
import RSSRadarPersistence
import RSSRadarProcessing
import XCTest

final class FeedScanUseCaseTests: XCTestCase {
    func testScanFeedPersistsArticlesAndFeedProgressThroughRepository() async throws {
        let repositories = try makeRepositories()
        let feed = Feed(
            id: "feed-1",
            title: "Persisted Feed",
            url: URL(string: "https://persisted.example.com/feed.xml")!,
            createdAt: fixedDate,
            updatedAt: fixedDate
        )
        try repositories.feeds.save(feed)

        let useCase = FeedScanUseCase(
            repositories: repositories,
            loader: FixtureFeedDataLoader(fixtureName: "many-articles-rss")
        )

        let result = try await useCase.scanFeed(id: feed.id, now: scanDate)
        let persistedArticles = try repositories.articles.fetch(feedID: feed.id)
        let persistedFeed = try XCTUnwrap(repositories.feeds.fetch(id: feed.id))

        XCTAssertEqual(result.articles.count, 20)
        XCTAssertEqual(persistedArticles.count, 20)
        XCTAssertEqual(persistedArticles.first?.title, "Article 22")
        XCTAssertEqual(persistedFeed.lastCheckedAt, scanDate)
        XCTAssertEqual(persistedFeed.lastSuccessAt, scanDate)
        XCTAssertEqual(persistedFeed.lastProcessedArticlePublishedAt, articleDate(day: 22))
        XCTAssertEqual(persistedFeed.status, .active)
    }

    func testScanFeedThrowsForMissingFeed() async throws {
        let repositories = try makeRepositories()
        let useCase = FeedScanUseCase(repositories: repositories)

        do {
            _ = try await useCase.scanFeed(id: "missing", now: scanDate)
            XCTFail("Expected missing feed to throw")
        } catch FeedScanUseCaseError.feedNotFound("missing") {
            XCTAssertTrue(try repositories.articles.fetchAll().isEmpty)
        }
    }

    func testScanFeedDeduplicatesCanonicalURLAndSimilarTitleWithinSameFeed() async throws {
        let repositories = try makeRepositories()
        let feed = Feed(
            id: "feed-1",
            title: "Persisted Feed",
            url: URL(string: "https://persisted.example.com/feed.xml")!,
            createdAt: fixedDate,
            updatedAt: fixedDate
        )
        try repositories.feeds.save(feed)
        try repositories.articles.save(
            Article(
                feedID: feed.id,
                title: "Already saved URL",
                url: URL(string: "https://example.com/story?id=42")!,
                publishedAt: articleDate(day: 18),
                createdAt: fixedDate,
                updatedAt: fixedDate
            )
        )

        let useCase = FeedScanUseCase(
            repositories: repositories,
            loader: FixtureFeedDataLoader(fixtureName: "dedup-rss")
        )

        let result = try await useCase.scanFeed(id: feed.id, now: scanDate)
        let persistedArticles = try repositories.articles.fetch(feedID: feed.id)
        let persistedFeed = try XCTUnwrap(repositories.feeds.fetch(id: feed.id))

        XCTAssertEqual(result.articles.map(\.title), [
            "Apple launches iPhone 17 in China",
            "Microsoft reports Azure growth"
        ])
        XCTAssertEqual(persistedArticles.count, 3)
        XCTAssertTrue(persistedArticles.contains { $0.title == "Already saved URL" })
        XCTAssertFalse(persistedArticles.contains { $0.title == "Original URL duplicate" })
        XCTAssertFalse(persistedArticles.contains { $0.title == "Apple launches the iPhone 17 in China" })
        XCTAssertEqual(persistedFeed.lastProcessedArticlePublishedAt, articleDate(day: 21))
    }

    func testScanFeedKeepsSimilarTitleWhenExistingArticleBelongsToDifferentFeed() async throws {
        let repositories = try makeRepositories()
        let sourceFeed = Feed(
            id: "feed-1",
            title: "Source Feed",
            url: URL(string: "https://source.example.com/feed.xml")!,
            createdAt: fixedDate,
            updatedAt: fixedDate
        )
        let otherFeed = Feed(
            id: "feed-2",
            title: "Other Feed",
            url: URL(string: "https://other.example.com/feed.xml")!,
            createdAt: fixedDate,
            updatedAt: fixedDate
        )
        try repositories.feeds.save(sourceFeed)
        try repositories.feeds.save(otherFeed)
        try repositories.articles.save(
            Article(
                feedID: otherFeed.id,
                title: "Apple launches the iPhone 17 in China",
                url: URL(string: "https://other.example.com/iphone-17")!,
                publishedAt: articleDate(day: 18),
                createdAt: fixedDate,
                updatedAt: fixedDate
            )
        )

        let useCase = FeedScanUseCase(
            repositories: repositories,
            loader: FixtureFeedDataLoader(fixtureName: "dedup-rss")
        )

        let result = try await useCase.scanFeed(id: sourceFeed.id, now: scanDate)

        XCTAssertTrue(result.articles.contains { $0.title == "Apple launches iPhone 17 in China" })
    }
}

private extension FeedScanUseCaseTests {
    func makeRepositories() throws -> RSSRadarRepositories {
        let directoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("RSSRadarFeedScanUseCaseTests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let databaseURL = directoryURL.appendingPathComponent("rssradar.sqlite")
        let database = try RSSRadarDatabase(path: databaseURL.path)
        try database.migrate()
        return RSSRadarRepositories(database: database)
    }
}

private struct FixtureFeedDataLoader: FeedDataLoader {
    var fixtureName: String

    func data(from url: URL) async throws -> (Data, URLResponse) {
        let fixtureURL = Bundle.module.url(forResource: fixtureName, withExtension: "xml")!
        let data = try Data(contentsOf: fixtureURL)
        let response = HTTPURLResponse(
            url: url,
            statusCode: 200,
            httpVersion: nil,
            headerFields: nil
        )!
        return (data, response)
    }
}

private func articleDate(day: Int) -> Date {
    ISO8601DateFormatter().date(from: "2026-05-\(String(format: "%02d", day))T10:00:00Z")!
}

private let fixedDate = Date(timeIntervalSince1970: 1_700_000_000)
private let scanDate = Date(timeIntervalSince1970: 1_778_889_600)
