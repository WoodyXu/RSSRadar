import Foundation
import RSSRadarCore
import XCTest
@testable import RSSRadarFeeds

final class ManualFeedAddServiceTests: XCTestCase {
    func testAddFeedSavesActiveFeedFromRSSFixture() async throws {
        let store = CapturingFeedStore()
        let service = ManualFeedAddService(
            loader: FixtureFeedDataLoader(fixtureName: "valid-rss"),
            store: store
        )

        let feed = try await service.addFeed(urlString: " https://example.com/feed.xml ", now: fixedDate)

        XCTAssertEqual(feed.title, "RSSRadar Test Feed")
        XCTAssertEqual(feed.url.absoluteString, "https://example.com/feed.xml")
        XCTAssertEqual(feed.siteURL?.absoluteString, "https://example.com")
        XCTAssertEqual(feed.status, .active)
        XCTAssertEqual(feed.lastCheckedAt, fixedDate)
        XCTAssertEqual(feed.lastSuccessAt, fixedDate)
        XCTAssertNil(feed.errorMessage)
        XCTAssertEqual(store.savedFeeds, [feed])
    }

    func testAddFeedSavesNoArticlesStatusForEmptyRSSFixture() async throws {
        let store = CapturingFeedStore()
        let service = ManualFeedAddService(
            loader: FixtureFeedDataLoader(fixtureName: "empty-rss"),
            store: store
        )

        let feed = try await service.addFeed(urlString: "https://empty.example.com/feed.xml", now: fixedDate)

        XCTAssertEqual(feed.title, "Empty RSSRadar Feed")
        XCTAssertEqual(feed.siteURL?.absoluteString, "https://empty.example.com")
        XCTAssertEqual(feed.status, .noArticles)
        XCTAssertEqual(feed.lastSuccessAt, fixedDate)
        XCTAssertNil(feed.errorMessage)
        XCTAssertEqual(store.savedFeeds, [feed])
    }

    func testAddFeedSavesErrorFeedForInvalidRSSFixture() async throws {
        let store = CapturingFeedStore()
        let service = ManualFeedAddService(
            loader: FixtureFeedDataLoader(fixtureName: "invalid-rss"),
            store: store
        )

        let feed = try await service.addFeed(urlString: "https://broken.example.com/feed.xml", now: fixedDate)

        XCTAssertEqual(feed.title, "broken.example.com")
        XCTAssertEqual(feed.status, .error)
        XCTAssertEqual(feed.lastCheckedAt, fixedDate)
        XCTAssertNil(feed.lastSuccessAt)
        XCTAssertNotNil(feed.errorMessage)
        XCTAssertEqual(store.savedFeeds, [feed])
    }

    func testAddFeedSavesErrorFeedForHTTPFailure() async throws {
        let store = CapturingFeedStore()
        let service = ManualFeedAddService(
            loader: FixtureFeedDataLoader(fixtureName: "valid-rss", statusCode: 404),
            store: store
        )

        let feed = try await service.addFeed(urlString: "https://missing.example.com/feed.xml", now: fixedDate)

        XCTAssertEqual(feed.status, .error)
        XCTAssertEqual(feed.errorMessage, "Feed request failed with HTTP status 404")
        XCTAssertEqual(store.savedFeeds, [feed])
    }

    func testAddFeedRejectsInvalidURLBeforeSaving() async throws {
        let store = CapturingFeedStore()
        let service = ManualFeedAddService(
            loader: FixtureFeedDataLoader(fixtureName: "valid-rss"),
            store: store
        )

        do {
            _ = try await service.addFeed(urlString: "not a url", now: fixedDate)
            XCTFail("Expected invalid URL to throw")
        } catch ManualFeedAddError.invalidURL {
            XCTAssertTrue(store.savedFeeds.isEmpty)
        }
    }
}

private final class CapturingFeedStore: FeedStore {
    private(set) var savedFeeds: [Feed] = []

    func save(_ feed: Feed) throws {
        savedFeeds.append(feed)
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

private let fixedDate = Date(timeIntervalSince1970: 1_778_889_600)
