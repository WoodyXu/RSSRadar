import Foundation
import RSSRadarCore
import XCTest
@testable import RSSRadarFeeds

final class OPMLImportServiceTests: XCTestCase {
    func testImportOPMLCreatesFeedsFromGroupedOutlinesAndRecordsErrors() throws {
        let store = CapturingOPMLFeedStore()
        let service = OPMLImportService(store: store)

        let result = try service.importOPML(data: fixtureData("feeds"), now: fixedDate)

        XCTAssertEqual(result.importedFeeds.map(\.title), [
            "AI Research",
            "Title Fallback",
            "untitled.example.com"
        ])
        XCTAssertEqual(result.importedFeeds.map { $0.url.absoluteString }, [
            "https://example.com/ai.xml",
            "https://fallback.example.com/rss.xml",
            "https://untitled.example.com/feed.xml"
        ])
        XCTAssertEqual(result.importedFeeds[0].siteURL?.absoluteString, "https://example.com/ai")
        XCTAssertEqual(result.importedFeeds.map(\.status), [.active, .active, .active])
        XCTAssertEqual(result.importedFeeds.map(\.createdAt), [fixedDate, fixedDate, fixedDate])
        XCTAssertEqual(result.importedFeeds, store.savedFeeds)

        XCTAssertEqual(result.skippedDuplicates.map(\.title), ["AI Research Duplicate"])
        XCTAssertEqual(result.skippedDuplicates.map { $0.xmlURL.absoluteString }, ["https://example.com/ai.xml"])
        XCTAssertEqual(result.errors, [
            OPMLImportErrorRecord(title: "Missing XML URL", reason: "Missing xmlUrl"),
            OPMLImportErrorRecord(title: "Broken URL", reason: "Invalid xmlUrl")
        ])
    }

    func testImportOPMLSkipsExistingFeedURLs() throws {
        let existingFeed = Feed(
            title: "Existing",
            url: URL(string: "https://example.com/ai.xml")!,
            createdAt: fixedDate,
            updatedAt: fixedDate
        )
        let store = CapturingOPMLFeedStore(existingFeeds: [existingFeed])
        let service = OPMLImportService(store: store)

        let result = try service.importOPML(data: fixtureData("feeds"), now: fixedDate)

        XCTAssertFalse(result.importedFeeds.contains { $0.url.absoluteString == "https://example.com/ai.xml" })
        XCTAssertEqual(result.skippedDuplicates.first?.title, "AI Research")
        XCTAssertEqual(result.skippedDuplicates.count, 2)
    }

    func testImportOPMLThrowsForInvalidXML() throws {
        let service = OPMLImportService()

        XCTAssertThrowsError(try service.importOPML(data: Data("<opml><body>".utf8), now: fixedDate)) { error in
            XCTAssertTrue(error is OPMLImportError)
        }
    }
}

private final class CapturingOPMLFeedStore: OPMLFeedStore {
    var existingFeeds: [Feed]
    private(set) var savedFeeds: [Feed] = []

    init(existingFeeds: [Feed] = []) {
        self.existingFeeds = existingFeeds
    }

    func fetchAll() throws -> [Feed] {
        existingFeeds
    }

    func save(_ feed: Feed) throws {
        savedFeeds.append(feed)
    }
}

private func fixtureData(_ name: String) throws -> Data {
    let fixtureURL = Bundle.module.url(forResource: name, withExtension: "opml")!
    return try Data(contentsOf: fixtureURL)
}

private let fixedDate = Date(timeIntervalSince1970: 1_778_889_600)
