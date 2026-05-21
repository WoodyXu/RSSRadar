import Foundation
import RSSRadarCore
import XCTest
@testable import RSSRadarFeeds

final class ArticleDeduplicatorTests: XCTestCase {
    func testCanonicalURLLowercasesHostRemovesFragmentAndTrackingParameters() throws {
        let url = try XCTUnwrap(URL(string: "HTTPS://Example.COM/story?b=2&utm_source=news&a=1&fbclid=abc#comments"))

        let canonicalURL = ArticleDeduplicator.canonicalURLString(for: url)

        XCTAssertEqual(canonicalURL, "https://example.com/story?a=1&b=2")
    }

    func testDeduplicateKeepsOnlyFirstArticleForEquivalentCanonicalURL() throws {
        let duplicate = makeArticle(
            title: "Original Title",
            url: "https://example.com/story?utm_campaign=feed&id=42#section"
        )
        let original = makeArticle(title: "Original Title", url: "https://example.com/story?id=42")

        let result = ArticleDeduplicator().deduplicate([duplicate], existingArticles: [original])

        XCTAssertTrue(result.isEmpty)
    }

    func testDeduplicateDropsSimilarTitlesWithinSameFeed() throws {
        let first = makeArticle(title: "Apple launches iPhone 17 in China", url: "https://example.com/a")
        let similar = makeArticle(title: "Apple launches the iPhone 17 in China", url: "https://example.com/b")
        let distinct = makeArticle(title: "Microsoft reports Azure growth", url: "https://example.com/c")

        let result = ArticleDeduplicator().deduplicate([first, similar, distinct])

        XCTAssertEqual(result.map(\.title), ["Apple launches iPhone 17 in China", "Microsoft reports Azure growth"])
    }

    func testDeduplicateKeepsSimilarTitlesAcrossDifferentFeeds() throws {
        let first = makeArticle(
            feedID: "feed-1",
            title: "Apple launches iPhone 17 in China",
            url: "https://example.com/a"
        )
        let second = makeArticle(
            feedID: "feed-2",
            title: "Apple launches the iPhone 17 in China",
            url: "https://other.example.com/a"
        )

        let result = ArticleDeduplicator().deduplicate([first, second])

        XCTAssertEqual(result.map(\.feedID), ["feed-1", "feed-2"])
    }
}

private func makeArticle(feedID: String = "feed-1", title: String, url: String) -> Article {
    Article(
        feedID: feedID,
        title: title,
        url: URL(string: url)!,
        createdAt: Date(timeIntervalSince1970: 1_700_000_000),
        updatedAt: Date(timeIntervalSince1970: 1_700_000_000)
    )
}
