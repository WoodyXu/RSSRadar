import Foundation
import RSSRadarCore
import XCTest
@testable import RSSRadarFeeds

final class ArticleContentExtractionServiceTests: XCTestCase {
    func testRSSFullContentTakesPriorityOverWebExtractionAndSummary() async {
        let article = makeArticle(
            rssSummary: "RSS summary should not be used.",
            content: "<p>RSS full content has the complete article body.</p>"
        )
        let service = ArticleContentExtractionService(loader: FailingContentLoader())

        let extractedArticle = await service.extractContent(for: article, now: fixedDate)

        XCTAssertEqual(extractedArticle.contentSource, .rssFullContent)
        XCTAssertEqual(extractedArticle.content, "RSS full content has the complete article body.")
        XCTAssertEqual(extractedArticle.status, .parsed)
        XCTAssertEqual(extractedArticle.updatedAt, fixedDate)
    }

    func testExtractableHTMLUsesWebExtractedContent() async {
        let article = makeArticle(rssSummary: "Short RSS summary.")
        let service = ArticleContentExtractionService(
            loader: FixtureContentLoader(fixtureName: "extractable-article", statusCode: 200)
        )

        let extractedArticle = await service.extractContent(for: article, now: fixedDate)

        XCTAssertEqual(extractedArticle.contentSource, .webExtracted)
        XCTAssertEqual(extractedArticle.status, .parsed)
        XCTAssertTrue(extractedArticle.content?.contains("RSSRadar extracts the durable article body") == true)
        XCTAssertFalse(extractedArticle.content?.contains("Navigation link") == true)
        XCTAssertFalse(extractedArticle.content?.contains("Footer text") == true)
    }

    func testUnextractableHTMLFallsBackToRSSSummary() async {
        let article = makeArticle(rssSummary: "RSS summary remains available when webpage extraction fails.")
        let service = ArticleContentExtractionService(
            loader: FixtureContentLoader(fixtureName: "unextractable-article", statusCode: 200)
        )

        let extractedArticle = await service.extractContent(for: article, now: fixedDate)

        XCTAssertEqual(extractedArticle.contentSource, .rssSummary)
        XCTAssertEqual(extractedArticle.content, "RSS summary remains available when webpage extraction fails.")
        XCTAssertEqual(extractedArticle.status, .parsed)
    }
}

private func makeArticle(rssSummary: String?, content: String? = nil) -> Article {
    Article(
        id: "article-1",
        feedID: "feed-1",
        title: "Article",
        url: URL(string: "https://example.com/article")!,
        rssSummary: rssSummary,
        content: content,
        createdAt: Date(timeIntervalSince1970: 1_700_000_000),
        updatedAt: Date(timeIntervalSince1970: 1_700_000_000)
    )
}

private struct FixtureContentLoader: FeedDataLoader {
    var fixtureName: String
    var statusCode: Int

    func data(from url: URL) async throws -> (Data, URLResponse) {
        let fixtureURL = Bundle.module.url(forResource: fixtureName, withExtension: "html")!
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

private struct FailingContentLoader: FeedDataLoader {
    func data(from url: URL) async throws -> (Data, URLResponse) {
        throw URLError(.cannotLoadFromNetwork)
    }
}

private let fixedDate = Date(timeIntervalSince1970: 1_778_889_600)
