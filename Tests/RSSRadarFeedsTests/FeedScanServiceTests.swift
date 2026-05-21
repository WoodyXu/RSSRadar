import Foundation
import RSSRadarCore
import XCTest
@testable import RSSRadarFeeds

final class FeedScanServiceTests: XCTestCase {
    func testNewFeedPersistsAtMostTwentyNewestArticles() async throws {
        let feed = makeFeed()
        let service = FeedScanService(loader: FixtureFeedDataLoader(fixtureName: "many-articles-rss"))

        let result = await service.scan(feed: feed, now: fixedDate)

        XCTAssertEqual(result.articles.count, 20)
        XCTAssertEqual(result.articles.first?.title, "Article 22")
        XCTAssertEqual(result.articles.last?.title, "Article 03")
        XCTAssertFalse(result.articles.contains { $0.title == "Article without date" })
        XCTAssertEqual(result.feed.status, .active)
        XCTAssertEqual(result.feed.lastCheckedAt, fixedDate)
        XCTAssertEqual(result.feed.lastSuccessAt, fixedDate)
        XCTAssertEqual(result.feed.lastProcessedArticlePublishedAt, articleDate(day: 22))
        XCTAssertNil(result.feed.errorMessage)
    }

    func testExistingFeedOnlyKeepsArticlesAfterLastProcessedDate() async throws {
        let feed = makeFeed(lastProcessedAt: articleDate(day: 20))
        let service = FeedScanService(loader: FixtureFeedDataLoader(fixtureName: "many-articles-rss"))

        let result = await service.scan(feed: feed, now: fixedDate)

        XCTAssertEqual(result.articles.map(\.title), ["Article 22", "Article 21"])
        XCTAssertEqual(result.feed.lastProcessedArticlePublishedAt, articleDate(day: 22))
    }

    func testExistingFeedWithoutNewArticlesKeepsActiveStatusAndProgress() async throws {
        let feed = makeFeed(lastProcessedAt: articleDate(day: 22))
        let service = FeedScanService(loader: FixtureFeedDataLoader(fixtureName: "many-articles-rss"))

        let result = await service.scan(feed: feed, now: fixedDate)

        XCTAssertTrue(result.articles.isEmpty)
        XCTAssertEqual(result.feed.status, .active)
        XCTAssertEqual(result.feed.lastProcessedArticlePublishedAt, articleDate(day: 22))
    }

    func testArticlesWithoutPublishedDateDoNotAdvanceProgress() async throws {
        let feed = makeFeed()
        let service = FeedScanService(loader: FixtureFeedDataLoader(fixtureName: "undated-rss"))

        let result = await service.scan(feed: feed, now: fixedDate)

        XCTAssertEqual(result.articles.count, 1)
        XCTAssertNil(result.articles.first?.publishedAt)
        XCTAssertNil(result.feed.lastProcessedArticlePublishedAt)
        XCTAssertEqual(result.feed.status, .active)
    }

    func testHTTPFailureMarksFeedErrorWithoutArticles() async throws {
        let previousSuccess = Date(timeIntervalSince1970: 1_700_000_000)
        let feed = makeFeed(lastProcessedAt: articleDate(day: 10), lastSuccessAt: previousSuccess)
        let service = FeedScanService(loader: FixtureFeedDataLoader(fixtureName: "many-articles-rss", statusCode: 500))

        let result = await service.scan(feed: feed, now: fixedDate)

        XCTAssertTrue(result.articles.isEmpty)
        XCTAssertEqual(result.feed.status, .error)
        XCTAssertEqual(result.feed.lastCheckedAt, fixedDate)
        XCTAssertEqual(result.feed.lastSuccessAt, previousSuccess)
        XCTAssertEqual(result.feed.lastProcessedArticlePublishedAt, articleDate(day: 10))
        XCTAssertEqual(result.feed.errorMessage, "Feed request failed with HTTP status 500")
    }
}

private extension FeedScanServiceTests {
    func makeFeed(lastProcessedAt: Date? = nil, lastSuccessAt: Date? = nil) -> Feed {
        Feed(
            id: "feed-1",
            title: "Fixture Feed",
            url: URL(string: "https://example.com/feed.xml")!,
            lastSuccessAt: lastSuccessAt,
            lastProcessedArticlePublishedAt: lastProcessedAt,
            createdAt: Date(timeIntervalSince1970: 1_600_000_000),
            updatedAt: Date(timeIntervalSince1970: 1_600_000_000)
        )
    }
}

private struct FixtureFeedDataLoader: FeedDataLoader {
    var fixtureName: String
    var statusCode: Int = 200

    func data(from url: URL) async throws -> (Data, URLResponse) {
        let fixtureURL = Bundle.module.url(forResource: fixtureName, withExtension: "xml")!
        let data = try Data(contentsOf: fixtureURL)
        let response = HTTPURLResponse(
            url: url,
            statusCode: statusCode,
            httpVersion: nil,
            headerFields: nil
        )!
        return (data, response)
    }
}

private func articleDate(day: Int) -> Date {
    ISO8601DateFormatter().date(from: "2026-05-\(String(format: "%02d", day))T10:00:00Z")!
}

private let fixedDate = Date(timeIntervalSince1970: 1_778_889_600)
